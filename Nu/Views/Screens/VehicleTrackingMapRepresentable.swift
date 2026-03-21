import SwiftUI
import MapKit
import UIKit

struct VehicleTrackingMapRepresentable: UIViewRepresentable {
    let vehicle: JourneyVehicle?
    let nearbyVehicles: [JourneyVehicle]
    let routeCoordinates: [CLLocationCoordinate2D]
    /// P0-2: generation counter from ViewModel; Coordinator skips stale updates.
    let displayGeneration: Int
    /// P0-4: when true, nearby candidate annotations are frozen.
    let isInteracting: Bool
    @Binding var region: MKCoordinateRegion
    let onInteractionStart: () -> Void
    let onInteractionEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .mutedStandard
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncRoute(on: mapView, coordinates: routeCoordinates)
        context.coordinator.syncVehicle(on: mapView, vehicle: vehicle, generation: displayGeneration)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: VehicleTrackingMapRepresentable
        private var currentAnnotation: TrackingVehicleAnnotation?
        private var nearbyAnnotationsByID: [String: TrackingVehicleAnnotation] = [:]
        private var baseRouteOverlay: MKPolyline?
        private var remainingRouteOverlay: MKPolyline?
        private var routeSignature: String?
        private var routeCoords: [CLLocationCoordinate2D] = []
        private var lastSplitIndex: Int?
        private var lastProjection: CLLocationCoordinate2D?
        private var routeOverlayKinds: [ObjectIdentifier: RouteSegmentKind] = [:]
        /// P0-2: tracks the last generation applied to avoid stale updates.
        private var lastAppliedVehicleGeneration: Int = 0

        // MARK: P0-5 perf counters
        #if DEBUG
        private var overlayChangeCount = 0
        private var annotationMoveCount = 0
        private var annotationAddRemoveCount = 0
        private var lastPerfReportDate = Date()
        #endif

        init(parent: VehicleTrackingMapRepresentable) {
            self.parent = parent
        }

        // MARK: - Route sync (P0-4: dual-layer overlays, init once)

        func syncRoute(on mapView: MKMapView, coordinates: [CLLocationCoordinate2D]) {
            guard coordinates.count >= 2 else {
                clearRouteOverlays(on: mapView)
                self.routeCoords = []
                self.routeSignature = nil
                self.lastSplitIndex = nil
                self.lastProjection = nil
                return
            }

            let signature = makeRouteSignature(coordinates)
            if signature != routeSignature {
                clearRouteOverlays(on: mapView)
                routeSignature = signature
                routeCoords = coordinates
                lastSplitIndex = nil
                lastProjection = nil
                var base = coordinates
                let overlay = MKPolyline(coordinates: &base, count: base.count)
                baseRouteOverlay = overlay
                routeOverlayKinds[ObjectIdentifier(overlay)] = .base
                mapView.addOverlay(overlay)
            }
        }

        // MARK: - Vehicle sync (P0-2 generation check, P0-4 interaction freeze)

        func syncVehicle(on mapView: MKMapView, vehicle: JourneyVehicle?, generation: Int) {
            // P0-2 checkpoint 3: skip stale generation data at MapKit boundary
            guard generation >= lastAppliedVehicleGeneration else {
                #if DEBUG
                if DebugFlags.trackingPerfLoggingEnabled {
                    AppLogger.debug("[TrackingPerf:Map] Skipped stale update gen=\(generation) current=\(lastAppliedVehicleGeneration)")
                }
                #endif
                return
            }
            lastAppliedVehicleGeneration = generation

            guard let vehicle else {
                if let currentAnnotation {
                    mapView.removeAnnotation(currentAnnotation)
                    self.currentAnnotation = nil
                    #if DEBUG
                    annotationAddRemoveCount += 1
                    #endif
                }
                if !nearbyAnnotationsByID.isEmpty {
                    mapView.removeAnnotations(Array(nearbyAnnotationsByID.values))
                    #if DEBUG
                    annotationAddRemoveCount += nearbyAnnotationsByID.count
                    #endif
                    nearbyAnnotationsByID.removeAll()
                }
                clearRouteOverlays(on: mapView)
                return
            }

            // Route progress – always update (driven by main vehicle position)
            syncRouteProgress(on: mapView, vehicleCoordinate: vehicle.coordinate)

            // Main vehicle annotation – always update with smooth animation
            updateMainAnnotation(on: mapView, vehicle: vehicle)

            // P0-4: freeze nearby candidates during map interaction
            if !parent.isInteracting {
                updateNearbyAnnotations(on: mapView)
            }

            #if DEBUG
            reportPerfIfNeeded()
            #endif
        }

        // MARK: - Main annotation (always animated)

        private func updateMainAnnotation(on mapView: MKMapView, vehicle: JourneyVehicle) {
            if let annotation = currentAnnotation, annotation.vehicleId == vehicle.id {
                let destination = vehicle.coordinate
                UIView.animate(withDuration: 0.85, delay: 0, options: [.curveEaseInOut]) {
                    annotation.coordinate = destination
                }
                annotation.title = vehicle.line
                annotation.subtitle = vehicle.direction
                #if DEBUG
                annotationMoveCount += 1
                #endif
            } else {
                if let currentAnnotation {
                    mapView.removeAnnotation(currentAnnotation)
                    #if DEBUG
                    annotationAddRemoveCount += 1
                    #endif
                }
                let annotation = TrackingVehicleAnnotation(vehicle: vehicle)
                annotation.style = .primary
                currentAnnotation = annotation
                mapView.addAnnotation(annotation)
                #if DEBUG
                annotationAddRemoveCount += 1
                #endif
            }
        }

        // MARK: - Nearby annotations (P0-4: animation budget of 6)

        private func updateNearbyAnnotations(on mapView: MKMapView) {
            let targetIDs = Set(parent.nearbyVehicles.map(\.id))
            let stale = nearbyAnnotationsByID.keys.filter { !targetIDs.contains($0) }
            for key in stale {
                if let ann = nearbyAnnotationsByID.removeValue(forKey: key) {
                    mapView.removeAnnotation(ann)
                    #if DEBUG
                    annotationAddRemoveCount += 1
                    #endif
                }
            }

            var animatedNearbyCount = 0
            for nearby in parent.nearbyVehicles {
                if let existing = nearbyAnnotationsByID[nearby.id] {
                    if animatedNearbyCount < 6 {
                        animatedNearbyCount += 1
                        UIView.animate(withDuration: 0.7, delay: 0, options: [.curveEaseInOut]) {
                            existing.coordinate = nearby.coordinate
                        }
                    } else {
                        existing.coordinate = nearby.coordinate
                    }
                    existing.title = nearby.line
                    existing.subtitle = nearby.direction
                    #if DEBUG
                    annotationMoveCount += 1
                    #endif
                } else {
                    let ann = TrackingVehicleAnnotation(vehicle: nearby)
                    ann.style = .secondary
                    nearbyAnnotationsByID[nearby.id] = ann
                    mapView.addAnnotation(ann)
                    #if DEBUG
                    annotationAddRemoveCount += 1
                    #endif
                }
            }
        }

        // MARK: - Route progress (P0-4: segment-boundary driven)

        private func syncRouteProgress(on mapView: MKMapView, vehicleCoordinate: CLLocationCoordinate2D) {
            guard routeCoords.count >= 2 else { return }
            let progress = nearestRouteProgress(to: vehicleCoordinate, in: routeCoords)
            let projectionChanged: Bool
            if let lastProjection {
                let distance = CLLocation(latitude: lastProjection.latitude, longitude: lastProjection.longitude)
                    .distance(from: CLLocation(latitude: progress.projectedCoordinate.latitude, longitude: progress.projectedCoordinate.longitude))
                projectionChanged = distance > 5
            } else {
                projectionChanged = true
            }
            guard progress.segmentStartIndex != lastSplitIndex || projectionChanged else { return }
            lastSplitIndex = progress.segmentStartIndex
            lastProjection = progress.projectedCoordinate
            rebuildRouteOverlays(
                on: mapView,
                splitIndex: progress.segmentStartIndex,
                projectedCoordinate: progress.projectedCoordinate
            )
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            guard mapView.isRegionChangeFromUserInteraction else { return }
            parent.onInteractionStart()
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
            if mapView.isRegionChangeFromUserInteraction {
                parent.onInteractionEnd()
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let reuseID = "TrackingVehiclePin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseID)
            view.annotation = annotation
            view.canShowCallout = true
            if let ann = annotation as? TrackingVehicleAnnotation, ann.style == .secondary {
                view.markerTintColor = .systemGray
                view.glyphImage = UIImage(systemName: "circle.fill")
                view.displayPriority = .defaultHigh
            } else {
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "bus.fill")
                view.displayPriority = .required
            }
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            let kind = routeOverlayKinds[ObjectIdentifier(polyline)] ?? .remaining
            switch kind {
            case .base:
                renderer.strokeColor = UIColor.systemGray.withAlphaComponent(0.45)
                renderer.lineWidth = 4
            case .remaining:
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.90)
                renderer.lineWidth = 6
            }
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        // MARK: - Route overlay management

        private func rebuildRouteOverlays(
            on mapView: MKMapView,
            splitIndex: Int,
            projectedCoordinate: CLLocationCoordinate2D
        ) {
            guard routeCoords.count >= 2 else { return }
            #if DEBUG
            overlayChangeCount += 1
            #endif
            let clamped = max(0, min(splitIndex, routeCoords.count - 2))
            var upcoming = [projectedCoordinate]
            upcoming.append(contentsOf: routeCoords[(clamped + 1)...(routeCoords.count - 1)])
            if upcoming.count >= 2 {
                if let remainingRouteOverlay {
                    mapView.removeOverlay(remainingRouteOverlay)
                    routeOverlayKinds.removeValue(forKey: ObjectIdentifier(remainingRouteOverlay))
                }
                let overlay = MKPolyline(coordinates: &upcoming, count: upcoming.count)
                remainingRouteOverlay = overlay
                routeOverlayKinds[ObjectIdentifier(overlay)] = .remaining
                mapView.addOverlay(overlay)
            }
        }

        private func clearRouteOverlays(on mapView: MKMapView) {
            if let baseRouteOverlay {
                mapView.removeOverlay(baseRouteOverlay)
                routeOverlayKinds.removeValue(forKey: ObjectIdentifier(baseRouteOverlay))
                self.baseRouteOverlay = nil
            }
            if let remainingRouteOverlay {
                mapView.removeOverlay(remainingRouteOverlay)
                routeOverlayKinds.removeValue(forKey: ObjectIdentifier(remainingRouteOverlay))
                self.remainingRouteOverlay = nil
            }
        }

        private func nearestRouteProgress(
            to coordinate: CLLocationCoordinate2D,
            in coords: [CLLocationCoordinate2D]
        ) -> RouteProgress {
            guard coords.count >= 2 else {
                return RouteProgress(segmentStartIndex: 0, projectedCoordinate: coordinate)
            }

            let target = MKMapPoint(coordinate)
            var bestSegmentStart = 0
            var bestProjected = coords[0]
            var bestDistanceSq = Double.greatestFiniteMagnitude

            for index in 0..<(coords.count - 1) {
                let a = MKMapPoint(coords[index])
                let b = MKMapPoint(coords[index + 1])
                let abx = b.x - a.x
                let aby = b.y - a.y
                let apx = target.x - a.x
                let apy = target.y - a.y
                let ab2 = abx * abx + aby * aby
                if ab2 <= 1e-12 { continue }

                var t = (apx * abx + apy * aby) / ab2
                t = min(1, max(0, t))
                let proj = MKMapPoint(x: a.x + t * abx, y: a.y + t * aby)
                let dx = target.x - proj.x
                let dy = target.y - proj.y
                let distSq = dx * dx + dy * dy
                if distSq < bestDistanceSq {
                    bestDistanceSq = distSq
                    bestSegmentStart = index
                    bestProjected = proj.coordinate
                }
            }
            return RouteProgress(segmentStartIndex: bestSegmentStart, projectedCoordinate: bestProjected)
        }

        private func makeRouteSignature(_ coordinates: [CLLocationCoordinate2D]) -> String {
            guard let first = coordinates.first, let last = coordinates.last else { return "empty" }
            return "\(coordinates.count)-\(first.latitude)-\(first.longitude)-\(last.latitude)-\(last.longitude)"
        }

        // MARK: - Debug perf reporting (P0-5)

        #if DEBUG
        private func reportPerfIfNeeded() {
            guard DebugFlags.trackingPerfLoggingEnabled else { return }
            let now = Date()
            guard now.timeIntervalSince(lastPerfReportDate) >= 30 else { return }
            AppLogger.debug("[TrackingPerf:Map] 30s: overlayChanges=\(overlayChangeCount) annotationMoves=\(annotationMoveCount) annotationAddsRemoves=\(annotationAddRemoveCount)")
            overlayChangeCount = 0
            annotationMoveCount = 0
            annotationAddRemoveCount = 0
            lastPerfReportDate = now
        }
        #endif
    }
}

// MARK: - Supporting types

enum RouteSegmentKind {
    case base
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
    var style: Style = .primary

    init(vehicle: JourneyVehicle) {
        self.vehicleId = vehicle.id
        self.coordinate = vehicle.coordinate
        self.title = vehicle.line
        self.subtitle = vehicle.direction
        super.init()
    }
}

