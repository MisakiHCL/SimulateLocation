import SwiftUI

private enum MenuLayout {
    static let statusMinWidth: CGFloat = 220
}

struct MenuBarContentView: View {
    @ObservedObject var controller: BridgeController

    var body: some View {
        Text(controller.status.title)
            .frame(minWidth: MenuLayout.statusMinWidth, alignment: .leading)

        Divider()

        Button(String(localized: "action.start")) {
            Task {
                await controller.start()
            }
        }
        .disabled(!controller.canStart)

        Button(String(localized: "action.stop")) {
            Task {
                await controller.stop()
            }
        }
        .disabled(!controller.canStop)

        Divider()

        Button(String(localized: "action.quit")) {
            Task {
                await controller.quit()
            }
        }
    }
}
