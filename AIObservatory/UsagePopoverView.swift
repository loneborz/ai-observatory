import AppKit
import ServiceManagement
import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var presenter: UsagePresenter
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?
    @State private var isUpdatingLoginItem = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            content

            loginItemControl

            HStack {
                // MenuBarExtra window style auto-invokes the first button.
                Button("") {}
                    .keyboardShortcut(.defaultAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)

                Button("Refresh") {
                    presenter.refreshNow()
                }
                .disabled(presenter.isRefreshing)
                .keyboardShortcut("r", modifiers: [.command])

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .onAppear {
            presenter.refreshFromPopover()
            refreshLoginItemStatus()
        }
    }

    @ViewBuilder
    private var loginItemControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { loginItemStatus.isEnabled },
                    set: { setLoginItem(enabled: $0) }
                )
            )
            .disabled(isUpdatingLoginItem || loginItemStatus.needsApproval)

            Text(loginItemStatus.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if loginItemStatus.needsApproval {
                Button("Open Login Items…") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .font(.caption)
            }

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    private func setLoginItem(enabled: Bool) {
        isUpdatingLoginItem = true
        defer {
            loginItemStatus = SMAppService.mainApp.status
            isUpdatingLoginItem = false
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn’t update Launch at Login: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("AI Observatory")
                .font(.headline)
            Text(providerContext)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var providerContext: String {
        guard case .available(let snapshot) = presenter.state,
              let plan = UsageDisplay.planSubtitle(snapshot.planType)
        else {
            return "Codex"
        }
        return "Codex · \(plan)"
    }

    @ViewBuilder
    private var content: some View {
        switch presenter.state {
        case .idle, .loading:
            Text("Reading usage…")
                .foregroundStyle(.secondary)
        case .available(let snapshot):
            AvailableUsageView(snapshot: snapshot)
        case .loggedOut(let message), .unavailable(let message), .error(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension SMAppService.Status {
    var isEnabled: Bool {
        if case .enabled = self {
            return true
        }
        return false
    }

    var needsApproval: Bool {
        if case .requiresApproval = self {
            return true
        }
        return false
    }

    var label: String {
        switch self {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Not registered"
        case .requiresApproval:
            return "Approval required"
        case .notFound:
            return "Unavailable"
        @unknown default:
            return "Unavailable"
        }
    }
}

private struct AvailableUsageView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let percent = snapshot.constrainingUsedPercent {
                Text("\(percent)%")
                    .font(.system(size: 28, weight: .regular).monospacedDigit())
                    .foregroundStyle(percentColor)
            }

            if let window = snapshot.constrainingWindow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UsageDisplay.windowLabel(window))
                    if let reset = UsageDisplay.resetPhrase(window.resetsAt) {
                        Text(reset)
                    }
                }
                .foregroundStyle(.secondary)
            }

            ForEach(snapshot.additionalWindows) { window in
                additionalWindow(window)
            }

            if snapshot.showsCredits {
                creditsRow
            }

            if snapshot.showsLimitReached {
                Text("Limit reached")
                    .foregroundStyle(.secondary)
            }

            Text(UsageDisplay.updatedPhrase(snapshot.fetchedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var percentColor: Color {
        snapshot.emphasizesNearExhaustion ? Color(nsColor: .systemOrange) : Color.primary
    }

    private var creditsRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Credits")
                .foregroundStyle(.secondary)
            Spacer()
            if let balance = UsageDisplay.creditsBalance(snapshot.creditBalance) {
                Text(balance)
            }
        }
    }

    private func additionalWindow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(UsageDisplay.windowLabel(window))
                Spacer()
                if let percent = window.usedPercent {
                    Text("\(percent)%")
                        .monospacedDigit()
                }
            }
            if let reset = UsageDisplay.resetPhrase(window.resetsAt) {
                Text(reset)
                    .font(.caption)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.tertiary)
    }
}
