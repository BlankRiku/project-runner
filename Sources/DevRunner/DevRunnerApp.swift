import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.terminationTarget?.session.stopAllForTermination()
        }
    }
}

@main
struct DevRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                if model.activeCount > 0 {
                    Text("\(model.activeCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
