import Combine
import CoreLocation
import Foundation

enum LocationPermissionStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case granted
    case unavailable

    var label: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .granted:
            "Granted"
        case .unavailable:
            "Unavailable"
        }
    }

    var isGranted: Bool { self == .granted }

    var detail: String {
        switch self {
        case .notDetermined:
            "Allow Pixel Pane in System Settings → Privacy & Security → Location Services, then press Refresh. Approximate (city-level) location is used only for location-aware questions in Cloud Mode, and only when sharing is enabled."
        case .denied:
            "macOS is blocking location access for Pixel Pane. Cloud answers that need your location will ask you for a city instead."
        case .granted:
            "Pixel Pane can read an approximate (city-level) location. It is shared with Pixel Pane Cloud only when the sharing toggle is on."
        case .unavailable:
            "Location Services are turned off on this Mac."
        }
    }
}

/// Resolves a coarse, city-level location for cloud questions. Uses reduced
/// accuracy and reverse geocoding; never stores or shares coordinates. The
/// resolved context is cached per launch and refreshed on demand.
@MainActor
final class LocationContextProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var permissionStatus: LocationPermissionStatus = .notDetermined
    @Published private(set) var approximateLocation: AgentLocationContext?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var isResolving = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        permissionStatus = Self.status(from: manager.authorizationStatus)
    }

    func requestAccess() {
        guard permissionStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        permissionStatus = Self.status(from: manager.authorizationStatus)
        guard permissionStatus.isGranted, !isResolving else { return }
        isResolving = true
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            permissionStatus = Self.status(from: status)
            if permissionStatus.isGranted, approximateLocation == nil {
                refresh()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor in isResolving = false }
            return
        }
        Task { @MainActor in
            defer { isResolving = false }
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first,
                  let city = placemark.locality ?? placemark.administrativeArea else {
                return
            }
            approximateLocation = AgentLocationContext(
                city: city,
                region: placemark.administrativeArea == city ? nil : placemark.administrativeArea,
                countryCode: placemark.isoCountryCode
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in isResolving = false }
    }

    private nonisolated static func status(from status: CLAuthorizationStatus) -> LocationPermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted, .denied:
            .denied
        case .authorizedAlways, .authorized:
            .granted
        @unknown default:
            .unavailable
        }
    }
}
