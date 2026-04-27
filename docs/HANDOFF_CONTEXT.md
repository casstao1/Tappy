# Tappy Handoff Context

Last updated: 2026-04-27

## Project

Tappy is a macOS keyboard-sound app in `/Users/castao/Desktop/KeyboardSoundApp`.

The current direction is a menu-bar-only Mac app. The old full application window should not open on launch. Users interact through the Tappy menu bar icon, where they can:

- See setup status for Input Monitoring.
- Enable or pause click sounds.
- Select free sound packs.
- Try premium packs through short/demo playback or limited preview behavior, depending on the final product decision.
- Control click sound volume with the menu-bar volume slider.
- Quit the app.

## Current App Shape

Important files:

- `Tappy/TappyApp.swift`: App entry point. It currently uses a no-op `Settings` scene so SwiftUI has a valid scene, but no main window is shown on launch.
- `Tappy/KeyboardSoundController.swift`: Central app state, menu-bar setup, pack selection, premium state, Input Monitoring state, relaunch flow, volume persistence.
- `Tappy/MenuBarView.swift`: Menu-bar popover UI, including status, setup bar, pack list, click-volume slider, sounds toggle, and quit button.
- `Tappy/Services/InputMonitoringPermissionManager.swift`: TCC/Input Monitoring preflight checks, request prompt, System Settings opening/focusing, polling.
- `Tappy/Services/KeyboardMonitor.swift`: Local key monitor plus global CGEvent tap for system-wide typing.
- `Tappy/Services/LowLatencyAudioEngine.swift`: AVAudioEngine-backed low-latency playback. Now supports a persisted output volume.
- `Tappy/Services/SoundLibrary.swift`: Loads bundled packs and demo sounds.
- `Tappy/Support/AppInfo.plist`: `LSUIElement` is `true`, making this a menu-bar/background-style app.
- `Tappy/Support/Tappy.entitlements`: App Sandbox is enabled.

## Current User Requirements

The latest explicit requirements are:

- App should live in the menu bar only.
- There should only be one Tappy app identity, not `Tappy Preview`.
- The app window should not be part of the normal installed workflow.
- Input Monitoring setup should be simple and reliable.
- The app should not automatically open the macOS keystroke permission prompt behind the app.
- Users can click an Input Monitoring/setup button from the menu bar when setup is needed.
- Menu-bar dropdown should include a click-volume dial/slider controlling only Tappy click sound volume.

## Recent Implemented Changes

### Menu-bar-only app

`TappyApp.swift` no longer opens the old `WindowGroup` on launch. It keeps a no-op `Settings` scene only to satisfy SwiftUI's `App` protocol.

`KeyboardSoundController.setupMenuBarItem()` creates an `NSStatusItem` and attaches `MenuBarView` in an `NSPopover`.

`AppInfo.plist` has:

```text
LSUIElement = true
```

This means the app is intended to appear in the menu bar and not as a normal Dock/window app.

### Volume slider

`KeyboardSoundController` has a persisted `clickVolume` value using:

```text
UserDefaults key: Tappy.clickVolume
```

`LowLatencyAudioEngine.setVolume(_:)` clamps volume from `0...1` and applies it to all `AVAudioPlayerNode`s.

`MenuBarView.volumeControl` shows a `Click Volume` slider and percentage. It binds to:

```swift
$controller.clickVolume
```

Last local rebuild succeeded after this change.

### Input Monitoring flow

The current code still contains support for:

- `SetupPhase.needsPermission`
- `SetupPhase.needsRestart`
- `SetupPhase.complete`

The app probes both:

- `CGPreflightListenEventAccess()`
- A real event-tap creation attempt via `KeyboardSoundController.canCreateEventTap()`

This was added because `CGPreflightListenEventAccess()` alone was observed to be stale/flaky.

The current user direction is to avoid auto-triggering the macOS permission dialog on launch because it can appear behind the app. The user accepts requiring the user to click the menu-bar setup button.

## Known Issues / Risks

### Input Monitoring detection remains the riskiest area

Observed user reports before the latest menu-bar-only pivot:

- Setup page sometimes showed even after permission was enabled.
- App sometimes went home even when Input Monitoring was revoked.
- Keystrokes worked inside the app but not outside it.
- Keystroke Receiving prompt appeared behind the app.
- Toggling Input Monitoring sometimes did not update app state until relaunch.

The current direction should simplify this by avoiding the full setup window and keeping setup controls in the menu bar. However, this still needs real clean-install testing through TestFlight.

### `CGRequestListenEventAccess()` behavior is OS-controlled

macOS decides whether and where the Keystroke Receiving dialog appears. The app can request access, but foreground ordering is not fully controllable. Avoid auto-requesting on launch unless the behavior is verified on target macOS versions.

### Dirty working tree

This repo has many uncommitted changes and generated artifacts. Do not assume everything should be committed or pushed.

Current generated/local artifacts include:

- `.buildcheck/`
- `.signedDerivedData/`
- `Tappy.app`
- `premium_demo_uploads/`
- `premium_demo_clips/`

These should generally not be committed unless intentionally added to release artifacts.

## Build / Run Commands

Build debug:

```bash
xcodebuild -project /Users/castao/Desktop/KeyboardSoundApp/Tappy.xcodeproj \
  -scheme Tappy \
  -configuration Debug \
  -derivedDataPath /Users/castao/Desktop/KeyboardSoundApp/.buildcheck \
  build
```

Replace local app bundle and relaunch:

```bash
pkill -x Tappy || true
rm -rf /Users/castao/Desktop/KeyboardSoundApp/Tappy.app
cp -R /Users/castao/Desktop/KeyboardSoundApp/.buildcheck/Build/Products/Debug/Tappy.app \
  /Users/castao/Desktop/KeyboardSoundApp/Tappy.app
open /Users/castao/Desktop/KeyboardSoundApp/Tappy.app
```

Last verified build command succeeded on 2026-04-27 after adding the volume slider.

## Fresh Install / Permission Reset Notes

There is a helper script:

```text
reset-tappy-permissions.command
```

Use caution. macOS TCC resets are bundle-ID based and can be confusing if both `Tappy` and `Tappy Preview` identities exist. The user explicitly wants only `Tappy` now.

When testing first-run behavior, verify:

- Only `Tappy` appears in System Settings > Privacy & Security > Input Monitoring.
- No `Tappy Preview` row remains.
- Starting Tappy with no permission shows the menu-bar setup state.
- Clicking setup opens or requests Input Monitoring in the expected way.
- After enabling Input Monitoring and relaunching if required, the menu status becomes active.
- Typing in another app plays sounds.
- Revoking Input Monitoring causes the menu-bar warning/setup state to return.

## Premium Pack Behavior

The product intent has changed during iteration. Current desired behavior should be reconfirmed before more work:

- Plastic Tapping and Farming are free.
- Other packs are premium.
- User previously wanted locked packs to play demo snippets instead of becoming active system-wide before purchase.
- Demo assets were generated/recorded under bundled `demo/` folders for premium packs.

Relevant paths:

- `Tappy/Resources/BundledSounds/sword-battle/demo/`
- `Tappy/Resources/BundledSounds/bubble/demo/`
- `Tappy/Resources/BundledSounds/analog-stopwatch/demo/`
- `Tappy/Resources/BundledSounds/stars/demo/`
- `Tappy/Resources/BundledSounds/wood-brush/demo/`
- `Tappy/Resources/BundledSounds/fart/demo/`

Check `SoundLibrary.previewBundledDemo(packID:using:)` before changing UI behavior.

## App Store / TestFlight Context

Known App Store readiness work already touched:

- App Sandbox enabled.
- `ITSAppUsesNonExemptEncryption` set to false.
- App icon and screenshots were iterated.
- Mac screenshot dimensions needed to be one of:
  - `1280 x 800`
  - `1440 x 900`
  - `2560 x 1600`
  - `2880 x 1800`

Potential remaining submission tasks:

- Confirm final bundle ID and App Store Connect app record.
- Confirm build number increment before each upload.
- Confirm in-app purchase product IDs and StoreKit configuration are production-ready.
- Confirm privacy policy/support URLs are live.
- Confirm all bundled sounds are licensed and documented.
- Confirm no generated/private review-board files are accidentally shipped.

## Next Recommended Steps

1. Verify the latest menu-bar-only build manually.
2. Confirm the volume slider changes click volume for both local and global keystrokes.
3. Remove or fully disable old window/setup workflows that are no longer part of the product.
4. Clean up `Tappy Preview` references, bundle IDs, scripts, and generated app bundles.
5. Run a clean first-run TCC test with only `com.castao.tappy`.
6. Decide final premium behavior: demo-snippet only vs timed live preview.
7. Build an archive and upload a new TestFlight build only after the first-run flow is stable.

