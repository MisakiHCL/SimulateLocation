import SwiftUI

@main
struct SimulateLocationMenuBarApp: App {
    @StateObject private var controller = BridgeController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(controller: controller)
                .task {
                    await controller.refreshStatus()
                }
        } label: {
            Label(String(localized: "app.title"), systemImage: controller.status.systemImage)
        }
        .menuBarExtraStyle(.menu)
    }
}
