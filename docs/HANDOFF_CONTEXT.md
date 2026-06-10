# Tappy Handoff Context

Tappy is a sandboxed macOS menu-bar app in `/Users/castao/Desktop/KeyboardSoundApp`.

## Current App Store Review Constraint

Apple rejected prior builds under Guideline 2.4.5(v) because the app requested Input Monitoring for keyboard audio. Apple later clarified that the concern was the scope of Input Monitoring itself. The current resubmission strategy is to present Tappy as an assistive auditory typing feedback utility with narrow, transparent Input Monitoring behavior and explicit reviewer/user-facing privacy copy.

## Current Keyboard Event Model

- `Tappy/Services/KeyboardMonitor.swift` creates a listen-only `CGEventTap` for system-wide key down, key up, and modifier changes.
- The event tap reads hardware key codes and modifier flags only; it does not read typed characters or text from the global event stream.
- `Tappy/Services/InputMonitoringPermissionManager.swift` handles the Input Monitoring prompt, Settings deep link, and TCC polling.
- The app does not post, modify, block, replace, or store keyboard events.
- The app remains sandboxed and does not store, upload, sell, or share typed content.

## Key Files

- `Tappy/KeyboardSoundController.swift`: App state, menu-bar setup, Input Monitoring setup phase, pack selection, premium flow, monitor lifecycle, volume persistence.
- `Tappy/MenuBarView.swift`: Menu-bar popover UI.
- `Tappy/Services/KeyboardMonitor.swift`: Listen-only event tap and local app key handling.
- `Tappy/Services/InputMonitoringPermissionManager.swift`: Input Monitoring permission prompt, Settings navigation, and polling.
- `Tappy/Services/LowLatencyAudioEngine.swift`: Low-latency playback.
- `Tappy/Services/SoundLibrary.swift`: Sound loading/importing.
- `Tappy/Services/PremiumStore.swift`: StoreKit premium unlock.
- `Tappy/Support/Tappy.entitlements`: Sandboxed app entitlement.

## Review Notes

Use `docs/app-store/APP_REVIEW_NOTES.md` as the source for App Review notes. Keep all marketing, screenshots, privacy, and support copy aligned with the assistive auditory feedback purpose, and keep the notes explicit that Tappy uses a listen-only event tap, does not read text, and does not use Accessibility APIs.
