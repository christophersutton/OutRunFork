#if STORAGE_VALIDATION_PORTABLE
// Foundation-only validation harness. The app's CoreStore/HealthKit-backed enum namespaces and
// interfaces are represented here so the unmodified current Codable payload and validator can run
// on macOS without building/launching the iOS app. These shims do not implement persistence.
import Foundation

public enum OutRunV4 {
    public enum Workout {
        public enum WorkoutType: Int, Codable { case running = 0, walking = 1, hiking = 4, unknown = -1 }
    }
    public enum WorkoutPause {
        public enum WorkoutPauseType: Int, Codable { case manual = 0, automatic = 1 }
    }
    public enum WorkoutEvent {
        public enum WorkoutEventType: Int, Codable { case lap = 0, marker = 1, segment = 2, unknown = -1 }
    }
}

public protocol ORWorkoutHeartRateDataSampleInterface {}
public protocol ORWorkoutRouteDataSampleInterface {}
public protocol ORWorkoutPauseInterface {}
public protocol ORWorkoutEventInterface {}
public protocol OREventInterface {}

public typealias TempWorkout = TempV4.Workout
public typealias TempWorkoutPause = TempV4.WorkoutPause
public typealias TempWorkoutEvent = TempV4.WorkoutEvent
public typealias TempWorkoutRouteDataSample = TempV4.WorkoutRouteDataSample
public typealias TempWorkoutHeartRateDataSample = TempV4.WorkoutHeartRateDataSample
public typealias TempEvent = TempV4.Event
extension TempWorkoutPause: ORWorkoutPauseInterface {}
extension TempWorkoutEvent: ORWorkoutEventInterface {}
extension TempWorkoutRouteDataSample: ORWorkoutRouteDataSampleInterface {}
extension TempWorkoutHeartRateDataSample: ORWorkoutHeartRateDataSampleInterface {}

func throwOnAccess<T>() -> T { fatalError("Relationship must not be read by the validation harness") }

// Platform service declarations needed to compile RootRouter. Router tests inject setup and
// preferences and never call these services; accidental access to app storage/Health/UI fails fast.
enum OutRunV3to4 {}
enum PortableStoreError: Error { case userCancelled }
enum DataManager {
    enum SetupError: Error {
        case failedToAddStorage(error: PortableStoreError)
        case intermediateMappingActionsFailed(version: OutRunV3to4.Type)
        var debugDescription: String {
            switch self {
            case .failedToAddStorage: return "Injected add-storage failure"
            case .intermediateMappingActionsFailed: return "Injected intermediate-mapping failure"
            }
        }
    }
    enum DeleteError: Error { case notSaved }
    static func setup(completion: @escaping (SetupError?) -> Void, migration: @escaping (Progress) -> Void) {
        fatalError("Tests must inject setup; no application storage access is allowed")
    }
}
final class PortablePreference<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
enum UserPreferences { static let isSetUp = PortablePreference(false) }
enum Config {
    static let version = "test"
    static let changeLogs: [String: String] = [:]
}
enum HealthStoreManager {
    static func setupObservers() { fatalError("No Health access is allowed in these tests") }
}
class UIViewController {
    var presentingViewController: UIViewController? { fatalError("No app UI access is allowed") }
    var presentedViewController: UIViewController? { fatalError("No app UI access is allowed") }
    var isBeingDismissed: Bool { fatalError("No app UI access is allowed") }
    var viewIfLoaded: PortableView? { fatalError("No app UI access is allowed") }
    func present(_ controller: UIViewController, animated: Bool) { fatalError("No app UI access is allowed") }
}
class UIAlertController: UIViewController {}
class NewWorkoutViewController: UIViewController {}
class PortableView { var window: Bool? { fatalError("No app UI access is allowed") } }
enum WorkoutBuilder {
    static var recoveryURL: URL { fatalError("Tests must inject recovery; no application files may be read") }
}
class UIApplication {
    static let shared = UIApplication()
    var topMostViewController: UIViewController? { fatalError("No app UI access is allowed in these tests") }
}
enum AppDelegate {
    static let lastVersion = PortablePreference<String?>(nil)
    static func checkPermissionStatus(controller: UIViewController, completion: @escaping () -> Void) {
        fatalError("No permission access is allowed in these tests")
    }
}
extension Progress {
    func setProgressHandler(_ handler: @escaping (Progress) -> Void) {}
}
#endif
