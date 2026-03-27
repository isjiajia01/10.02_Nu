import Foundation

enum WalkETADebugLogger {
    static func log(_ message: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] == nil else { return }
        print("[WalkETA] \(message)")
        #endif
    }
}
