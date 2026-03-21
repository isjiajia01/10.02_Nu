import Foundation

/// Lightweight preference store for the user's departure delay selection.
///
/// Stores the value as JSON-encoded `Int` so the implementation stays compatible
/// with the project's `KeyValueStoring` abstraction.
struct DepartureDelayStore {
    private let storage: KeyValueStoring
    private let key: String
    private let allowedRange: ClosedRange<Int>

    init(
        storage: KeyValueStoring = UserDefaults.standard,
        key: String = "departure_delay_minutes",
        allowedRange: ClosedRange<Int> = 0...20
    ) {
        self.storage = storage
        self.key = key
        self.allowedRange = allowedRange
    }

    func load() -> Int {
        guard let data = storage.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Int.self, from: data) else {
            return allowedRange.lowerBound
        }
        return clamp(decoded)
    }

    func save(_ minutes: Int) {
        let clamped = clamp(minutes)
        guard let data = try? JSONEncoder().encode(clamped) else { return }
        storage.set(data, forKey: key)
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, allowedRange.lowerBound), allowedRange.upperBound)
    }
}
