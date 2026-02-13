import SwiftUI

@main
struct NuApp: App {
    init() {
        #if DEBUG
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
        if !isRunningTests {
            HafasSmokeTests.runIfEnabled()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
