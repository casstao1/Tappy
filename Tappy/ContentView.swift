import SwiftUI

// MARK: - Deep Aurora colour tokens
private extension Color {
    /// The three mesh blobs that make up the aurora background
    static let auroraIndigo  = Color(red: 0.231, green: 0.122, blue: 0.659)  // #3b1fa8
    static let auroraBlue    = Color(red: 0.102, green: 0.173, blue: 0.541)  // #1a2c8a
    static let auroraPurple  = Color(red: 0.290, green: 0.082, blue: 0.439)  // #4a1570
    static let auroraBase    = Color(red: 0.055, green: 0.044, blue: 0.125)  // #0e0b20

    /// Card surfaces
    static let cardSurface   = Color(red: 0.059, green: 0.039, blue: 0.125).opacity(0.72) // #0f0a20
    static let cardBorder    = Color.white.opacity(0.07)

    /// Active / selected purple
    static let accentPurple  = Color(red: 0.482, green: 0.353, blue: 0.941)  // #7b5af0
    static let accentSoft    = Color(red: 0.608, green: 0.478, blue: 1.0)    // #9b7aff

    /// Text
    static let textPrimary   = Color(red: 0.933, green: 0.914, blue: 1.0)    // #ede9ff
    static let textSecondary = Color(red: 0.745, green: 0.725, blue: 0.941).opacity(0.5)
}

struct ContentView: View {
    @EnvironmentObject private var controller: KeyboardSoundController
    @State private var showingDiagnostics = false
    @State private var showingPaywall = false

    var body: some View {
        Group {
            if controller.shouldShowSetupGate {
                setupScreen
            } else {
                homeScreen
            }
        }
        .frame(minWidth: 640, minHeight: 500)
        .sheet(isPresented: $showingDiagnostics) {
            diagnosticsSheet
        }
        .sheet(isPresented: $showingPaywall) {
            premiumPaywallSheet
        }
    }

    // MARK: - Aurora background

    /// Three overlapping radial blobs on a dark base — the "deep aurora" mesh.
    private var auroraBackground: some View {
        ZStack {
            Color.auroraBase

            // Top-left indigo blob
            RadialGradient(
                colors: [Color.auroraIndigo.opacity(0.65), .clear],
                center: .init(x: 0.15, y: 0.25),
                startRadius: 0,
                endRadius: 320
            )

            // Bottom-right blue blob
            RadialGradient(
                colors: [Color.auroraBlue.opacity(0.55), .clear],
                center: .init(x: 0.88, y: 0.80),
                startRadius: 0,
                endRadius: 290
            )

            // Centre deep-purple blob
            RadialGradient(
                colors: [Color.auroraPurple.opacity(0.42), .clear],
                center: .init(x: 0.50, y: 0.50),
                startRadius: 0,
                endRadius: 260
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Home screen

    private var homeScreen: some View {
        ZStack {
            auroraBackground

            VStack(spacing: 20) {
                topBar
                if let launchWarning = controller.launchWarning {
                    warningBanner(text: launchWarning)
                }
                packCarousel
                packDetail
                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Setup screen

    private var setupScreen: some View {
        ZStack {
            auroraBackground

            // Frosted card
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.accentPurple.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: Color.accentPurple.opacity(0.18), radius: 40, y: 20)
                .padding(26)

            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Tappy")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.textPrimary)

                    Text(controller.setupHeadline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.textPrimary.opacity(0.85))

                    Text(controller.setupDetail)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }

                VStack(spacing: 14) {
                    ForEach(controller.setupChecklist) { item in
                        HStack(spacing: 14) {
                            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isComplete ? Color.accentSoft : Color.white.opacity(0.3))
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.textPrimary)

                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }

                            Spacer()

                            Button(item.actionTitle) {
                                item.action()
                            }
                            .buttonStyle(AuroraButtonStyle())
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .frame(maxWidth: 520)

                if let launchWarning = controller.launchWarning {
                    warningBanner(text: launchWarning)
                        .frame(maxWidth: 520)
                }

                HStack(spacing: 12) {
                    Button("Request Access") {
                        controller.requestKeyboardPermission()
                    }
                    .buttonStyle(AuroraButtonStyle())

                    if controller.canUseManualPermissionOverride {
                        Button("It's Already On") {
                            controller.confirmPermissionOverride()
                        }
                        .buttonStyle(AuroraButtonStyle())
                    }

                    Button("Let's Get Tappy") {
                        controller.completeSetupAndEnterHome()
                    }
                    .buttonStyle(AuroraPrimaryButtonStyle())
                    .disabled(!controller.isReadyForHomeScreen)
                }

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(32)
        }
    }

    // MARK: - Warning banner

    private func warningBanner(text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary.opacity(0.85))
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 24) {
            Text("Tappy")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            // Diagnose — frosted glass pill
            Button {
                controller.refreshInputMonitoringStatus()
                showingDiagnostics = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: controller.launchWarning == nil ? "sparkles" : "stethoscope")
                        .font(.system(size: 13, weight: .bold))
                    Text("Diagnose")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.textPrimary.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.09))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(controller.launchWarning == nil ? 0.14 : 0.0), lineWidth: 1)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.orange.opacity(controller.launchWarning == nil ? 0.0 : 0.5), lineWidth: 1)
                )
                .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())

            Toggle("", isOn: $controller.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(1.25)
                .tint(Color.accentPurple)
        }
    }

    // MARK: - Pack carousel

    private var packCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(controller.availablePacks) { pack in
                        Button {
                            controller.highlightPack(pack)
                            if controller.isPackLocked(pack) {
                                showingPaywall = true
                            }
                        } label: {
                            PackCard(
                                pack: pack,
                                isHighlighted: controller.highlightedPackID == pack.id,
                                isCurrent: controller.currentPack.id == pack.id,
                                isLocked: controller.isPackLocked(pack)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
        }
    }

    // MARK: - Pack detail

    @ViewBuilder
    private var packDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(controller.highlightedPack.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if controller.highlightedPackIsLocked {
                    Label("Premium", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orange.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule(style: .continuous))
                }
            }

            Text(controller.highlightedPack.blurb)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            if controller.highlightedPackIsLocked {
                premiumPreviewPanel
            } else {
                activePackPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var premiumPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview sounds")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textPrimary.opacity(0.84))

            HStack(spacing: 8) {
                previewButton("Default", category: .standard)
                previewButton("Space", category: .space)
                previewButton("Return", category: .returnKey)
                previewButton("Delete", category: .delete)
                previewButton("Modifier", category: .modifier)
            }

            HStack(spacing: 10) {
                Button {
                    showingPaywall = true
                } label: {
                    Text("Unlock All Packs")
                }
                .buttonStyle(AuroraPrimaryButtonStyle())

                Text("Preview works now. Activation stays locked until purchase.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, 4)
    }

    private var activePackPanel: some View {
        HStack(spacing: 10) {
            Label(
                controller.highlightedPack.isPremium ? "Premium Active" : "Free Pack",
                systemImage: controller.highlightedPack.isPremium ? "lock.open.fill" : "checkmark.circle.fill"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(controller.highlightedPack.isPremium ? Color.accentSoft : Color.green.opacity(0.9))

            Spacer()

            Button("Preview") {
                controller.preview(category: .standard)
            }
            .buttonStyle(AuroraButtonStyle())
        }
        .padding(.top, 4)
    }

    private func previewButton(_ title: String, category: SoundCategory) -> some View {
        Button(title) {
            controller.previewHighlightedPack(category: category)
        }
        .buttonStyle(AuroraButtonStyle())
    }

    // MARK: - Diagnostics sheet

    private var diagnosticsSheet: some View {
        ZStack {
            Color(red: 0.07, green: 0.055, blue: 0.16).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Diagnostics")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    Button {
                        showingDiagnostics = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                statusCard

                if !isTappyWorking {
                    actionButtons
                } else {
                    HStack {
                        Spacer()
                        Button {
                            controller.refreshInputMonitoringStatus()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(AuroraButtonStyle())
                    }
                }
            }
            .padding(26)
        }
        .frame(width: 440)
    }

    @ViewBuilder
    private var actionButtons: some View {
        let needsPermission = !controller.permissionManager.isTrusted

        HStack(spacing: 10) {
            if needsPermission {
                Button {
                    controller.openInputMonitoringSettings()
                } label: {
                    Text("Open Input Monitoring")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AuroraPrimaryButtonStyle())
                .controlSize(.large)
            }

            if needsPermission {
                Button {
                    controller.relaunchApp()
                } label: {
                    Text("Relaunch Tappy")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AuroraButtonStyle())
                .controlSize(.large)
            } else {
                Button {
                    controller.relaunchApp()
                } label: {
                    Text("Relaunch Tappy")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AuroraPrimaryButtonStyle())
                .controlSize(.large)
            }

            Button {
                controller.refreshInputMonitoringStatus()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 20)
            }
            .buttonStyle(AuroraButtonStyle())
            .controlSize(.large)
            .help("Refresh status")
        }
    }

    private var isTappyWorking: Bool {
        controller.permissionManager.isTrusted
            && controller.backgroundCaptureState == .ready
    }

    private var statusCard: some View {
        let title: String
        let detail: String

        if !controller.permissionManager.isTrusted {
            title = "Input Monitoring Needed"
            detail = "Enable Tappy under System Settings › Privacy & Security › Input Monitoring, then tap Relaunch Tappy for the change to take effect."
        } else if controller.backgroundCaptureState != .ready {
            title = "Relaunch Required"
            detail = "Permission is granted but the keyboard listener didn't attach. Relaunch Tappy to apply the new permission."
        } else {
            title = "Tappy is Ready"
            detail = "The keyboard listener is active and Input Monitoring is confirmed by macOS."
        }

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: isTappyWorking ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(isTappyWorking ? Color.accentSoft : Color.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var premiumPaywallSheet: some View {
        ZStack {
            Color(red: 0.07, green: 0.055, blue: 0.16).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Unlock Premium Packs")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text("Plastic Tapping and Farming stay free. Everything else unlocks with one purchase.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Includes")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    ForEach(controller.premiumPacks) { pack in
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.orange.opacity(0.95))

                            Text(pack.name)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    Text("\(controller.premiumUnlockPrice) one-time unlock")
                        .font(.headline)
                        .foregroundStyle(Color.orange.opacity(0.95))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if controller.isPremiumStoreLoading || controller.isPremiumPurchaseInFlight {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text(controller.isPremiumPurchaseInFlight ? "Processing purchase..." : "Loading store...")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if let premiumStoreMessage = controller.premiumStoreMessage {
                    Text(premiumStoreMessage)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(spacing: 10) {
                    Button("Not Now") {
                        showingPaywall = false
                    }
                    .buttonStyle(AuroraButtonStyle())

                    Button("Restore Purchases") {
                        Task {
                            await controller.restorePremiumPurchases()
                            if controller.premiumUnlocked {
                                showingPaywall = false
                            }
                        }
                    }
                    .buttonStyle(AuroraButtonStyle())
                    .disabled(controller.isPremiumStoreLoading || controller.isPremiumPurchaseInFlight)

                    Button("Unlock All for \(controller.premiumUnlockPrice)") {
                        Task {
                            await controller.purchasePremiumUnlock()
                            if controller.premiumUnlocked {
                                showingPaywall = false
                            }
                        }
                    }
                    .buttonStyle(AuroraPrimaryButtonStyle())
                    .disabled(controller.premiumUnlocked || controller.isPremiumStoreLoading || controller.isPremiumPurchaseInFlight)
                }
            }
            .padding(26)
        }
        .frame(width: 420)
        .onAppear {
            controller.beginUnlockPremiumFlow()
        }
    }
}

// MARK: - Pack card

private struct PackCard: View {
    let pack: TechPack
    let isHighlighted: Bool
    let isCurrent: Bool
    let isLocked: Bool
    @State private var isHovered = false

    /// A thematic colour for each pack's icon — visible at full strength when
    /// highlighted, dimmed to ~40 % opacity when idle.
    private var iconColor: Color {
        switch pack.id {
        case TechPack.plasticTapping.id:  return Color(red: 0.48, green: 0.72, blue: 1.00)  // sky blue
        case TechPack.farming.id:         return Color(red: 0.38, green: 0.82, blue: 0.46)  // leaf green
        case TechPack.bubble.id:          return Color(red: 0.38, green: 0.88, blue: 0.88)  // teal/cyan
        case TechPack.stars.id:           return Color(red: 1.00, green: 0.82, blue: 0.30)  // gold
        case TechPack.swordBattle.id:     return Color(red: 1.00, green: 0.45, blue: 0.32)  // flame orange
        case TechPack.woodBrush.id:       return Color(red: 0.85, green: 0.62, blue: 0.38)  // warm amber
        case TechPack.fart.id:            return Color(red: 0.72, green: 0.88, blue: 0.30)  // yellow-green
        case TechPack.analogStopwatch.id: return Color(red: 0.72, green: 0.78, blue: 0.90)  // cool silver-blue
        default:                          return Color.accentSoft
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                iconView
                Spacer()
            }

            Spacer(minLength: 0)

            Text(pack.name)
                .font(.headline)
                .foregroundStyle(
                    isCurrent || isHovered
                        ? Color(red: 0.882, green: 0.863, blue: 1.0)
                        : Color(red: 0.745, green: 0.725, blue: 0.941).opacity(0.7)
                )

            Text(pack.blurb)
                .font(.caption)
                .foregroundStyle(Color(red: 0.745, green: 0.725, blue: 0.941).opacity(0.4))
                .lineLimit(3)
        }
        .padding(16)
        .frame(width: 210, height: 140)
        .background(cardBackground)
        .overlay(cardAccentOverlay)
        .overlay(cardBorderOverlay)
        .overlay(alignment: .topTrailing) {
            if isCurrent {
                selectedBadge
                    .padding(10)
            } else if isLocked {
                lockedBadge
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(
            color: Color.black.opacity(isHovered ? 0.28 : 0.08),
            radius: isHovered ? 24 : 8,
            x: 0,
            y: isHovered ? 14 : 5
        )
        .offset(y: isHovered ? -4 : 0)
        .scaleEffect(isHovered ? 1.025 : 0.985)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isCurrent)
    }

    @ViewBuilder
    private var iconView: some View {
        if pack.id == TechPack.bubble.id {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(isCurrent || isHovered ? 1.0 : 0.42))
                    .frame(width: 22, height: 22)
                    .offset(x: -12, y: 3)

                Circle()
                    .fill(iconColor.opacity(isCurrent || isHovered ? 0.96 : 0.40))
                    .frame(width: 16, height: 16)
                    .offset(x: 10, y: 8)

                Circle()
                    .fill(iconColor.opacity(isCurrent || isHovered ? 0.90 : 0.36))
                    .frame(width: 13, height: 13)
                    .offset(x: 4, y: -10)
            }
            .frame(width: 34, height: 34)
        } else {
            Image(systemName: pack.symbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(iconColor.opacity(isCurrent || isHovered ? 1.0 : 0.42))
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                isCurrent
                    ? AnyShapeStyle(LinearGradient(
                        colors: [
                            Color(red: 0.082, green: 0.051, blue: 0.188),
                            Color(red: 0.059, green: 0.031, blue: 0.125)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    : isHovered
                        ? AnyShapeStyle(LinearGradient(
                            colors: [
                                Color(red: 0.074, green: 0.047, blue: 0.157),
                                Color(red: 0.057, green: 0.036, blue: 0.118)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    : AnyShapeStyle(Color(red: 0.059, green: 0.039, blue: 0.125).opacity(0.70))
            )
    }

    private var cardAccentOverlay: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isCurrent
                        ? [
                            Color.white.opacity(0.08),
                            iconColor.opacity(0.06),
                            Color.clear
                        ]
                        : isHovered
                            ? [
                                Color.white.opacity(0.05),
                                iconColor.opacity(0.04),
                                Color.clear
                            ]
                        : [
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(.screen)
    }

    private var cardBorderOverlay: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                isCurrent
                    ? Color(red: 0.608, green: 0.478, blue: 1.0).opacity(0.55)
                    : isHovered
                        ? iconColor.opacity(0.42)
                    : Color.white.opacity(0.07),
                lineWidth: isHovered ? 1.4 : 1
            )
    }

    private var selectedBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(iconColor)
            .shadow(color: iconColor.opacity(0.22), radius: 6, y: 2)
    }

    private var lockedBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.orange.opacity(0.95))
            .padding(8)
            .background(Color.orange.opacity(0.12))
            .clipShape(Circle())
    }
}

// MARK: - Button styles

/// Secondary / ghost button — frosted glass
struct AuroraButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(red: 0.933, green: 0.914, blue: 1.0).opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

/// Primary button — solid purple
struct AuroraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.482, green: 0.353, blue: 0.941),
                        Color(red: 0.353, green: 0.239, blue: 0.784)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color(red: 0.482, green: 0.353, blue: 0.941).opacity(0.45), radius: 14, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}
