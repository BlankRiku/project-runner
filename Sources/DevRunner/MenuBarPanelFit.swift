import AppKit
import SwiftUI

/// MenuBarExtra(.window) often shifts its panel down when the content size or page changes.
/// Keep the panel at the measured size and re-anchor under the status item (not current maxY).
struct MenuBarPanelFit: NSViewRepresentable {
    var width: CGFloat
    var height: CGFloat
    /// Bumped on navigation / overlays so we re-pin Y even when size is unchanged.
    var placementToken: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let width = width
        let height = height
        let token = placementToken
        guard width > 1, height > 1 else { return }
        let place: @MainActor @Sendable () -> Void = {
            guard let window = nsView.window else { return }
            let current = window.contentView?.bounds.size ?? .zero
            let sizeChanged = abs(current.width - width) > 0.5 || abs(current.height - height) > 0.5
            if sizeChanged {
                window.setContentSize(NSSize(width: width, height: height))
            }
            guard let anchorY = Self.statusItemBottomY(for: window) else { return }
            var frame = window.frame
            let targetY = anchorY - frame.height
            guard sizeChanged || abs(frame.origin.y - targetY) > 0.5 else { return }
            frame.origin.y = targetY
            window.setFrame(frame, display: true, animate: false)
        }
        // MenuBarExtra may move the panel after our first pass; pin again on the next turns.
        DispatchQueue.main.async { place() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            _ = token
            place()
        }
    }

    /// Bottom edge of the nearest status item in screen coordinates (AppKit, Y up).
    private static func statusItemBottomY(for panel: NSWindow) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for window in NSApp.windows {
            guard String(describing: type(of: window)).contains("StatusBar") else { continue }
            func walk(_ view: NSView) {
                if let button = view as? NSStatusBarButton, let buttonWindow = button.window {
                    let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                    let dx = abs(rect.midX - panel.frame.midX)
                    if dx < bestDistance {
                        bestDistance = dx
                        best = rect.minY
                    }
                }
                for subview in view.subviews {
                    walk(subview)
                }
            }
            if let content = window.contentView {
                walk(content)
            }
        }
        return best
    }
}

private struct MenuBarPanelSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct FitMenuBarPanelModifier: ViewModifier {
    var width: CGFloat
    var maxHeight: CGFloat
    var placementToken: Int
    @State private var measured = CGSize.zero

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: width, maxHeight: maxHeight, alignment: .top)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MenuBarPanelSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(MenuBarPanelSizeKey.self) { size in
                guard abs(size.width - measured.width) > 0.5 || abs(size.height - measured.height) > 0.5 else { return }
                measured = size
            }
            .background(alignment: .topLeading) {
                MenuBarPanelFit(
                    width: measured.width > 1 ? measured.width : width,
                    height: measured.height > 1 ? measured.height : maxHeight,
                    placementToken: placementToken
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Sizes the hosting MenuBarExtra panel to this view and pins it under the status item.
    func fitMenuBarPanel(width: CGFloat, maxHeight: CGFloat = 640, placementToken: Int = 0) -> some View {
        modifier(FitMenuBarPanelModifier(width: width, maxHeight: maxHeight, placementToken: placementToken))
    }
}
