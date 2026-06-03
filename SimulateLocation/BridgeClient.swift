import CoreLocation
import Foundation

private enum BridgeConstants {
    static let applyPath = "/apply"
    static let httpScheme = "http"
}

struct BridgeEndpoint: Equatable {
    let host: String
    let port: Int

    var displayName: String {
        "\(normalizedHost):\(port)"
    }

    var applyURL: URL? {
        var components = URLComponents()
        components.scheme = BridgeConstants.httpScheme
        components.host = normalizedHost
        components.port = port
        components.path = BridgeConstants.applyPath
        return components.url
    }

    private var normalizedHost: String {
        host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

struct BridgeApplyRequest: Encodable {
    let latitude: Double
    let longitude: Double
    let name: String

    init(latitude: Double, longitude: Double, name: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }

    init(coordinate: CLLocationCoordinate2D, name: String) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.name = name
    }
}

struct BridgeApplyResponse: Decodable {
    let ok: Bool
    let latestPath: String?
    let historyPath: String?
    let applied: [String]
    let warnings: [String]
    let message: String?
}

enum BridgeClientError: Error {
    case endpointUnavailable
    case invalidResponse
    case serverRejected(String)
}

final class BridgeClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func apply(
        coordinate: CLLocationCoordinate2D,
        name: String,
        endpoint: BridgeEndpoint
    ) async throws -> BridgeApplyResponse {
        guard let url = endpoint.applyURL else {
            throw BridgeClientError.endpointUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            BridgeApplyRequest(coordinate: coordinate, name: name)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(BridgeApplyResponse.self, from: data)
        guard (200..<300).contains(httpResponse.statusCode), decoded.ok else {
            throw BridgeClientError.serverRejected(decoded.message ?? "Bridge rejected the request.")
        }

        return decoded
    }
}
