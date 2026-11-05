import AppKit
import SwiftUI

/// Menu bar apps launched with `LSUIElement` stay `.accessory`, so AppKit ignores activation
/// and the menu bar window treats the next click as an outside click. Hold `.regular` only
/// while a form window or the folder panel is on screen, then return to `.accessory`.
@MainActor
enum AppActivation {
    private static var holds = 0
    private static var borrowed = false

    static func promote() {
        let app = NSApplication.shared
        if holds == 0, app.activationPolicy() != .regular {
            _ = app.setActivationPolicy(.regular)
            borrowed = true
        }
        holds += 1
        activate()
    }

    static func release() {
        guard holds > 0 else { return }
        holds -= 1
        guard holds == 0, borrowed else { return }
        borrowed = false
        _ = NSApplication.shared.setActivationPolicy(.accessory)
    }

    static func activate() {
        let app = NSApplication.shared
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(ignoringOtherApps: true)
        }
        if !app.isActive {
            app.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
enum DirectoryPicker {
    private static var retained: NSOpenPanel?

    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Scegli"
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        retained = panel
        AppActivation.promote()
        defer {
            retained = nil
            AppActivation.release()
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

@MainActor
final class FormWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = FormWindowPresenter()

    private var window: NSWindow?
    private var replacing = false
    private var holdingActivation = false

    func present<Content: View>(title: String, content: Content) {
        if window != nil {
            replacing = true
            window?.close()
            replacing = false
        }

        let host = NSHostingController(rootView:
            content
                .preferredColorScheme(.dark)
                .background(Theme.background)
        )
        host.sizingOptions = .preferredContentSize

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = host
        host.view.layoutSubtreeIfNeeded()

        var size = host.preferredContentSize
        if size.width < 200 || size.height < 160 {
            size = host.sizeThatFits(in: NSSize(width: 520, height: 2000))
        }
        if size.width < 200 || size.height < 160 {
            size = NSSize(width: 440, height: 480)
        }
        size.width = min(max(size.width, 420), 560)
        size.height = min(max(size.height, 200), 700)
        panel.setContentSize(size)
        panel.center()

        window = panel
        if !holdingActivation {
            AppActivation.promote()
            holdingActivation = true
        } else {
            AppActivation.activate()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === window {
            window = nil
        }
        guard !replacing, holdingActivation else { return }
        holdingActivation = false
        AppActivation.release()
    }
}
