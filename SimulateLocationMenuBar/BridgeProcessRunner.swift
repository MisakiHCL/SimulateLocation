import AppKit
import Foundation

struct CommandResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum BridgeProcessError: LocalizedError {
    case missingProjectRoot
    case missingBridgeScript(String)
    case missingXcodeProject(String)
    case commandFailed(String)
    case commandTimedOut(String)

    var errorDescription: String? {
        switch self {
        case .missingProjectRoot:
            return String(localized: "error.project_root_missing")
        case let .missingBridgeScript(path):
            return String(format: String(localized: "error.bridge_script_missing_format"), path)
        case let .missingXcodeProject(path):
            return String(format: String(localized: "error.xcode_project_missing_format"), path)
        case let .commandFailed(message):
            return message
        case let .commandTimedOut(command):
            return String(format: String(localized: "error.command_timeout_format"), command)
        }
    }
}

final class BridgeProcessRunner {
    private let paths: BridgePaths

    init(paths: BridgePaths) {
        self.paths = paths
    }

    func startBridge(port: Int) throws -> Process {
        try validateBridgeScript()

        let process = Process()
        process.executableURL = paths.bridgeScriptURL
        process.arguments = ["--port", String(port)]
        process.currentDirectoryURL = paths.projectRoot
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    func stopBridge(port: Int) async throws {
        let result = try await runBridgeScript(
            arguments: ["--stop", "--port", String(port)],
            timeout: MenuBarConstants.bridgeStopTimeout
        )

        guard result.exitCode == 0 else {
            let message = result.standardError.isEmpty ? result.standardOutput : result.standardError
            throw BridgeProcessError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func openXcodeProject() throws {
        guard FileManager.default.fileExists(atPath: paths.xcodeProjectURL.path) else {
            throw BridgeProcessError.missingXcodeProject(paths.xcodeProjectURL.path)
        }

        NSWorkspace.shared.open(paths.xcodeProjectURL)
    }

    private func validateBridgeScript() throws {
        guard FileManager.default.isExecutableFile(atPath: paths.bridgeScriptURL.path) else {
            throw BridgeProcessError.missingBridgeScript(paths.bridgeScriptURL.path)
        }
    }

    private func runBridgeScript(arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try validateBridgeScript()

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = self.paths.bridgeScriptURL
            process.arguments = arguments
            process.currentDirectoryURL = self.paths.projectRoot
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            if process.isRunning {
                process.terminate()
                throw BridgeProcessError.commandTimedOut(self.paths.bridgeScriptURL.lastPathComponent)
            }

            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return CommandResult(exitCode: process.terminationStatus, standardOutput: output, standardError: error)
        }.value
    }
}
