import SwiftUI

struct VehicleStopSequenceSheet: View {
    let vehicle: JourneyVehicle
    let departure: Departure
    let stops: [JourneyStop]
    let onClose: () -> Void

    @State private var showPassedStops = false

    private var orderedStops: [JourneyStop] {
        stops
            .filter { !isTechnicalStop($0) }
            .sorted { ($0.routeIdx ?? 0) < ($1.routeIdx ?? 0) }
    }

    private var currentIndex: Int {
        if let nextStop = vehicle.nextStopName,
           let idx = orderedStops.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(nextStop) }) {
            return max(0, idx - 1)
        }
        if let stopName = vehicle.stopName,
           let idx = orderedStops.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(stopName) }) {
            return idx
        }
        return 0
    }

    private var passedStops: ArraySlice<JourneyStop> {
        orderedStops.prefix(currentIndex)
    }

    private var visibleUpcomingStops: ArraySlice<JourneyStop> {
        let start = min(currentIndex, orderedStops.count)
        let end = min(orderedStops.count, start + 6)
        return orderedStops[start..<end]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if !passedStops.isEmpty {
                        passedStopsToggle
                    }

                    VStack(spacing: 12) {
                        if showPassedStops {
                            ForEach(Array(passedStops.enumerated()), id: \.offset) { offset, stop in
                                stopRow(stop, index: offset)
                            }
                        }

                        ForEach(Array(visibleUpcomingStops.enumerated()), id: \.element.id) { offset, stop in
                            stopRow(stop, index: currentIndex + offset)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(L10n.tr("tracking.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("common.close"), action: onClose)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(vehicle.line ?? departure.name)
                .font(.title3.weight(.bold))
            Text(vehicle.direction ?? departure.direction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if vehicle.id != departure.id {
                Text(L10n.tr("tracking.sheet.selectedVehicle"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if let nextStopName = vehicle.nextStopName, !nextStopName.isEmpty {
                Text(L10n.tr("tracking.sheet.nextStop", nextStopName))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.blue)
            }
        }
    }

    private var passedStopsToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showPassedStops.toggle()
            }
        } label: {
            HStack {
                Text(showPassedStops
                     ? L10n.tr("journeyDetail.past.collapse", passedStops.count)
                     : L10n.tr("journeyDetail.past.expand", passedStops.count))
                Spacer()
                Image(systemName: showPassedStops ? "chevron.up" : "chevron.down")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private func stopRow(_ stop: JourneyStop, index: Int) -> some View {
        let isPassed = index < currentIndex
        let isCurrent = index == currentIndex
        let etaText = estimatedArrivalText(for: stop, index: index)

        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isCurrent ? Color.blue : (isPassed ? Color.gray.opacity(0.5) : Color.secondary.opacity(0.4)))
                .frame(width: isCurrent ? 12 : 9, height: isCurrent ? 12 : 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stop.name)
                        .font(.body.weight(isCurrent ? .bold : .semibold))
                    if isCurrent {
                        Text(L10n.tr("tracking.sheet.current"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text(etaText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(isPassed ? .secondary : .primary)

                if let track = stop.rtTrack ?? stop.track, !track.isEmpty {
                    Text(L10n.tr("journeyDetail.track", track))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCurrent ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
        )
    }

    private func isTechnicalStop(_ stop: JourneyStop) -> Bool {
        stop.name.localizedCaseInsensitiveContains("Gennemkzone")
    }

    private func estimatedArrivalText(for stop: JourneyStop, index: Int) -> String {
        let planned = JourneyDetailViewModel.normalizeTimeToMinute(stop.rtArrTime ?? stop.rtDepTime ?? stop.arrTime ?? stop.depTime)
            ?? "--:--"

        if index < currentIndex {
            return L10n.tr("tracking.sheet.passed", planned)
        }
        if index == currentIndex {
            return L10n.tr("tracking.sheet.currentEta", planned)
        }
        if let targetDate = parseStopDate(stop),
           let baseDate = departure.effectiveDepartureDate?.date {
            let deltaMinutes = max(Int(targetDate.timeIntervalSince(baseDate) / 60), 0)
            return L10n.tr("tracking.sheet.upcomingEta", planned, deltaMinutes)
        }
        return L10n.tr("tracking.sheet.scheduledEta", planned)
    }

    private func parseStopDate(_ stop: JourneyStop) -> Date? {
        let dateText = stop.arrDate ?? stop.depDate ?? departure.rtDate ?? departure.date
        let timeText = stop.rtArrTime ?? stop.rtDepTime ?? stop.arrTime ?? stop.depTime
        guard let timeText else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.timeZone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        formatter.dateFormat = "dd.MM.yy HH:mm"
        return formatter.date(from: "\(dateText) \(timeText)")
    }
}
