import CoreLocation
import MapKit
import SwiftUI
import UIKit

private enum AppConstants {
    static let coordinatePrecision = 6
    static let currentLocationSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
}

private enum AppLayout {
    static let panelMaxWidth: CGFloat = 560
    static let panelScreenPadding: CGFloat = 16
    static let panelBottomPadding: CGFloat = 16
    static let panelPadding: CGFloat = 16
    static let panelSpacing: CGFloat = 12
    static let panelCornerRadius: CGFloat = 8
    static let panelShadowOpacity: CGFloat = 0.16
    static let panelShadowRadius: CGFloat = 16
    static let panelShadowYOffset: CGFloat = 8
    static let buttonSpacing: CGFloat = 8
    static let informationSpacing: CGFloat = 8
    static let selectionDetailsSpacing: CGFloat = 8
    static let selectionDetailsHeight: CGFloat = 80
    static let bridgeStatusHeight: CGFloat = 20
    static let coordinateRowSpacing: CGFloat = 8
    static let coordinateSpacerMinLength: CGFloat = 16
    static let emptySelectionVerticalPadding: CGFloat = 8
}

private enum L10n {
    static let appTitle = LocalizedStringKey("app.title")
    static let instruction = LocalizedStringKey("map.instruction")
    static let selectedTitle = LocalizedStringKey("selection.title")
    static let noSelection = LocalizedStringKey("selection.empty")
    static let latitudeLabel = LocalizedStringKey("coordinate.latitude")
    static let longitudeLabel = LocalizedStringKey("coordinate.longitude")
    static let currentLocationButton = LocalizedStringKey("action.current_location")
    static let locatingButton = LocalizedStringKey("action.locating")
    static let applyButton = LocalizedStringKey("action.apply_location")
    static let applyingButton = LocalizedStringKey("action.applying")
    static let clearButton = LocalizedStringKey("action.clear")
    static let bridgeErrorTitle = LocalizedStringKey("bridge.error.title")
    static let bridgeNotFoundMessage = String(localized: "bridge.error.not_found")
    static let bridgeNetworkMessage = String(localized: "bridge.error.network")
    static let bridgeFailedFormat = String(localized: "bridge.error.failed_format")
    static let bridgeSearchingStatus = LocalizedStringKey("bridge.status.searching")
    static let bridgeNotFoundStatus = LocalizedStringKey("bridge.status.not_found")
    static let bridgeConnectedFormat = String(localized: "bridge.status.connected_format")
    static let bridgeApplySuccess = String(localized: "bridge.apply.success")
    static let bridgeApplyPartialFormat = String(localized: "bridge.apply.partial_format")
    static let locationErrorTitle = LocalizedStringKey("location.error.title")
    static let locationPermissionDeniedMessage = LocalizedStringKey("location.error.permission_denied")
    static let locationSimulatedMessage = LocalizedStringKey("location.error.simulated")
    static let locationLowAccuracyMessage = LocalizedStringKey("location.error.low_accuracy")
    static let locationUnavailableMessage = LocalizedStringKey("location.error.unavailable")
    static let okButton = LocalizedStringKey("action.ok")
    static let selectedMarker = LocalizedStringKey("map.selected_marker")
    static let gpxLocationName = String(localized: "gpx.location_name")
}

struct ContentView: View {
    @StateObject private var locationProvider = CurrentLocationProvider()
    @StateObject private var bridgeBrowser = BridgeServiceBrowser()
    @State private var selectedLocation: SelectedMapLocation?
    @State private var focusRequest: MapFocusRequest?
    @State private var locationAlert: LocationAlert?
    @State private var bridgeAlert: BridgeAlert?
    @State private var bridgeStatusMessage: String?
    @State private var isApplyingLocation = false
    @State private var startupLocationPolicy = StartupLocationPolicy()

    private let bridgeClient = BridgeClient()

    var body: some View {
        ZStack(alignment: .bottom) {
            InteractiveMapView(
                initialRegion: nil,
                selectedLocation: $selectedLocation,
                focusRequest: focusRequest
            )
            .ignoresSafeArea()

            controlPanel
                .frame(maxWidth: AppLayout.panelMaxWidth)
                .padding(.horizontal, AppLayout.panelScreenPadding)
                .padding(.bottom, AppLayout.panelBottomPadding)
        }
        .alert(item: $locationAlert) { alert in
            Alert(
                title: Text(L10n.locationErrorTitle),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.okButton))
            )
        }
        .alert(item: $bridgeAlert) { alert in
            Alert(
                title: Text(L10n.bridgeErrorTitle),
                message: Text(alert.message),
                dismissButton: .default(Text(L10n.okButton))
            )
        }
        .onAppear(perform: requestStartupLocationIfNeeded)
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: AppLayout.panelSpacing) {
            Text(L10n.appTitle)
                .font(.title2.weight(.semibold))

            Text(L10n.instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            informationArea

            HStack(spacing: AppLayout.buttonSpacing) {
                Button(action: centerOnCurrentLocation) {
                    Label(
                        locationProvider.isLocating ? L10n.locatingButton : L10n.currentLocationButton,
                        systemImage: "location.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(locationProvider.isLocating)

                Button(action: applySelectedLocation) {
                    Label(
                        isApplyingLocation ? L10n.applyingButton : L10n.applyButton,
                        systemImage: "bolt.fill"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedLocation == nil || bridgeBrowser.endpoint == nil || isApplyingLocation)

                Button(action: clearSelection) {
                    Label(L10n.clearButton, systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(selectedLocation == nil)
            }
        }
        .padding(AppLayout.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: AppLayout.panelCornerRadius, style: .continuous)
        )
        .shadow(
            color: .black.opacity(AppLayout.panelShadowOpacity),
            radius: AppLayout.panelShadowRadius,
            y: AppLayout.panelShadowYOffset
        )
    }

    private var informationArea: some View {
        VStack(alignment: .leading, spacing: AppLayout.informationSpacing) {
            selectionDetails
                .frame(height: AppLayout.selectionDetailsHeight, alignment: .topLeading)

            bridgeStatus
                .frame(height: AppLayout.bridgeStatusHeight, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var selectionDetails: some View {
        if let selectedLocation {
            VStack(alignment: .leading, spacing: AppLayout.selectionDetailsSpacing) {
                Text(L10n.selectedTitle)
                    .font(.headline)

                coordinateRow(label: L10n.latitudeLabel, value: selectedLocation.gpxCoordinate.latitude)
                coordinateRow(label: L10n.longitudeLabel, value: selectedLocation.gpxCoordinate.longitude)
            }
        } else {
            Text(L10n.noSelection)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, AppLayout.emptySelectionVerticalPadding)
        }
    }

    private var bridgeStatus: some View {
        Group {
            if let bridgeStatusMessage {
                Label(bridgeStatusMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let endpoint = bridgeBrowser.endpoint {
                Label(
                    String(format: L10n.bridgeConnectedFormat, endpoint.displayName),
                    systemImage: "desktopcomputer"
                )
                .foregroundStyle(.secondary)
            } else if bridgeBrowser.isSearching {
                Label(L10n.bridgeSearchingStatus, systemImage: "wifi")
                    .foregroundStyle(.secondary)
            } else {
                Label(L10n.bridgeNotFoundStatus, systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func coordinateRow(label: LocalizedStringKey, value: CLLocationDegrees) -> some View {
        HStack(spacing: AppLayout.coordinateRowSpacing) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: AppLayout.coordinateSpacerMinLength)
            Text(formattedCoordinate(value))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func clearSelection() {
        selectedLocation = nil
        bridgeStatusMessage = nil
    }

    private func centerOnCurrentLocation() {
        requestCurrentLocation(shouldShowFailureAlert: true)
    }

    private func requestStartupLocationIfNeeded() {
        guard startupLocationPolicy.consumeShouldRequestCurrentLocation() else {
            return
        }

        requestCurrentLocation(shouldShowFailureAlert: false)
    }

    private func requestCurrentLocation(shouldShowFailureAlert: Bool) {
        locationProvider.requestCurrentLocation { fix in
            let location = SelectedMapLocation(gpxCoordinate: fix.coordinate)
            selectedLocation = location
            focusRequest = MapFocusRequest(
                coordinate: location.mapDisplayCoordinate,
                span: AppConstants.currentLocationSpan
            )
        } onFailure: { error in
            if shouldShowFailureAlert {
                locationAlert = LocationAlert(error: error)
            }
        }
    }

    private func applySelectedLocation() {
        guard let selectedLocation else {
            return
        }
        guard let endpoint = bridgeBrowser.endpoint else {
            bridgeBrowser.restart()
            bridgeAlert = BridgeAlert(message: L10n.bridgeNotFoundMessage)
            return
        }

        isApplyingLocation = true
        bridgeStatusMessage = nil

        Task {
            do {
                let response = try await bridgeClient.apply(
                    coordinate: selectedLocation.gpxCoordinate,
                    name: L10n.gpxLocationName,
                    endpoint: endpoint
                )
                await MainActor.run {
                    bridgeStatusMessage = applyMessage(for: response)
                    isApplyingLocation = false
                }
            } catch {
                await MainActor.run {
                    bridgeAlert = BridgeAlert(error: error)
                    isApplyingLocation = false
                }
            }
        }
    }

    private func applyMessage(for response: BridgeApplyResponse) -> String {
        guard let warning = response.warnings.first, !warning.isEmpty else {
            return L10n.bridgeApplySuccess
        }

        return String(format: L10n.bridgeApplyPartialFormat, warning)
    }

    private func formattedCoordinate(_ value: CLLocationDegrees) -> String {
        String(
            format: "%.\(AppConstants.coordinatePrecision)f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}

private struct LocationAlert: Identifiable {
    let id: String
    let message: LocalizedStringKey

    init(error: CurrentLocationError) {
        switch error {
        case .permissionDenied:
            id = "permission_denied"
            message = L10n.locationPermissionDeniedMessage
        case .simulatedBySoftware:
            id = "simulated_by_software"
            message = L10n.locationSimulatedMessage
        case .lowAccuracy:
            id = "low_accuracy"
            message = L10n.locationLowAccuracyMessage
        case .unavailable:
            id = "unavailable"
            message = L10n.locationUnavailableMessage
        }
    }
}

private struct BridgeAlert: Identifiable {
    let id = UUID()
    let message: String

    init(message: String) {
        self.message = message
    }

    init(error: Error) {
        if let clientError = error as? BridgeClientError,
           case let .serverRejected(message) = clientError {
            self.message = String(format: L10n.bridgeFailedFormat, message)
        } else if error is URLError {
            message = L10n.bridgeNetworkMessage
        } else {
            message = String(format: L10n.bridgeFailedFormat, error.localizedDescription)
        }
    }
}
