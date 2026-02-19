import Foundation
import CoreLocation
import Combine
import MapKit

protocol ClockProtocol {
    nonisolated var now: Date { get }
}

struct SystemClock: ClockProtocol {
    nonisolated init() {}
    nonisolated var now: Date { Date() }
}

protocol KeyValueStoring {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    func double(forKey defaultName: String) -> Double
    func array(forKey defaultName: String) -> [Any]?
}

extension UserDefaults: KeyValueStoring {}

protocol LocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var currentLocation: CLLocation? { get }
    var authorizationStatusPublisher: AnyPublisher<CLAuthorizationStatus, Never> { get }
    var currentLocationPublisher: AnyPublisher<CLLocation?, Never> { get }

    func requestAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
}

enum WalkETASource: Equatable {
    case hafasWalk
    case estimatedFallback
}

struct WalkingETADestination: Equatable {
    enum Mode: String, Equatable {
        case bus
        case metro
        case tog
        case unknown

        var displayText: String {
            switch self {
            case .bus: return "BUS"
            case .metro: return "METRO"
            case .tog: return "TOG"
            case .unknown: return "station"
            }
        }
    }

    let stopId: String
    let name: String?
    let groupId: String?
    let latitude: Double?
    let longitude: Double?
    let mode: Mode
    let isRecommended: Bool

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct WalkETA: Equatable {
    let minutes: Int
    let baseMinutes: Int?
    let distanceMeters: Int?
    let source: WalkETASource
}

protocol WalkingETAServiceProtocol: AnyObject {
    func fetchWalkETA(
        origin: CLLocationCoordinate2D,
        destination: WalkingETADestination,
        locationAccuracy: CLLocationAccuracy?,
        locationAgeSeconds: TimeInterval?
    ) async throws -> WalkETA
}

struct MapKitWalkingETAResult: Equatable {
    let expectedSeconds: Int
    let distanceMeters: Int?
}

protocol MapKitWalkingETAServiceProtocol: AnyObject {
    func fetchWalkingETA(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws -> MapKitWalkingETAResult
}
