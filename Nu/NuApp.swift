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

        // 启动时异步加载 /datainfo 产品类别映射（不阻塞 UI）
        Task {
            await ProductClassCache.shared.loadDataInfoIfNeeded(client: HafasClient())
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
