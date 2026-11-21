import SwiftUI

struct MenuBarView: View {
    static let popoverWidth: CGFloat = 288

    @EnvironmentObject private var controller: KeyboardSoundController

    var body: some View {
        VStack(spacing: 0) {
            // Shown while a premium preview is active
            if let preview = controller.previewPack {
                previewBar(pack: preview)
                Divider()
            }

            // Shown after a preview ends
            if controller.showUpgradeCTA, let cta = controller.ctaPack {
                ctaBar(pack: cta)
                Divider()
            }

            header
            Divider()
            if let storeStatus = controller.premiumStoreStatusText {
                storeStatusBar(storeStatus)
                Divider()
            }
            if controller.shouldShowPremiumPurchaseUI {
                premiumPurchaseBar
                Divider()
            }
            if controller.setupPhase != .complete {
                setupBar
                Divider()
            }
            if let issue = controller.inputMonitoringIssue {
                statusBar(issue)
                Divider()
            }
            if let sampleError = controller.sampleErrorMessage {
                statusBar(sampleError)
                Divider()
            }
            packList
            Divider()
            volumeControl
            Divider()
            footer
        }
        .frame(width: Self.popoverWidth)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Tappy")
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusDotColor: Color {
        switch controller.setupPhase {
        case .needsPermission, .needsRestart: return .orange
        case .complete: return controller.isEnabled ? .green : Color.secondary
        }
    }

    private var statusLabel: String {
        switch controller.setupPhase {
        case .needsPermission: return "Setup needed"
        case .needsRestart: return "Restart required"
        case .complete: return controller.isEnabled ? "Active" : "Paused"
        }
    }

    private func storeStatusBar(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .opacity(controller.isPremiumStoreBusy ? 1 : 0)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.04))
    }

    /// Error bar shown only when system-wide input monitoring isn't working.
    private func statusBar(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.06))
    }

    private var premiumPurchaseBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Unlock ASMR Packs", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(controller.premiumUnlockPrice)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Unlock every sound pack with a one-time App Store purchase.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                controller.buyPremium()
            } label: {
                Label(controller.premiumUnlockPrice.isEmpty ? "Buy All Packs" : "Buy \(controller.premiumUnlockPrice)", systemImage: "cart.fill")
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!controller.canRequestPremiumPurchase)

            Button("Restore Purchases") {
                controller.restorePurchases()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .disabled(controller.isPremiumStoreBusy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.04))
    }

    // MARK: - Setup bar

    private var setupBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(controller.setupHeadline, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(setupMenuDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Button(controller.setupPrimaryButtonTitle) {
                controller.performSetupPrimaryAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.04))
        .onAppear {
            controller.requestStartupInputMonitoringPromptIfNeeded()
        }
    }

    private var setupMenuDetail: String {
        switch controller.setupPhase {
        case .needsPermission:
            return "Enable Input Monitoring so Tappy can provide auditory typing feedback in other apps. Tappy uses physical key codes only and never records typed text."
        case .needsRestart:
            return "Restart once so macOS applies the new permission."
        case .complete:
            return ""
        }
    }

    // MARK: - Live preview bar

    @ViewBuilder
    private func previewBar(pack: TechPack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                Text("Previewing \(pack.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text("Switches back to the free sound at the limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                if controller.shouldShowPremiumPurchaseUI {
                    Button(controller.premiumUnlockPrice.isEmpty ? "Buy All Packs" : "Buy \(controller.premiumUnlockPrice)") {
                        controller.buyPremium()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .disabled(!controller.canRequestPremiumPurchase)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.05))
    }

    // MARK: - Post-preview CTA bar

    @ViewBuilder
    private func ctaBar(pack: TechPack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enjoying these switches?")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Unlock the full pack for unlimited typing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(controller.premiumUnlockPrice.isEmpty ? "Buy All Packs" : "Buy \(controller.premiumUnlockPrice)") {
                    controller.buyPremium()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .disabled(!controller.canRequestPremiumPurchase)

                Button("Not Now") {
                    controller.dismissUpgradeCTA()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.05))
    }

    // MARK: - Pack list

    private var packList: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(controller.availablePacks) { pack in
                    PackRow(pack: pack)
                        .environmentObject(controller)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 360)
    }

    // MARK: - Volume

    private var volumeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Feedback Volume", systemImage: "speaker.wave.2.fill")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer()

                Text("\(Int((controller.clickVolume * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $controller.clickVolume, in: 0...1)
                    .controlSize(.small)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Toggle(isOn: $controller.isEnabled) {
                Label("Feedback", systemImage: "keyboard")
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(controller.setupPhase != .complete)

            Spacer()

            Button("Privacy") {
                controller.showAnalyticsPrivacy()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.trailing, 12)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Pack row

private struct PackRow: View {
    let pack: TechPack
    @EnvironmentObject private var controller: KeyboardSoundController
    @State private var isHovered = false
    @State private var showLockedPackOptions = false

    private var isActive: Bool { pack.id == controller.currentPack.id }
    private var isLocked: Bool { controller.isPackLocked(pack) }
    private var isTrying: Bool { controller.previewPack?.id == pack.id }
    private var isHighlighted: Bool { pack.id == controller.highlightedPackID }

    private var lockedPackAlertTitle: String {
        "Preview \(pack.name)?"
    }

    private var iconColor: Color {
        switch pack.id {
        case TechPack.plasticTapping.id:  return Color(red: 0.48, green: 0.72, blue: 1.00)
        case TechPack.farming.id:         return Color(red: 0.38, green: 0.82, blue: 0.46)
        case TechPack.swordBattle.id:     return Color(red: 1.00, green: 0.45, blue: 0.32)
        case TechPack.bubble.id:          return Color(red: 0.38, green: 0.88, blue: 0.88)
        case TechPack.stars.id:           return Color(red: 1.00, green: 0.82, blue: 0.30)
        case TechPack.woodBrush.id:       return Color(red: 0.85, green: 0.62, blue: 0.38)
        case TechPack.analogStopwatch.id: return Color(red: 0.72, green: 0.78, blue: 0.90)
        case TechPack.squishyPop.id:       return Color(red: 0.70, green: 0.52, blue: 1.00)
        case TechPack.waxCracking.id:      return Color(red: 0.96, green: 0.42, blue: 0.58)
        case TechPack.fart.id:             return Color(red: 0.65, green: 0.76, blue: 0.35)
        case TechPack.paperCrinkle.id:     return Color(red: 0.82, green: 0.73, blue: 0.58)
        case TechPack.plasticCrinkle.id:   return Color(red: 0.46, green: 0.76, blue: 0.85)
        case TechPack.wetMouth.id:         return Color(red: 0.86, green: 0.51, blue: 0.65)
        case TechPack.suckingWaterThroughATube.id: return Color(red: 0.43, green: 0.72, blue: 0.88)
        case TechPack.hairBrushing.id: return Color(red: 0.77, green: 0.61, blue: 0.82)
        case TechPack.splashingWater.id: return Color(red: 0.31, green: 0.70, blue: 0.86)
        case TechPack.gentleWaterSwishing.id: return Color(red: 0.39, green: 0.76, blue: 0.79)
        case TechPack.scissorsCutting.id: return Color(red: 0.67, green: 0.72, blue: 0.79)
        case TechPack.catMeows.id: return Color(red: 0.90, green: 0.64, blue: 0.45)
        case TechPack.dogBarks.id: return Color(red: 0.76, green: 0.63, blue: 0.45)
        case TechPack.running.id: return Color(red: 0.50, green: 0.73, blue: 0.52)
        case TechPack.thud.id: return Color(red: 0.68, green: 0.50, blue: 0.40)
        default:                          return .accentColor
        }
    }

    var body: some View {
        lockedPackRow
    }

    private var packRowContent: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(iconColor.opacity(isActive || isTrying ? 0.20 : 0.10))
                    .frame(width: 30, height: 30)
                Image(systemName: NSImage(systemSymbolName: pack.symbolName, accessibilityDescription: nil) == nil ? "water.waves" : pack.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(isActive || isTrying ? 1.0 : 0.8))

                if isLocked && !isTrying {
                    Circle()
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(width: 13, height: 13)
                        .overlay(
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        )
                        .offset(x: 9, y: 9)
                } else if isTrying {
                    Circle()
                        .fill(Color(NSColor.windowBackgroundColor))
                        .frame(width: 13, height: 13)
                        .overlay(
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 7, height: 7)
                        )
                        .offset(x: 9, y: 9)
                }
            }

            Text(pack.name)
                .font(.subheadline)
                .fontWeight(isActive || isTrying ? .semibold : .regular)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer()

            if isLocked && !isTrying {
                Button {
                    controller.highlightPack(pack)
                    controller.playPremiumDemo()
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Play a sample of \(pack.name)")
            }

            if isActive && !isTrying {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 42)
        .background(rowBackgroundColor)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if isLocked && !isTrying {
                controller.highlightPack(pack)
                showLockedPackOptions = true
            } else {
                controller.highlightPack(pack)
            }
        }
    }

    private var lockedPackRow: some View {
        packRowContent
        .alert(
            lockedPackAlertTitle,
            isPresented: $showLockedPackOptions
        ) {
            Button("Play Sample") {
                controller.highlightPack(pack)
                controller.playPremiumDemo()
            }
            if controller.shouldShowPremiumPurchaseUI {
                Button(controller.premiumUnlockPrice.isEmpty ? "Buy All Packs" : "Buy All Packs — \(controller.premiumUnlockPrice)") {
                    controller.highlightPack(pack)
                    controller.buyPremium()
                }
                .disabled(!controller.canRequestPremiumPurchase)
            }
            Button("Go Back", role: .cancel) {}
        } message: {
            Text("Play a sample, or unlock all packs to use them while you type.")
        }
    }

    private var rowBackgroundColor: Color {
        if isTrying {
            return Color.accentColor.opacity(0.08)
        }
        if isHighlighted && !isActive {
            return Color.primary.opacity(0.07)
        }
        if isHovered && !isActive {
            return Color.primary.opacity(0.05)
        }
        return .clear
    }
}
