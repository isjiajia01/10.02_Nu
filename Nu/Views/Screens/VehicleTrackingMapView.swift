import SwiftUI
import MapKit

struct VehicleTrackingMapView: View {
    let departure: Departure
    let operationDate: String?
    let apiService: APIServiceProtocol

    @StateObject private var vm: VehicleTrackingViewModel
    @State private var selectedSheetDetent: PresentationDetent = .medium
    @State private var selectedVehicle: JourneyVehicle?
    @State private var isStopSequencePresented = false
    @State private var cardState: VehicleCardState = .compact

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
        ZStack(alignment: .bottom) {
            VehicleTrackingMapRepresentable(
                vehicle: vm.trackedVehicle,
                nearbyVehicles: vm.nearbyLineVehicles,
                routeCoordinates: vm.routeCoordinates,
                centerOnVehicleCoordinate: vm.mapCenterCoordinate,
                selectedVehicleID: selectedVehicle?.id ?? vm.trackedVehicle?.id,
                highlightedVehicleCoordinate: (selectedVehicle ?? vm.trackedVehicle)?.coordinate,
                displayGeneration: vm.displayGeneration,
                isInteracting: vm.isInteracting,
                region: $vm.visibleRegion,
                onInteractionStart: { vm.pauseForInteraction() },
                onInteractionEnd: { vm.resumeAfterInteraction() },
                onVehicleSelection: { vehicle in
                    selectedVehicle = vehicle
                }
            )
            .ignoresSafeArea()

            VStack {
                switch vm.state {
                case .loading:
                    VehicleTrackingFloatingMessage(text: "Resolving vehicle identity…")
                case .empty:
                    VehicleTrackingFloatingMessage(text: vm.statusText.isEmpty ? "No matching vehicle in this area" : vm.statusText)
                case .blocked(let msg):
                    VehicleTrackingFloatingMessage(text: msg, color: .red)
                case .failed(let msg):
                    VehicleTrackingFloatingMessage(text: msg, color: .orange)
                case .tracking, .idle:
                    EmptyView()
                }
                Spacer()
            }
            .padding(.horizontal, VehicleTrackingUI.horizontalPadding)
            .padding(.top, VehicleTrackingUI.topOverlayPadding)

            if let vehicle = selectedVehicle ?? vm.trackedVehicle,
               vm.state == .tracking || !vm.routeStops.isEmpty {
                VehicleTrackingBottomCard(
                    vehicle: vehicle,
                    motionLabel: vm.motionState.label,
                    motionColor: vm.motionState == .moving ? .green : .orange,
                    lastUpdateDate: vm.lastUpdateDate,
                    statusText: vm.statusText,
                    routeStopsAvailable: !vm.routeStops.isEmpty,
                    isShowingAlternateVehicle: isShowingAlternateVehicle,
                    onResetToPrimary: { selectedVehicle = vm.trackedVehicle },
                    onOpenStops: { isStopSequencePresented = true },
                    cardState: $cardState
                )
                    .padding(.horizontal, VehicleTrackingUI.horizontalPadding)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.trackedVehicle?.id) { _, _ in
            if selectedVehicle == nil {
                selectedVehicle = vm.trackedVehicle
            }
            isStopSequencePresented = shouldPresentStopSequence
        }
        .onChange(of: vm.routeStops.count) { _, _ in
            isStopSequencePresented = shouldPresentStopSequence
        }
        .sheet(isPresented: $isStopSequencePresented) {
            if let vehicle = selectedVehicle ?? vm.trackedVehicle, !vm.routeStops.isEmpty {
                VehicleStopSequenceSheet(
                    vehicle: vehicle,
                    departure: departure,
                    stops: vm.routeStops,
                    onClose: { isStopSequencePresented = false }
                )
                .presentationDetents([.medium, .large], selection: $selectedSheetDetent)
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var isShowingAlternateVehicle: Bool {
        guard let selectedVehicle, let trackedVehicle = vm.trackedVehicle else { return false }
        return selectedVehicle.id != trackedVehicle.id
    }

    private var shouldPresentStopSequence: Bool {
        (selectedVehicle ?? vm.trackedVehicle) != nil && !vm.routeStops.isEmpty
    }
}
