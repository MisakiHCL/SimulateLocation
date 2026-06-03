import AppKit
import Foundation

final class NativePortConflictPrompt: PortConflictPrompt {
    func chooseAction(port: Int, owners: [PortOwner]) async -> PortConflictChoice {
        await MainActor.run {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "dialog.port_conflict.title")
            alert.informativeText = String(
                format: String(localized: "dialog.port_conflict.message_format"),
                port,
                owners.map { "\($0.command) (\($0.pid))" }.joined(separator: ", ")
            )
            alert.addButton(withTitle: String(format: String(localized: "dialog.port_conflict.force_format"), port))
            alert.addButton(withTitle: String(localized: "dialog.port_conflict.next_port"))
            alert.addButton(withTitle: String(localized: "action.cancel"))

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                return .forceClose
            case .alertSecondButtonReturn:
                return .useNextAvailablePort
            default:
                return .cancel
            }
        }
    }
}

@MainActor
enum NativeOperationAlert {
    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "dialog.error.title")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "action.ok"))
        alert.runModal()
    }

    static func showWarning(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "dialog.warning.title")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "action.ok"))
        alert.runModal()
    }
}
