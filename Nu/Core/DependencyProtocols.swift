import Foundation
import CoreLocation
import Combine

protocol ClockProtocol {
    var now: Date { get }
}

struct SystemClock: ClockProtocol {
    var now: Date { Date() }
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
