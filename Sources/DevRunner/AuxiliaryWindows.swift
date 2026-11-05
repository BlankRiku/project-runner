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

enum FormWindowMetrics {
    static let minWidth: CGFloat = 420
    static let maxWidth: CGFloat = 560
    static let minHeight: CGFloat = 200
    /// Whole window, title bar included, stays at about this fraction of the screen.
    static let maxScreenFraction: CGFloat = 0.65
    /// Headline, paddings and the pinned footer live outside the scrolling body.
    static let outsideScroll: CGFloat = 120
    /// Sync sheet also shows project name, a caption and the select-all row above the list.
    static let syncOutsideScroll: CGFloat = 230

    static func maxContentHeight(screenHeight: CGFloat, visibleHeight: CGFloat, titleBar: CGFloat = 28) -> CGFloat {
        let limit = min(screenHeight * maxScreenFraction, visibleHeight)
        return max(80, limit - titleBar)
    }

    static func maxScrollHeight(
        screenHeight: CGFloat,
        visibleHeight: CGFloat,
        titleBar: CGFloat = 28,
        outsideScroll: CGFloat = outsideScroll
    ) -> CGFloat {
        max(80, maxContentHeight(screenHeight: screenHeight, visibleHeight: visibleHeight, titleBar: titleBar) - outsideScroll)
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
        let screen = panel.screen ?? NSScreen.main
        let maxHeight = FormWindowMetrics.maxContentHeight(
            screenHeight: screen?.frame.height ?? 900,
            visibleHeight: screen?.visibleFrame.height ?? 900
        )
        size.width = min(max(size.width, FormWindowMetrics.minWidth), FormWindowMetrics.maxWidth)
        size.height = min(max(size.height, FormWindowMetrics.minHeight), maxHeight)
        panel.setContentSize(size)
        panel.center()
        applyHeightLimit(to: panel)

        window = panel
        if !holdingActivation {
            AppActivation.promote()
            holdingActivation = true
        } else {
            AppActivation.activate()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        applyHeightLimit(to: panel)
    }

    /// `preferredContentSize` keeps resizing the panel after the first layout.
    /// The window frame cannot grow past 65% of the screen height.
    private func applyHeightLimit(to panel: NSWindow) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        let titleBar = panel.frame.height - contentSize.height
        let maxWindowHeight = screen.frame.height * FormWindowMetrics.maxScreenFraction
        let maxHeight = FormWindowMetrics.maxContentHeight(
            screenHeight: screen.frame.height,
            visibleHeight: visible.height,
            titleBar: titleBar
        )
        let maxFrame = panel.frameRect(forContentRect: NSRect(
            origin: .zero,
            size: NSSize(width: FormWindowMetrics.maxWidth, height: maxHeight)
        ))
        panel.maxSize = NSSize(width: maxFrame.width, height: min(maxFrame.height, maxWindowHeight))
        let minFrame = panel.frameRect(forContentRect: NSRect(
            origin: .zero,
            size: NSSize(width: FormWindowMetrics.minWidth, height: min(FormWindowMetrics.minHeight, maxHeight))
        ))
        panel.minSize = minFrame.size

        if contentSize.height > maxHeight + 0.5 || panel.frame.height > maxWindowHeight + 0.5 {
            panel.setContentSize(NSSize(width: min(contentSize.width, FormWindowMetrics.maxWidth), height: maxHeight))
            panel.center()
        }
        var frame = panel.frame
        if frame.maxY > visible.maxY { frame.origin.y -= frame.maxY - visible.maxY }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame != panel.frame {
            panel.setFrame(frame, display: false)
        }
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
