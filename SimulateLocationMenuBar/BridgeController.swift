import AppKit
import Combine
import Foundation

enum BridgeStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case stopping
    case error(String)

    var title: String {
        switch self {
        case .stopped:
            return String(localized: "status.stopped")
        case .starting:
            return String(localized: "status.starting")
        case let .running(port):
            return String(format: String(localized: "status.running_format"), port)
        case .stopping:
            return String(localized: "status.stopping")
        case .error:
            return String(localized: "status.error")
        }
    }

    var systemImage: String {
        switch self {
        case .running:
            return "location.fill"
        case .starting, .stopping:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle.fill"
        case .stopped:
            return "location"
        }
    }
}

@MainActor
final class BridgeController: ObservableObject {
    @Published private(set) var status: BridgeStatus = .stopped

    var canStart: Bool {
        if case .starting = status { return false }
        if case .stopping = status { return false }
        return true
    }

    var canStop: Bool {
        if case .running = status { return true }
        if activePort != nil { return true }
        return false
    }

    private let runner: BridgeProcessRunner
    private let resolver: BridgePortResolver
    private let prompt: PortConflictPrompt
    private var activePort: Int?
    private var bridgeProcess: Process?

    init(
        runner: BridgeProcessRunner? = nil,
        resolver: BridgePortResolver = BridgePortResolver(),
        prompt: PortConflictPrompt = NativePortConflictPrompt()
    ) {
        do {
            let paths = try BridgePaths.fromBundle()
            self.runner = runner ?? BridgeProcessRunner(paths: paths)
        } catch {
            self.runner = runner ?? BridgeProcessRunner(
                paths: BridgePaths(projectRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            )
            self.status = .error(error.localizedDescription)
        }
        self.resolver = resolver
        self.prompt = prompt
    }

    func refreshStatus() async {
        let port = activePort ?? MenuBarConstants.defaultPort
        if await resolver.waitUntilHealthy(port: port, timeout: MenuBarConstants.bridgeHealthTimeout) {
            activePort = port
            status = .running(port: port)
        } else if case .running = status {
            activePort = nil
            status = .stopped
        }
    }

    func start() async {
        guard canStart else {
            return
        }

        status = .starting

        do {
            let port = try await resolver.resolveStartPort(defaultPort: MenuBarConstants.defaultPort, prompt: prompt)
            bridgeProcess = try runner.startBridge(port: port)

            guard await resolver.waitUntilHealthy(port: port, timeout: MenuBarConstants.bridgeStartupTimeout) else {
                bridgeProcess?.terminate()
                activePort = nil
                status = .error(String(localized: "error.bridge_health_failed"))
                NativeOperationAlert.showError(String(localized: "error.bridge_health_failed"))
                return
            }

            activePort = port
            status = .running(port: port)

            do {
                try runner.openXcodeProject()
            } catch {
                NativeOperationAlert.showWarning(error.localizedDescription)
            }
        } catch {
            activePort = nil
            status = .error(error.localizedDescription)
            NativeOperationAlert.showError(error.localizedDescription)
        }
    }

    func stop() async {
        await stopBridge(shouldShowErrors: true)
    }

    func quit() async {
        let didStop = await stopBridge(shouldShowErrors: true)
        if didStop {
            NSApplication.shared.terminate(nil)
        }
    }

    @discardableResult
    private func stopBridge(shouldShowErrors: Bool) async -> Bool {
        let port = activePort ?? MenuBarConstants.defaultPort
        status = .stopping

        do {
            try await runner.stopBridge(port: port)
            _ = await resolver.waitUntilReleased(port: port)
            bridgeProcess = nil
            activePort = nil
            status = .stopped
            return true
        } catch {
            status = .error(error.localizedDescription)
            if shouldShowErrors {
                NativeOperationAlert.showError(error.localizedDescription)
            }
            return false
        }
    }
}
