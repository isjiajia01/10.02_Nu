import SwiftUI

@main
struct NuApp: App {
    private let dependencies: AppDependencies

    @MainActor
    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let dependencies = arguments.contains("--use-mock-api") ? AppDependencies.preview : AppDependencies.live
        #else
        let dependencies = AppDependencies.live
        #endif
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
