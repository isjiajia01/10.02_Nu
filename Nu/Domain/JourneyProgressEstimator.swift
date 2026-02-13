import Foundation

struct JourneyProgressEstimation: Equatable {
    enum Status: Equatable {
        case between(from: String, to: String)
        case at(name: String)
        case nearDestination
        case unknown
    }

    let currentIndex: Int?
    let nextIndex: Int?
    let currentOrNextIndex: Int?
    let usesRealtime: Bool
    let minutesToDestination: Int?
    let status: Status
}

enum JourneyProgressEstimator {
    static func infer(
        stops: [JourneyStop],
        fallbackCurrentStopName: String,
        operationDate: String?,
        now: Date = Date()
    ) -> JourneyProgressEstimation {
        guard !stops.isEmpty else {
            return JourneyProgressEstimation(
                currentIndex: nil,
                nextIndex: nil,
                currentOrNextIndex: nil,
                usesRealtime: false,
                minutesToDestination: nil,
                status: .unknown
            )
        }

        let usesRealtime = stops.contains { ($0.rtArrTime != nil) || ($0.rtDepTime != nil) }
        let points = stops.enumerated().map { index, stop in
            JourneyTimelinePoint(index: index, stop: stop, operationDate: operationDate)
        }

        var current: Int?
        var next: Int?

        for point in points {
            if let arr = point.arrivalDate, let dep = point.departureDate, arr <= now, now < dep {
                current = point.index
                next = min(point.index + 1, points.count - 1)
                break
            }
        }

        if current == nil {
            let departed = points.last { point in
                guard let marker = point.departureDate ?? point.arrivalDate else { return false }
                return marker <= now
            }
            if let departed {
                if departed.index >= points.count - 1 {
                    current = points.count - 1
                    next = nil
                } else {
                    current = departed.index
                    next = departed.index + 1
                }
            } else {
                current = 0
                next = points.count > 1 ? 1 : nil
            }
        }

        let status: JourneyProgressEstimation.Status
        if let current, let next {
            status = .between(from: points[current].stop.name, to: points[next].stop.name)
        } else if let current {
            status = current == points.count - 1 ? .nearDestination : .at(name: points[current].stop.name)
        } else {
            status = .unknown
        }

        let currentOrNextIndex: Int?
        if let current {
            currentOrNextIndex = current
        } else if !fallbackCurrentStopName.isEmpty {
            currentOrNextIndex = stops.firstIndex { $0.name.localizedCaseInsensitiveContains(fallbackCurrentStopName) }
        } else {
            currentOrNextIndex = nil
        }

        let minutesToDestination: Int?
        if let last = points.last {
            let destinationTime = last.arrivalDate ?? last.departureDate
            if let destinationTime {
                minutesToDestination = max(Int(destinationTime.timeIntervalSince(now) / 60), 0)
            } else {
                minutesToDestination = nil
            }
        } else {
            minutesToDestination = nil
        }

        return JourneyProgressEstimation(
            currentIndex: current,
            nextIndex: next,
            currentOrNextIndex: currentOrNextIndex,
            usesRealtime: usesRealtime,
            minutesToDestination: minutesToDestination,
            status: status
        )
    }
}

private struct JourneyTimelinePoint {
    let index: Int
    let stop: JourneyStop
    let arrivalDate: Date?
    let departureDate: Date?

    init(index: Int, stop: JourneyStop, operationDate: String?) {
        self.index = index
        self.stop = stop
        arrivalDate = Self.parse(date: stop.arrDate, time: stop.rtArrTime ?? stop.arrTime, fallbackDate: operationDate)
        departureDate = Self.parse(date: stop.depDate, time: stop.rtDepTime ?? stop.depTime, fallbackDate: operationDate)
    }

    private static func parse(date: String?, time: String?, fallbackDate: String?) -> Date? {
        guard let time else { return nil }
        let cleanTime = time.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTime = cleanTime.count >= 5 ? String(cleanTime.prefix(5)) : cleanTime
        let cleanedDate = date?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateDate = (cleanedDate?.isEmpty == false ? cleanedDate : nil) ?? fallbackDate
        guard let candidateDate else { return nil }

        let zone = TimeZone(identifier: "Europe/Copenhagen") ?? .current
        let locale = Locale(identifier: "da_DK")
        let formats = ["yyyy-MM-dd HH:mm", "dd.MM.yy HH:mm", "dd.MM.yyyy HH:mm"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = zone
            formatter.dateFormat = format
            if let parsed = formatter.date(from: "\(candidateDate) \(normalizedTime)") {
                return parsed
            }
        }
        return nil
    }
}
