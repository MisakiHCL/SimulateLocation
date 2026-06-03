import CoreLocation
import Foundation

enum CoordinateSystemConverter {
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.006693421622965943
    private static let minimumChinaLatitude = 0.8293
    private static let maximumChinaLatitude = 55.8271
    private static let minimumChinaLongitude = 72.004
    private static let maximumChinaLongitude = 137.8347

    static func mapDisplayCoordinate(
        forGPXCoordinate coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        guard isInsideMainlandChina(coordinate) else {
            return coordinate
        }

        let delta = gcjOffset(for: coordinate)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + delta.latitude,
            longitude: coordinate.longitude + delta.longitude
        )
    }

    static func gpxCoordinate(
        forMapDisplayCoordinate coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        guard isInsideMainlandChina(coordinate) else {
            return coordinate
        }

        var result = coordinate
        for _ in 0..<3 {
            let displayCoordinate = mapDisplayCoordinate(forGPXCoordinate: result)
            result = CLLocationCoordinate2D(
                latitude: result.latitude + coordinate.latitude - displayCoordinate.latitude,
                longitude: result.longitude + coordinate.longitude - displayCoordinate.longitude
            )
        }

        return result
    }

    private static func isInsideMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minimumChinaLatitude
            && coordinate.latitude <= maximumChinaLatitude
            && coordinate.longitude >= minimumChinaLongitude
            && coordinate.longitude <= maximumChinaLongitude
    }

    private static func gcjOffset(for coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        var deltaLatitude = transformLatitude(
            x: coordinate.longitude - 105.0,
            y: coordinate.latitude - 35.0
        )
        var deltaLongitude = transformLongitude(
            x: coordinate.longitude - 105.0,
            y: coordinate.latitude - 35.0
        )

        let radianLatitude = coordinate.latitude / 180.0 * .pi
        var magic = sin(radianLatitude)
        magic = 1 - eccentricitySquared * magic * magic
        let sqrtMagic = sqrt(magic)

        deltaLatitude = (deltaLatitude * 180.0)
            / ((semiMajorAxis * (1 - eccentricitySquared)) / (magic * sqrtMagic) * .pi)
        deltaLongitude = (deltaLongitude * 180.0)
            / (semiMajorAxis / sqrtMagic * cos(radianLatitude) * .pi)

        return CLLocationCoordinate2D(latitude: deltaLatitude, longitude: deltaLongitude)
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y
            + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x
            + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return result
    }
}
