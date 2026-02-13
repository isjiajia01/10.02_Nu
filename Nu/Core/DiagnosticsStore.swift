import Foundation
import Combine

@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()

    @Published var latestWarning: String?

    private init() {}

    func pushWarning(_ text: String) {
        latestWarning = text
    }

    func clearWarning() {
        latestWarning = nil
    }
}
