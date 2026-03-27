import SwiftUI
import MapKit
import UIKit

enum RouteSegmentKind {
    case base
    case passed
    case remaining
}

struct RouteProgress {
    let segmentStartIndex: Int
    let projectedCoordinate: CLLocationCoordinate2D
}

final class TrackingVehicleAnnotation: NSObject, MKAnnotation {
    enum Style: Equatable {
        case primary
        case secondary
    }

    dynamic var coordinate: CLLocationCoordinate2D
    dynamic var title: String?
    dynamic var subtitle: String?
    let vehicleId: String
    let vehicle: JourneyVehicle
    let heading: Double?
    var style: Style = .primary

    init(vehicle: JourneyVehicle) {
        self.vehicle = vehicle
        self.vehicleId = vehicle.id
        self.coordinate = vehicle.coordinate
        self.title = vehicle.line
        self.subtitle = [vehicle.stopName, vehicle.nextStopName].compactMap { $0 }.joined(separator: " → ")
        self.heading = vehicle.heading
        super.init()
    }
}

extension MKMapView {
    var isRegionChangeFromUserInteraction: Bool {
        guard let firstSubview = subviews.first else { return false }
        let recognizers = firstSubview.gestureRecognizers ?? []
        return recognizers.contains {
            $0.state == .began || $0.state == .changed || $0.state == .ended
        }
    }
}
