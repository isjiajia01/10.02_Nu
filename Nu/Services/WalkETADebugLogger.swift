import Foundation

enum WalkETADebugLogger {
    static func log(_ message: String) {
        #if DEBUG
        fputs("[WalkETA] \(message)\n", stderr)
        #endif
    }
}
