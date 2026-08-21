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
#if DEBUG
        UsageRefreshSchedule.logInvariantCheck()
#endif
        presenter.start()
#if DEBUG
        if let path = ProcessInfo.processInfo.environment["AI_USAGE_OBSERVATORY_SCREENSHOT_PATH"] {
            screenshotPanel = ScreenshotCapture.start(presenter: presenter, outputPath: path)
        }
#endif
    }

#if DEBUG
    private var screenshotPanel: NSPanel?
#endif
}

private struct MenuBarLabel: View {
    @ObservedObject var presenter: UsagePresenter

    var body: some View {
        switch presenter.menuBarAppearance {
        case .percent(let percent, let nearExhaustion):
            Image(nsImage: StatusItemImage.percent(percent, warning: nearExhaustion))
                .renderingMode(nearExhaustion ? .original : .template)
                .accessibilityLabel("AI Usage Observatory, \(percent)% used")
        case .glyph:
            Image(systemName: "gauge")
                .accessibilityLabel("AI Usage Observatory, Codex usage")
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

#if DEBUG
private struct ScreenshotSurface: View {
    @ObservedObject var presenter: UsagePresenter

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
            UsagePopoverView(presenter: presenter)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        .padding(24)
        .fixedSize()
    }
}

@MainActor
private enum ScreenshotCapture {
    static func start(presenter: UsagePresenter, outputPath: String) -> NSPanel {
        let hostingView = NSHostingView(rootView: ScreenshotSurface(presenter: presenter))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = hostingView
        panel.center()
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                let bounds = hostingView.bounds
                guard let representation = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(ceil(bounds.width * 2)),
                    pixelsHigh: Int(ceil(bounds.height * 2)),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bitmapFormat: [],
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                representation.size = bounds.size
                hostingView.cacheDisplay(in: bounds, to: representation)
                guard let data = representation.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let outputURL = URL(fileURLWithPath: outputPath)
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: outputURL)
                fputs("screenshot-capture: wrote \(outputURL.path)\n", stderr)
            } catch {
                fputs("screenshot-capture: \(error)\n", stderr)
            }
            NSApp.terminate(nil)
        }
        return panel
    }
}
#endif
