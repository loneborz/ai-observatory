import AppKit
import SwiftUI

@main
struct AIObservatoryApp: App {
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
        if let path = ProcessInfo.processInfo.environment["AI_OBSERVATORY_SCREENSHOT_PATH"] {
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
        case .quotas(let quotas):
            let hasWarning = quotas.contains { $0.nearExhaustion }
            Image(nsImage: StatusItemImage.quotas(quotas))
                .renderingMode(hasWarning ? .original : .template)
                .accessibilityLabel(
                    "AI Observatory, " + quotas.map {
                        "\($0.remainingPercent)% remaining \($0.shortLabel)"
                    }.joined(separator: ", ")
                )
        case .glyph:
            Image(systemName: "gauge")
                .accessibilityLabel("AI Observatory, Codex usage")
        }
    }
}

private enum StatusItemImage {
    static func quotas(_ quotas: [MenuBarQuota]) -> NSImage {
        guard quotas.count > 1 else {
            return singleLine(quotas.first)
        }

        let lines = quotas.prefix(2).map(attributedLine)
        let lineSizes = lines.map { $0.size() }
        let width = ceil(lineSizes.map(\.width).max() ?? 0)
        let height = 20.0
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let lineHeight = rect.height / 2
            for (index, line) in lines.enumerated() {
                line.draw(at: NSPoint(x: 0, y: rect.height - CGFloat(index + 1) * lineHeight))
            }
            return true
        }
        image.isTemplate = !quotas.contains { $0.nearExhaustion }
        return image
    }

    private static func singleLine(_ quota: MenuBarQuota?) -> NSImage {
        guard let quota else {
            return NSImage(size: NSSize(width: 1, height: 18))
        }
        let line = attributedLine(quota)
        let lineSize = line.size()
        let size = NSSize(width: ceil(lineSize.width), height: ceil(max(lineSize.height, 18)))
        let image = NSImage(size: size, flipped: false) { rect in
            line.draw(at: NSPoint(x: 0, y: (rect.height - lineSize.height) / 2))
            return true
        }
        image.isTemplate = !quota.nearExhaustion
        return image
    }

    private static func attributedLine(_ quota: MenuBarQuota) -> NSAttributedString {
        let line = NSMutableAttributedString(
            string: "\(quota.remainingPercent)%",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: quota.nearExhaustion ? .medium : .regular),
                .foregroundColor: quota.nearExhaustion ? NSColor.systemOrange : NSColor.labelColor,
            ]
        )
        line.append(
            NSAttributedString(
                string: " \(quota.shortLabel)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .medium),
                    .foregroundColor: quota.nearExhaustion ? NSColor.systemOrange : NSColor.labelColor,
                ]
            )
        )
        return line
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
                let captureScale = CGFloat(ProcessInfo.processInfo.environment["AI_OBSERVATORY_CAPTURE_SCALE"].flatMap(Double.init) ?? 2)
                guard let representation = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(ceil(bounds.width * captureScale)),
                    pixelsHigh: Int(ceil(bounds.height * captureScale)),
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
