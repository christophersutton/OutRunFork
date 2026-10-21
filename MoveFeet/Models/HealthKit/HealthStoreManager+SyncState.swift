import Foundation
import CryptoKit

/// Queue confined to the main queue by its caller. A failed batch invalidates all
/// later callbacks; a new observer must restart from the last committed anchor.
final class HealthImportBatchQueue {
    typealias Operation = (@escaping (Bool) -> Void) -> Void
    private var pending: [(Operation, () -> Void, () -> Void)] = []
    private var running = false
    private var generation = 0
    private(set) var blocked = false

    func reset() {
        generation += 1
        pending.removeAll()
        running = false
        blocked = false
    }

    func enqueue(process: @escaping Operation, commit: @escaping () -> Void, failure: @escaping () -> Void) {
        guard !blocked else { return }
        pending.append((process, commit, failure))
        drain()
    }

    private func drain() {
        guard !running, !blocked, !pending.isEmpty else { return }
        running = true
        let (process, commit, failure) = pending.removeFirst()
        let token = generation
        var completed = false
        process { success in
            guard !completed, token == self.generation, self.running else { return }
            completed = true
            self.running = false
            if success {
                commit()
                self.drain()
            } else {
                self.blocked = true
                self.pending.removeAll()
                failure()
            }
        }
    }
}

/// Shared by manual and automatic imports, so their duplicate checks and writes
/// cannot race each other. Also used to serialize exports of the same parent.
final class HealthSerialOperations {
    private var pending: [(@escaping () -> Void) -> Void] = []
    private var running = false

    func enqueue(_ operation: @escaping (@escaping () -> Void) -> Void) {
        pending.append(operation)
        drain()
    }

    private func drain() {
        guard !running, !pending.isEmpty else { return }
        running = true
        let operation = pending.removeFirst()
        var completed = false
        operation {
            guard !completed else { return }
            completed = true
            self.running = false
            self.drain()
        }
    }
}

/// No workout payload: only local/Health identities and completed attachment groups.
/// Corrupt/unknown data fails closed; it must never silently enable a second export.
final class HealthExportLedger {
    struct Entry: Codable, Equatable {
        var parent: UUID?
        var completed: Set<String> = []
        var contentDigest: String?
    }
    enum LedgerError: Error { case invalidData }
    static let attachmentKeys: Set<String> = ["distance", "energy", "steps", "heartRate", "route"]
    private let defaults: UserDefaults
    private let key = "com.wcc.movefeet.healthExportRetry.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func entries() throws -> [String: Entry] {
        guard defaults.object(forKey: key) != nil else { return [:] }
        guard let data = defaults.data(forKey: key), data.count <= 4_000_000,
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data),
              entries.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.value.completed.isSubset(of: Self.attachmentKeys) })
        else { throw LedgerError.invalidData }
        return entries
    }

    func entry(for id: UUID) throws -> Entry? { try entries()[id.uuidString] }
    func pendingIDs() throws -> Set<UUID> {
        Set(try entries().keys.compactMap(UUID.init(uuidString:)))
    }
    func set(_ entry: Entry?, for id: UUID) throws {
        guard entry?.completed.isSubset(of: Self.attachmentKeys) ?? true else { throw LedgerError.invalidData }
        var values = try entries()
        values[id.uuidString] = entry
        defaults.set(try JSONEncoder().encode(values), forKey: key)
    }
}

/// Bind completed attachments to the values that produced them without putting workout
/// contents in the retry preferences. Sorted JSON keeps the digest stable across launches.
enum HealthExportFingerprint {
    static func digest<Content: Encodable>(_ content: Content) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(content)).map { String(format: "%02x", $0) }.joined()
    }

    static func canResume(recorded: String?, current: String) -> Bool {
        recorded == nil || recorded == current
    }
}

/// Await every attachment and record each successful group before moving on.
/// Failed groups remain pending, while already completed groups are never repeated.
enum HealthAttachmentBatch {
    static func run(keys: [String], completed: Set<String>,
                    attach: @escaping (String, @escaping (Bool) -> Void) -> Void,
                    checkpoint: @escaping (String) -> Bool,
                    completion: @escaping (Bool) -> Void) {
        func next(_ index: Int, _ succeeded: Bool) {
            guard index < keys.count else { completion(succeeded); return }
            let key = keys[index]
            guard !completed.contains(key) else { next(index + 1, succeeded); return }
            attach(key) { success in
                let saved = success && checkpoint(key)
                next(index + 1, succeeded && saved)
            }
        }
        next(0, true)
    }
}

enum HealthImportValues {
    static func addingSteps(_ previous: Int?, _ sample: Int) -> Int { (previous ?? 0) + sample }
}

/// A workout can contain several Health routes. Import is complete only after every
/// segment is read; a failed segment must keep the observer's previous anchor.
enum HealthRouteCollection {
    static func collect<Route, Location>(routes: [Route],
        query: @escaping (Route, @escaping (Result<[Location], Error>) -> Void) -> Void,
        completion: @escaping (Result<[Location], Error>) -> Void) {
        var locations: [Location] = []
        func next(_ index: Int) {
            guard index < routes.count else { completion(.success(locations)); return }
            var finished = false
            query(routes[index]) { result in
                guard !finished else { return }
                finished = true
                switch result {
                case .failure(let error): completion(.failure(error))
                case .success(let segment):
                    locations.append(contentsOf: segment)
                    next(index + 1)
                }
            }
        }
        next(0)
    }
}

/// Per-feature request policy, independent of HealthKit's private read decisions.
struct HealthAccessPlan: Equatable {
    enum Kind: String, CaseIterable {
        case workout, route, distance, energy, steps, heartRate, bodyMass
    }
    var read: Set<Kind> = []
    var write: Set<Kind> = []
    init(workouts: Bool, weight: Bool) {
        if workouts {
            read = [.workout, .route, .steps, .heartRate]
            write = [.workout, .route, .distance, .energy, .steps, .heartRate]
        }
        if weight { read.insert(.bodyMass) }
    }
}

struct HealthImportIdentities {
    var health: Set<UUID>
    var local: Set<UUID>
}

/// Persistence seam shared by UI and observer imports. Query failures and partial
/// writes fail closed, while duplicate rows count as successful processing.
final class HealthImportPersistence<Record> {
    typealias Query = (@escaping (HealthImportIdentities?) -> Void) -> Void
    private let operations = HealthSerialOperations()
    private let identity: (Record) -> UUID
    private let isLocalExport: (Record, Set<UUID>) -> Bool
    private let prepare: (Record) -> Void
    private let query: Query
    private let save: ([Record], @escaping (Bool) -> Void) -> Void

    init(identity: @escaping (Record) -> UUID,
         isLocalExport: @escaping (Record, Set<UUID>) -> Bool,
         prepare: @escaping (Record) -> Void,
         query: @escaping Query,
         save: @escaping ([Record], @escaping (Bool) -> Void) -> Void) {
        self.identity = identity
        self.isLocalExport = isLocalExport
        self.prepare = prepare
        self.query = query
        self.save = save
    }

    func persist(_ records: [Record], completion: @escaping (Bool) -> Void) {
        operations.enqueue { done in
            self.query { existing in
                guard let existing = existing else { completion(false); done(); return }
                var seen = existing.health
                let unique = records.filter {
                    !self.isLocalExport($0, existing.local) && seen.insert(self.identity($0)).inserted
                }
                guard !unique.isEmpty else { completion(true); done(); return }
                unique.forEach(self.prepare)
                self.save(unique) { success in
                    guard success else { completion(false); done(); return }
                    self.query { persisted in
                        completion(persisted.map { ids in unique.allSatisfy { ids.health.contains(self.identity($0)) } } ?? false)
                        done()
                    }
                }
            }
        }
    }
}

/// Validate every recovered parent before attaching or accepting its identity.
/// The query adapter also constrains source and externalUUID in HealthKit itself.
enum HealthExportRecovery {
    static func canReuse(expectedStart: Date, expectedEnd: Date, expectedActivity: UInt,
                         start: Date, end: Date, activity: UInt,
                         parent: UUID, ledgerParent: UUID?,
                         expectedDistance: Double? = nil, distance: Double? = nil,
                         expectedEnergy: Double? = nil, energy: Double? = nil) -> Bool {
        expectedStart == start && expectedEnd == end && expectedActivity == activity &&
            expectedDistance == distance && expectedEnergy == energy &&
            (ledgerParent == nil || ledgerParent == parent)
    }
    static func canCreate(ledgerParent: UUID?, localReference: UUID?) -> Bool {
        ledgerParent == nil && localReference == nil
    }
}

/// A failed Health add may have saved some samples before attachment completed.
/// Reuse those identities; create only samples absent from the scoped lookup.
enum HealthSampleRecovery {
    enum Action: Equatable {
        case create(Int)
        case attach(UUID)
    }
    static func plan(expected: [String], saved: [String: [UUID]], attached: Set<UUID>) -> [Action]? {
        var result: [Action] = []
        for (index, identifier) in expected.enumerated() {
            let matches = saved[identifier] ?? []
            guard matches.count <= 1 else { return nil }
            if let id = matches.first {
                if !attached.contains(id) { result.append(.attach(id)) }
            } else {
                result.append(.create(index))
            }
        }
        return result
    }
}
