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
                MenuBarMark()
                if model.activeCount > 0 {
                    Text("\(model.activeCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuBarIcon {
    /// 16×16 grid. Three bars into a run arrow, sized for the menu bar slot.
    static func path(in rect: CGRect) -> NSBezierPath {
        let sx = rect.width / 16
        let sy = rect.height / 16
        let ox = rect.minX
        let oy = rect.minY
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * sx, y: oy + y * sy)
        }
        let path = NSBezierPath()
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ cut: CGFloat) {
            path.move(to: point(x, y))
            path.line(to: point(x + w - cut, y))
            path.line(to: point(x + w, y + h / 2))
            path.line(to: point(x + w - cut, y + h))
            path.line(to: point(x, y + h))
            path.close()
        }
        bar(1, 1.5, 8, 3, 1.5)
        bar(1, 6.5, 9.2, 3, 1.5)
        bar(1, 11.5, 8, 3, 1.5)
        path.move(to: point(10.2, 1.5))
        path.line(to: point(15, 8))
        path.line(to: point(10.2, 14.5))
        path.close()
        return path
    }
}

struct MenuBarMark: View {
    var height: CGFloat = 16
    /// Popover is always dark. The menu bar follows the system appearance.
    var lightGlyph = false

    var body: some View {
        TemplateGlyph(lightGlyph: lightGlyph)
            .frame(width: height, height: height)
            .accessibilityLabel("Dev Runner")
    }
}

private struct TemplateGlyph: NSViewRepresentable {
    var lightGlyph: Bool

    func makeNSView(context: Context) -> TemplateGlyphView {
        let view = TemplateGlyphView(frame: .zero)
        view.lightGlyph = lightGlyph
        return view
    }

    func updateNSView(_ view: TemplateGlyphView, context: Context) {
        view.lightGlyph = lightGlyph
    }
}

private final class TemplateGlyphView: NSView {
    var lightGlyph = false {
        didSet { needsDisplay = true }
    }

    private var observingTheme = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !observingTheme else { return }
        observingTheme = true
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(themeChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @objc private func themeChanged() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        glyphColor.setFill()
        MenuBarIcon.path(in: bounds).fill()
    }

    private var glyphColor: NSColor {
        drawsLightGlyph ? .white : .black
    }

    private var drawsLightGlyph: Bool {
        if lightGlyph { return true }
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (domain?["AppleInterfaceStyle"] as? String) == "Dark"
    }
}
