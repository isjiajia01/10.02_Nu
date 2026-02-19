import Foundation
import CoreLocation
import Combine

/// Shared location service.
///
/// Two-stage accuracy strategy:
/// - Starts with `kCLLocationAccuracyHundredMeters` for a fast first fix (~1-2s).
/// - Switches to `kCLLocationAccuracyNearestTenMeters` once a usable fix arrives.
///
/// All tabs share a single instance (owned by MainTabView).
@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var lastError: Error?

    private let manager = CLLocationManager()
    private var hasRefinedAccuracy = false

    override init() {
        super.init()
        manager.delegate = self
        // Stage 1: coarse accuracy for fast first fix.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 15
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }

    /// Switch to fine accuracy after the first usable fix.
    private func refineAccuracyIfNeeded() {
        guard !hasRefinedAccuracy else { return }
        hasRefinedAccuracy = true
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }
}

extension LocationManager: LocationManaging {
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }

    var currentLocationPublisher: AnyPublisher<CLLocation?, Never> {
        $currentLocation.eraseToAnyPublisher()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            currentLocation = location
            // Once we have any usable fix, switch to fine accuracy.
            if location.horizontalAccuracy > 0, location.horizontalAccuracy <= 5000 {
                refineAccuracyIfNeeded()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error
        }
    }
}
