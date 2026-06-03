import CoreLocation
import MapKit
import SwiftUI

struct MapFocusRequest {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let span: MKCoordinateSpan
}

struct InteractiveMapView: UIViewRepresentable {
    let initialRegion: MKCoordinateRegion?
    @Binding var selectedLocation: SelectedMapLocation?
    let focusRequest: MapFocusRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(.follow, animated: false)
        if let initialRegion {
            mapView.setRegion(initialRegion, animated: false)
        }

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tapRecognizer)

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncSelection(on: mapView)

        guard let focusRequest,
              context.coordinator.lastFocusRequestID != focusRequest.id else {
            return
        }

        context.coordinator.lastFocusRequestID = focusRequest.id
        mapView.setRegion(
            MKCoordinateRegion(center: focusRequest.coordinate, span: focusRequest.span),
            animated: true
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveMapView
        weak var mapView: MKMapView?
        var lastFocusRequestID: UUID?

        private let selectionAnnotation = MKPointAnnotation()
        private var isShowingSelection = false

        init(parent: InteractiveMapView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let mapView else {
                return
            }

            let point = recognizer.location(in: mapView)
            let mapDisplayCoordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.selectedLocation = SelectedMapLocation(mapDisplayCoordinate: mapDisplayCoordinate)
        }

        func syncSelection(on mapView: MKMapView) {
            guard let selectedLocation = parent.selectedLocation else {
                if isShowingSelection {
                    mapView.removeAnnotation(selectionAnnotation)
                    isShowingSelection = false
                }
                return
            }

            selectionAnnotation.coordinate = selectedLocation.mapDisplayCoordinate
            selectionAnnotation.title = String(localized: "map.selected_marker")

            if !isShowingSelection {
                mapView.addAnnotation(selectionAnnotation)
                isShowingSelection = true
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation === selectionAnnotation else {
                return nil
            }

            let identifier = "selected-location"
            let markerView = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(
                annotation: annotation,
                reuseIdentifier: identifier
            )
            markerView.annotation = annotation
            markerView.markerTintColor = .systemRed
            markerView.canShowCallout = false
            return markerView
        }
    }
}
