import SwiftUI

@main
struct NuApp: App {
    private let dependencies: AppDependencies

    @MainActor
    init() {
        let dependencies = AppDependencies.live
        self.dependencies = dependencies

        #if DEBUG
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
        if !isRunningTests {
            HafasSmokeTests.runIfEnabled()
        }
        #endif

        Task {
            await ProductClassCache.shared.loadDataInfoIfNeeded(client: HafasClient())
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(dependencies: dependencies)
        }
    }
}
