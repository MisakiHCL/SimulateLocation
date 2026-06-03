import CoreLocation
import Foundation

enum GPXGenerator {
    private static let coordinateFractionDigits = 6
    private static let creatorName = "SimulateLocation"

    static func waypointDocument(coordinate: CLLocationCoordinate2D, name: String) -> String {
        let latitude = formattedCoordinate(coordinate.latitude)
        let longitude = formattedCoordinate(coordinate.longitude)
        let escapedName = xmlEscaped(name)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="\(creatorName)">
          <wpt lat="\(latitude)" lon="\(longitude)">
            <name>\(escapedName)</name>
          </wpt>
        </gpx>

        """
    }

    private static func formattedCoordinate(_ value: CLLocationDegrees) -> String {
        String(format: "%.\(coordinateFractionDigits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
