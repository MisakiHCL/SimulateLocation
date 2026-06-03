import Foundation

enum MenuBarConstants {
    static let defaultPort = 8765
    static let maxPortProbeAttempts = 20
    static let healthPath = "/health"
    static let serviceName = "SimulateLocation"
    static let projectRootInfoKey = "SLProjectRoot"
    static let bridgeStopTimeout: TimeInterval = 4
    static let bridgeHealthTimeout: TimeInterval = 0.5
    static let bridgeStartupTimeout: TimeInterval = 6
    static let portReleaseTimeout: TimeInterval = 3
    static let portReleasePollInterval: TimeInterval = 0.1
}

struct BridgePaths {
    let projectRoot: URL

    var bridgeScriptURL: URL {
        projectRoot.appendingPathComponent("Scripts/location-bridge")
    }

    var xcodeProjectURL: URL {
        projectRoot.appendingPathComponent("SimulateLocation.xcodeproj")
    }

    static func fromBundle(_ bundle: Bundle = .main) throws -> BridgePaths {
        guard let root = bundle.object(forInfoDictionaryKey: MenuBarConstants.projectRootInfoKey) as? String,
              !root.isEmpty else {
            throw BridgeProcessError.missingProjectRoot
        }

        return BridgePaths(projectRoot: URL(fileURLWithPath: root, isDirectory: true))
    }
}
