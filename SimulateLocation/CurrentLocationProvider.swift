import CoreLocation
import Foundation

enum CurrentLocationError {
    case permissionDenied
    case simulatedBySoftware
    case lowAccuracy
    case unavailable
}

struct LocationFix {
    let coordinate: CLLocationCoordinate2D
    let horizontalAccuracy: CLLocationAccuracy
    let isSimulatedBySoftware: Bool
    let timestamp: Date

    init(location: CLLocation) {
        coordinate = location.coordinate
        horizontalAccuracy = location.horizontalAccuracy
        isSimulatedBySoftware = location.sourceInformation?.isSimulatedBySoftware == true
        timestamp = location.timestamp
    }

    func isUsable(maximumAge: TimeInterval, maximumHorizontalAccuracy: CLLocationAccuracy) -> Bool {
        let age = abs(timestamp.timeIntervalSinceNow)
        return !isSimulatedBySoftware
            && horizontalAccuracy >= 0
            && horizontalAccuracy <= maximumHorizontalAccuracy
            && age <= maximumAge
    }
}

final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private static let maximumLocationAge: TimeInterval = 30
    private static let maximumHorizontalAccuracy: CLLocationAccuracy = 50
    private static let locationTimeout: TimeInterval = 8

    @Published private(set) var isLocating = false

    private let manager: CLLocationManager
    private var onSuccess: ((LocationFix) -> Void)?
    private var onFailure: ((CurrentLocationError) -> Void)?
    private var bestFix: LocationFix?
    private var timeoutWorkItem: DispatchWorkItem?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
        self.manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestCurrentLocation(
        onSuccess: @escaping (LocationFix) -> Void,
        onFailure: @escaping (CurrentLocationError) -> Void
    ) {
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        bestFix = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if let cachedFix = recentCachedFix(), cachedFix.isUsable(
                maximumAge: Self.maximumLocationAge,
                maximumHorizontalAccuracy: Self.maximumHorizontalAccuracy
            ) {
                finishWithSuccess(cachedFix)
                return
            }

            requestLocation()
        case .denied, .restricted:
            finishWithFailure(.permissionDenied)
        @unknown default:
            finishWithFailure(.unavailable)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied, .restricted:
            finishWithFailure(.permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            finishWithFailure(.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else {
            finishWithFailure(.unavailable)
            return
        }

        for location in locations {
            let fix = LocationFix(location: location)

            if fix.isSimulatedBySoftware {
                finishWithFailure(.simulatedBySoftware)
                return
            }

            if fix.isUsable(
                maximumAge: Self.maximumLocationAge,
                maximumHorizontalAccuracy: Self.maximumHorizontalAccuracy
            ) {
                finishWithSuccess(fix)
                return
            }

            if bestFix == nil || fix.horizontalAccuracy < bestFix!.horizontalAccuracy {
                bestFix = fix
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishWithFailure(.unavailable)
    }

    private func recentCachedFix() -> LocationFix? {
        guard let location = manager.location else {
            return nil
        }

        return LocationFix(location: location)
    }

    private func requestLocation() {
        isLocating = true
        manager.startUpdatingLocation()
        scheduleTimeout()
    }

    private func finishWithSuccess(_ fix: LocationFix) {
        isLocating = false
        stopLocationUpdates()
        onSuccess?(fix)
        clearCallbacks()
    }

    private func finishWithFailure(_ error: CurrentLocationError) {
        isLocating = false
        stopLocationUpdates()
        onFailure?(error)
        clearCallbacks()
    }

    private func scheduleTimeout() {
        timeoutWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isLocating else {
                return
            }

            if self.bestFix != nil {
                self.finishWithFailure(.lowAccuracy)
            } else {
                self.finishWithFailure(.unavailable)
            }
        }

        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.locationTimeout, execute: workItem)
    }

    private func stopLocationUpdates() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        manager.stopUpdatingLocation()
    }

    private func clearCallbacks() {
        onSuccess = nil
        onFailure = nil
        bestFix = nil
    }
}
