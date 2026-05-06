# Tappy Handoff Context

Tappy is a sandboxed macOS menu-bar app in `/Users/castao/Desktop/KeyboardSoundApp`.

## Current App Store Review Constraint

Apple rejected version 1.0 (11) under Guideline 2.4.5 because the app requested macOS keystroke access for a non-accessibility feature. Current research found Apple DTS guidance that sandboxed Mac App Store apps can monitor inactive keyboard events with a listen-only `CGEventTap` backed by Input Monitoring, not Accessibility trust.

## Current Keyboard Event Model

- `Tappy/Services/KeyboardMonitor.swift` uses a listen-only `CGEventTap` for key events delivered while other apps are active.
- `Tappy/Services/KeyboardMonitor.swift` also uses `NSEvent.addLocalMonitorForEvents` for key events delivered to Tappy's own menu-bar popover to avoid duplicate sounds.
- `Tappy/Services/InputMonitoringPermissionManager.swift` requests and polls macOS Input Monitoring permission with `CGRequestListenEventAccess` / `CGPreflightListenEventAccess`.
- The app does not post, modify, block, replace, or store keyboard events.
- The app remains sandboxed and does not store, upload, sell, or share typed content.

## Key Files

- `Tappy/KeyboardSoundController.swift`: App state, menu-bar setup, Input Monitoring setup phase, pack selection, premium flow, monitor lifecycle, volume persistence.
- `Tappy/MenuBarView.swift`: Menu-bar popover UI.
- `Tappy/Services/KeyboardMonitor.swift`: Listen-only background event tap, local key event handling, and sound trigger classification.
- `Tappy/Services/InputMonitoringPermissionManager.swift`: Input Monitoring permission handling.
- `Tappy/Services/LowLatencyAudioEngine.swift`: Low-latency playback.
- `Tappy/Services/SoundLibrary.swift`: Sound loading/importing.
- `Tappy/Services/PremiumStore.swift`: StoreKit premium unlock.
- `Tappy/Support/Tappy.entitlements`: Sandboxed app entitlement.

## Review Notes

Use `docs/app-store/APP_REVIEW_NOTES.md` as the source for App Review notes. Keep all marketing, screenshots, privacy, and support copy aligned with system-wide behavior through Input Monitoring, and keep the notes explicit that Tappy does not use Accessibility APIs.
