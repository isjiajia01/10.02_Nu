import SwiftUI
import MapKit

struct VehicleTrackingMapView: View {
    let departure: Departure
    let operationDate: String?
    let apiService: APIServiceProtocol

    @StateObject private var vm: VehicleTrackingViewModel

    init(
        departure: Departure,
        operationDate: String?,
        apiService: APIServiceProtocol
    ) {
        self.departure = departure
        self.operationDate = operationDate
        self.apiService = apiService
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683),
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
        _vm = StateObject(
            wrappedValue: VehicleTrackingViewModel(
                departure: departure,
                operationDate: operationDate,
                apiService: apiService,
                initialRegion: initialRegion
            )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            VehicleTrackingMapRepresentable(
                vehicle: vm.trackedVehicle,
                nearbyVehicles: vm.nearbyLineVehicles,
                routeCoordinates: vm.routeCoordinates,
                displayGeneration: vm.displayGeneration,
                isInteracting: vm.isInteracting,
                region: $vm.visibleRegion,
                onInteractionStart: { vm.pauseForInteraction() },
                onInteractionEnd: { vm.resumeAfterInteraction() }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                switch vm.state {
                case .loading:
                    statusPill(text: "Resolving vehicle identity…")
                case .tracking:
                    statusPill(text: vm.statusText)
                    HStack(spacing: 8) {
                        LastUpdatedPill(lastUpdateDate: vm.lastUpdateDate)
                        statusPill(text: vm.motionState.label, color: vm.motionState == .moving ? .green : .orange)
                    }
                case .empty:
                    statusPill(text: vm.statusText.isEmpty ? "No matching vehicle in this area" : vm.statusText)
                case .blocked(let msg):
                    statusPill(text: msg, color: .red)
                case .failed(let msg):
                    statusPill(text: msg, color: .orange)
                case .idle:
                    EmptyView()
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
        .navigationTitle("Vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private func statusPill(text: String, color: Color = .indigo) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.9))
            .clipShape(Capsule())
    }
}

// MARK: - P0-3: local-only timer for "Updated Xs ago" text

private struct LastUpdatedPill: View {
    let lastUpdateDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(labelText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.teal.opacity(0.9))
                .clipShape(Capsule())
        }
    }

    private var labelText: String {
        guard let lastUpdateDate else { return "Updated —" }
        let age = Int(max(0, Date().timeIntervalSince(lastUpdateDate)))
        return "Updated \(age)s ago"
    }
}
