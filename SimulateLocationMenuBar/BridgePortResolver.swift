import Darwin
import Foundation

struct PortOwner: Equatable {
    let pid: Int32
    let command: String
}

enum PortConflictChoice {
    case forceClose
    case useNextAvailablePort
    case cancel
}

struct BridgeHealthResponse: Decodable {
    let ok: Bool
    let service: String
}

protocol PortConflictPrompt {
    func chooseAction(port: Int, owners: [PortOwner]) async -> PortConflictChoice
}

enum BridgePortResolverError: LocalizedError {
    case cancelled
    case noAvailablePort
    case portReleaseFailed(Int)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return String(localized: "error.start_cancelled")
        case .noAvailablePort:
            return String(localized: "error.no_available_port")
        case let .portReleaseFailed(port):
            return String(format: String(localized: "error.port_release_failed_format"), port)
        }
    }
}

final class BridgePortResolver {
    func resolveStartPort(defaultPort: Int, prompt: PortConflictPrompt) async throws -> Int {
        let owners = findPortOwners(port: defaultPort)
        if owners.isEmpty {
            return defaultPort
        }
        if await isKnownBridge(port: defaultPort) {
            return defaultPort
        }

        switch await prompt.chooseAction(port: defaultPort, owners: owners) {
        case .forceClose:
            try await forceClose(owners: owners, port: defaultPort)
            return defaultPort
        case .useNextAvailablePort:
            return try await findNextAvailablePort(startingAt: defaultPort + 1)
        case .cancel:
            throw BridgePortResolverError.cancelled
        }
    }

    func waitUntilHealthy(port: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isKnownBridge(port: port) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func waitUntilReleased(port: Int, timeout: TimeInterval = MenuBarConstants.portReleaseTimeout) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if findPortOwners(port: port).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: UInt64(MenuBarConstants.portReleasePollInterval * 1_000_000_000))
        }
        return findPortOwners(port: port).isEmpty
    }

    private func findNextAvailablePort(startingAt startPort: Int) async throws -> Int {
        for offset in 0..<MenuBarConstants.maxPortProbeAttempts {
            let candidate = startPort + offset
            let owners = findPortOwners(port: candidate)
            if owners.isEmpty {
                return candidate
            }
            if await isKnownBridge(port: candidate) {
                return candidate
            }
        }
        throw BridgePortResolverError.noAvailablePort
    }

    private func forceClose(owners: [PortOwner], port: Int) async throws {
        for owner in owners {
            kill(owner.pid, SIGTERM)
        }

        guard await waitUntilReleased(port: port) else {
            throw BridgePortResolverError.portReleaseFailed(port)
        }
    }

    private func isKnownBridge(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(MenuBarConstants.healthPath)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = MenuBarConstants.bridgeHealthTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            let payload = try JSONDecoder().decode(BridgeHealthResponse.self, from: data)
            return payload.ok && payload.service == MenuBarConstants.serviceName
        } catch {
            return false
        }
    }

    private func findPortOwners(port: Int) -> [PortOwner] {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "pc"]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else {
            return []
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parsePortOwners(output)
    }

    private func parsePortOwners(_ output: String) -> [PortOwner] {
        var owners: [PortOwner] = []
        var currentPID: Int32?
        var currentCommand = ""

        for line in output.split(separator: "\n").map(String.init) {
            if line.hasPrefix("p") {
                if let currentPID {
                    owners.append(PortOwner(pid: currentPID, command: currentCommand))
                }
                currentPID = Int32(line.dropFirst())
                currentCommand = ""
            } else if line.hasPrefix("c") {
                currentCommand = String(line.dropFirst())
            }
        }

        if let currentPID {
            owners.append(PortOwner(pid: currentPID, command: currentCommand))
        }

        return owners
    }
}
