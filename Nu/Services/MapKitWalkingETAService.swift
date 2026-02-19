import Foundation
import CoreLocation
import MapKit

final class MapKitWalkingETAService: MapKitWalkingETAServiceProtocol {
    func fetchWalkingETA(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) async throws -> MapKitWalkingETAResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
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
