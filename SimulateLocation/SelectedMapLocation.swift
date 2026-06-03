import CoreLocation

struct SelectedMapLocation {
    let gpxCoordinate: CLLocationCoordinate2D
    let mapDisplayCoordinate: CLLocationCoordinate2D

    init(gpxCoordinate: CLLocationCoordinate2D) {
        self.gpxCoordinate = gpxCoordinate
        mapDisplayCoordinate = CoordinateSystemConverter.mapDisplayCoordinate(
            forGPXCoordinate: gpxCoordinate
        )
    }

    init(mapDisplayCoordinate: CLLocationCoordinate2D) {
        self.mapDisplayCoordinate = mapDisplayCoordinate
        gpxCoordinate = CoordinateSystemConverter.gpxCoordinate(
            forMapDisplayCoordinate: mapDisplayCoordinate
        )
    }
}
