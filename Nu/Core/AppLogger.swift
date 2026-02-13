import Foundation

enum AppLogger {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }
}
