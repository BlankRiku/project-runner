import AppKit
import SwiftUI

/// MenuBarExtra(.window) grows with content but keeps a high-water height when content shrinks,
/// leaving a transparent gap and shifting the panel down. Force the panel to the measured size
/// while pinning the top edge.
struct MenuBarPanelFit: NSViewRepresentable {
    var width: CGFloat
    var height: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let width = width
        let height = height
        guard width > 1, height > 1 else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let current = window.contentView?.bounds.size ?? .zero
            guard abs(current.width - width) > 0.5 || abs(current.height - height) > 0.5 else { return }
            let top = window.frame.maxY
            window.setContentSize(NSSize(width: width, height: height))
            var frame = window.frame
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true, animate: false)
        }
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
    @State private var measured = CGSize.zero

    func body(content: Content) -> some View {
        content
            // Ignore the panel's high-water proposed height; size to the SwiftUI content.
            .fixedSize(horizontal: false, vertical: true)
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
                MenuBarPanelFit(width: width, height: measured.height)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Sizes the hosting MenuBarExtra panel to this view's intrinsic height.
    func fitMenuBarPanel(width: CGFloat, maxHeight: CGFloat = 640) -> some View {
        modifier(FitMenuBarPanelModifier(width: width, maxHeight: maxHeight))
    }
}
