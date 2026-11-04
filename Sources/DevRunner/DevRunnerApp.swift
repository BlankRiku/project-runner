import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated {
                MenuBarIcon.apply(count: MenuBarIcon.latestCount)
            }
        }
    }

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

    init() {
        MenuBarIcon.register()
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        let count = model.activeCount
        MenuBarIcon.scheduleApply(count: count)
        return MenuBarExtra {
            RootView()
                .environmentObject(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
enum MenuBarIcon {
    /// Point height of the menu bar glyph.
    static let menuBarHeight: CGFloat = 18
    static let templateName = "MenuBarIconTemplate"

    static let image: NSImage = load()

    static var aspectRatio: CGFloat {
        image.size.width / max(image.size.height, 1)
    }

    fileprivate static var latestCount = 0
    private static var applyScheduled = false

    static func register() {
        image.isTemplate = true
        image.setName(NSImage.Name(templateName))
    }

    static func scheduleApply(count: Int) {
        latestCount = count
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async {
            applyScheduled = false
            apply(count: latestCount)
        }
    }

    static func apply(count: Int) {
        latestCount = count
        let icon = image
        icon.isTemplate = true
        for button in statusButtons() {
            button.image = icon
            button.image?.isTemplate = true
            button.imageScaling = .scaleProportionallyDown
            button.imageHugsTitle = true
            button.imagePosition = count > 0 ? .imageLeading : .imageOnly
            button.title = count > 0 ? "\(count)" : ""
            button.setAccessibilityLabel("Dev Runner")
        }
    }

    private static func statusButtons() -> [NSStatusBarButton] {
        var found: [NSStatusBarButton] = []
        for window in NSApp.windows {
            func walk(_ view: NSView?) {
                guard let view else { return }
                if let button = view as? NSStatusBarButton {
                    found.append(button)
                }
                for subview in view.subviews {
                    walk(subview)
                }
            }
            walk(window.contentView)
        }
        return found
    }

    private static func load() -> NSImage {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
              let source = NSImage(contentsOf: url),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            preconditionFailure("MenuBarIcon.png is missing from the app bundle")
        }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            preconditionFailure("MenuBarIcon.png could not be converted to a template mask")
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[i + 3]
            pixels[i] = 0
            pixels[i + 1] = 0
            pixels[i + 2] = 0
            pixels[i + 3] = alpha
        }
        guard let maskCG = context.makeImage() else {
            preconditionFailure("MenuBarIcon.png mask export failed")
        }
        let image = NSImage(cgImage: maskCG, size: NSSize(width: width, height: height))
        let aspect = CGFloat(width) / CGFloat(height)
        image.size = NSSize(width: menuBarHeight * aspect, height: menuBarHeight)
        image.isTemplate = true
        image.accessibilityDescription = "Dev Runner"
        return image
    }
}

struct MenuBarMark: View {
    var height: CGFloat = 16

    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: height * MenuBarIcon.aspectRatio, height: height)
            .accessibilityLabel("Dev Runner")
    }
}
