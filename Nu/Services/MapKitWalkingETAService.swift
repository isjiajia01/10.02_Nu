import Foundation
import CoreLocation
import MapKit

final class MapKitWalkingETAService: MapKitWalkingETAServiceProtocol {
    func fetchWalkingETA(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws -> MapKitWalkingETAResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = .walking

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw APIError.invalidResponse
        }

        return MapKitWalkingETAResult(
            expectedSeconds: Int(ceil(route.expectedTravelTime)),
            distanceMeters: Int(route.distance.rounded())
        )
    }
}
