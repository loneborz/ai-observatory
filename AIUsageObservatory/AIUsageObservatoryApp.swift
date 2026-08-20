import AppKit
import SwiftUI

@main
struct AIUsageObservatoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(presenter: appDelegate.presenter)
        } label: {
            MenuBarLabel(presenter: appDelegate.presenter)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let presenter = UsagePresenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UsageDisplay.logInvariantCheck()
        presenter.start()
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var presenter: UsagePresenter

    var body: some View {
        switch presenter.menuBarAppearance {
        case .percent(let percent, let nearExhaustion):
            Image(nsImage: StatusItemImage.percent(percent, warning: nearExhaustion))
                .renderingMode(nearExhaustion ? .original : .template)
                .accessibilityLabel("\(percent)%")
        case .glyph:
            Image(systemName: "gauge")
                .accessibilityLabel("Codex usage")
        }
    }
}

private enum StatusItemImage {
    static func percent(_ percent: Int, warning: Bool) -> NSImage {
        let text = "\(percent)%" as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let color: NSColor = warning ? .systemOrange : .black
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let textSize = text.size(withAttributes: attributes)
        let size = NSSize(width: ceil(textSize.width), height: ceil(max(textSize.height, 18)))
        let image = NSImage(size: size, flipped: false) { rect in
            let origin = NSPoint(x: 0, y: (rect.height - textSize.height) / 2)
            text.draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = !warning
        return image
    }
}
