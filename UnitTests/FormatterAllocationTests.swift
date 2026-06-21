//
//  FormatterAllocationTests.swift
//  OutRun
//

import Foundation
import XCTest
@testable import OutRun

final class FormatterAllocationTests: XCTestCase {

    func testFormattingHelpersDoNotAllocateFormattersInsideHotFunctions() throws {
        let dateSource = try readSource(at: "OutRun/Models/Formatting/CustomDateFormatting.swift")
        try assertFunctionBody(
            named: "dayString(forDate date: Date)",
            in: dateSource,
            path: "OutRun/Models/Formatting/CustomDateFormatting.swift",
            excludes: ["DateFormatter()"]
        )
        try assertFunctionBody(
            named: "dayString(forIdentifier dayIdentifier: String)",
            in: dateSource,
            path: "OutRun/Models/Formatting/CustomDateFormatting.swift",
            excludes: ["DateFormatter()"]
        )
        try assertFunctionBody(
            named: "dayIdentifier(forDate date: Date)",
            in: dateSource,
            path: "OutRun/Models/Formatting/CustomDateFormatting.swift",
            excludes: ["DateFormatter()"]
        )
        try assertFunctionBody(
            named: "timeString(forDate date: Date)",
            in: dateSource,
            path: "OutRun/Models/Formatting/CustomDateFormatting.swift",
            excludes: ["DateFormatter()"]
        )
        try assertFunctionBody(
            named: "backupTimeCode(forDate date: Date)",
            in: dateSource,
            path: "OutRun/Models/Formatting/CustomDateFormatting.swift",
            excludes: ["DateFormatter()"]
        )
        try assertFunctionBody(
            named: "fullDateString(forDate date: Date)",
            in: dateSource,
            path: "OutRun/Models/Formatting/CustomDateFormatting.swift",
            excludes: ["DateFormatter()"]
        )

        let measurementSource = try readSource(at: "OutRun/Models/Formatting/CustomMeasurementFormatting.swift")
        try assertFunctionBody(
            named: "string(forMeasurement measurement: NSMeasurement",
            in: measurementSource,
            path: "OutRun/Models/Formatting/CustomMeasurementFormatting.swift",
            excludes: ["MeasurementFormatter()", "DateComponentsFormatter()"]
        )
        try assertFunctionBody(
            named: "string(forUnit unit: Unit",
            in: measurementSource,
            path: "OutRun/Models/Formatting/CustomMeasurementFormatting.swift",
            excludes: ["MeasurementFormatter()", "DateComponentsFormatter()"]
        )

        let settingsSource = try readSource(at: "OutRun/Views/SwiftUI/Settings/SettingsView.swift")
        XCTAssertFalse(settingsSource.contains("MeasurementFormatter().string(from:"))

        let unitSelectionSource = try readSource(at: "OutRun/Views/SwiftUI/Settings/UnitSelectionView.swift")
        XCTAssertFalse(unitSelectionSource.contains("MeasurementFormatter().string(from:"))
    }

    func testFixedDateFormatsUseImmutablePOSIXConfiguration() throws {
        let source = try readSource(at: "OutRun/Models/Formatting/CustomDateFormatting.swift")

        XCTAssertTrue(
            source.contains("static let dayIDFormat = \"yyyyMMdd\""),
            "The day identifier format should be immutable so the cached formatter cannot desynchronize from the format string."
        )
        XCTAssertTrue(
            source.contains(#"Locale(identifier: "en_US_POSIX")"#),
            "Fixed date identifiers and backup filenames must use en_US_POSIX, not the user's display locale."
        )
        XCTAssertTrue(
            source.contains("formatter.locale = posixLocale"),
            "Fixed date formatter construction should assign the shared en_US_POSIX locale."
        )
        XCTAssertTrue(
            source.contains("formatter.calendar = gregorianCalendar"),
            "Fixed date formatter construction should pin the Gregorian calendar for non-Gregorian user calendar settings."
        )
    }

    func testFixedDateIdentifiersAndBackupCodesAreDeterministic() throws {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = TimeZone.current
        components.year = 2020
        components.month = 1
        components.day = 2
        components.hour = 3
        components.minute = 4
        components.second = 5
        let date = try XCTUnwrap(components.date)

        XCTAssertEqual(CustomDateFormatting.dayIdentifier(forDate: date), "20200102")
        XCTAssertEqual(CustomDateFormatting.dayString(forIdentifier: "20200102"), CustomDateFormatting.dayString(forDate: date))
        XCTAssertEqual(CustomDateFormatting.backupTimeCode(forDate: date), "20200102-030405")
    }

    func testUnitLabelsMatchFreshDefaultMeasurementFormatter() {
        let freshFormatter = MeasurementFormatter()
        let units: [Unit] = [
            UnitLength.kilometers,
            UnitLength.miles,
            UnitLength.meters,
            UnitLength.feet,
            UnitSpeed.kilometersPerHour,
            UnitSpeed.milesPerHour,
            UnitEnergy.kilocalories,
            UnitMass.kilograms,
            UnitMass.pounds
        ]

        for unit in units {
            XCTAssertEqual(
                CustomMeasurementFormatting.string(forUnit: unit),
                freshFormatter.string(from: unit),
                "Shared unit label formatter should match Foundation's default label for \(unit.symbol)."
            )
            XCTAssertEqual(CustomMeasurementFormatting.string(forUnit: unit, short: true), unit.symbol)
        }
    }

    func testClockAndPaceFormattingReturnExpectedPositionalStrings() {
        XCTAssertEqual(
            CustomMeasurementFormatting.string(
                forMeasurement: NSMeasurement(doubleValue: 3661, unit: UnitDuration.seconds),
                type: .clock
            ),
            "01:01:01"
        )
        XCTAssertEqual(
            CustomMeasurementFormatting.string(
                forMeasurement: NSMeasurement(doubleValue: 301, unit: UnitDuration.seconds),
                type: .pace
            ),
            "05:01"
        )
    }

    func testFormatterHelpersTolerateConcurrentAccess() {
        let iterations = 250
        let queue = DispatchQueue(label: "FormatterAllocationTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        let failures = Locked<[String]>([])

        for index in 0..<iterations {
            group.enter()
            queue.async {
                defer { group.leave() }
                let date = Date(timeIntervalSince1970: TimeInterval(index))
                let dayID = CustomDateFormatting.dayIdentifier(forDate: date)
                if dayID.count != 8 {
                    failures.withLock { $0.append("Unexpected day id: \(dayID)") }
                }
                if CustomDateFormatting.dayString(forIdentifier: dayID) == nil {
                    failures.withLock { $0.append("Could not parse day id: \(dayID)") }
                }
                if CustomDateFormatting.backupTimeCode(forDate: date).count != 15 {
                    failures.withLock { $0.append("Unexpected backup time code") }
                }
                if CustomMeasurementFormatting.string(forUnit: UnitLength.kilometers).isEmpty {
                    failures.withLock { $0.append("Empty unit label") }
                }
                if CustomMeasurementFormatting.string(
                    forMeasurement: NSMeasurement(doubleValue: 301, unit: UnitDuration.seconds),
                    type: .pace
                ) != "05:01" {
                    failures.withLock { $0.append("Unexpected pace string") }
                }
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        XCTAssertTrue(failures.withLock { $0 }.isEmpty, failures.withLock { $0 }.joined(separator: "\n"))
    }

    private func readSource(at relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func assertFunctionBody(named signatureFragment: String, in source: String, path: String, excludes forbiddenPatterns: [String]) throws {
        let body = try functionBody(named: signatureFragment, in: source)
        for pattern in forbiddenPatterns {
            XCTAssertFalse(
                body.contains(pattern),
                "\(path) should not allocate formatters inside \(signatureFragment): \(pattern)"
            )
        }
    }

    private func functionBody(named signatureFragment: String, in source: String) throws -> String {
        let signatureRange = try XCTUnwrap(source.range(of: "static func " + signatureFragment))
        let searchStart = signatureRange.upperBound
        let openingBrace = try XCTUnwrap(source[searchStart...].firstIndex(of: "{"))
        var depth = 0
        var index = openingBrace

        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            }
            index = source.index(after: index)
        }

        XCTFail("Could not find function body for \(signatureFragment)")
        return ""
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

}

private final class Locked<Value> {

    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

}
