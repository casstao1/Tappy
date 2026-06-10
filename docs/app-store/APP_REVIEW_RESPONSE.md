# Tappy App Review Response

## Current rejection

Apple rejected Tappy 1.0 (13) under Guideline 2.4.5 on May 7, 2026.

The rejection says the app requests access to Accessibility features on macOS for a non-accessibility purpose, specifically access to keystrokes, and suggests using `NSEvent.addLocalMonitor` for mouse clicks or key presses.

## What changed

This build removes the attempted InputMethodKit/input-source workaround and returns to the implementation used by comparable keyboard sound utilities: a user-approved, listen-only Input Monitoring path.

Tappy uses:

- Input Monitoring permission
- `CGEventTap` configured with `.listenOnly`
- `CGPreflightListenEventAccess`
- `CGRequestListenEventAccess`

Tappy does not use:

- `NSEvent.addGlobalMonitorForEvents`
- Accessibility APIs such as `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions`, or `AXUIElement`
- InputMethodKit
- A custom keyboard/input source

The event tap listens for key down, key up, and modifier state changes and reads only hardware key codes plus modifier flags. It uses that data to choose a local sound category: standard key, space, return, delete, or modifier. It returns events unchanged and does not read typed characters or text from the event stream.

## What the app does not do

- Tappy does not record or store typed text as user data.
- Tappy does not upload keystrokes to a remote server.
- Tappy does not sell or share typed content.
- Tappy does not inject synthetic keyboard events.
- Tappy does not modify, block, replace, or repost keyboard events.
- Tappy does not request Accessibility trust.
- Tappy does not collect typing analytics.

## Recommended App Review reply

Hello App Review,

Thank you for reviewing Tappy. This resubmission is Tappy 1.0 (38), and we have revised the build to use a transparent, listen-only Input Monitoring implementation for the disclosed system-wide keyboard sound feature.

Tappy requests macOS Input Monitoring because macOS requires that permission for keyboard sound feedback while the user types in other apps. The app creates a `CGEventTap` with `.listenOnly` and reads only hardware key codes plus modifier flags to select local sound effects. Tappy returns keyboard events unchanged.

Tappy does not read typed characters or text, record typed text, store keystrokes, transmit typed content, collect typing analytics, sell/share input data, or send input data to a server.

Tappy does not use Accessibility APIs such as `AXIsProcessTrusted`, `AXIsProcessTrustedWithOptions`, or `AXUIElement`. Tappy does not use `NSEvent.addGlobalMonitorForEvents`, does not use InputMethodKit, does not install a custom keyboard/input source, and does not inject, block, modify, replace, or repost keyboard events.

Please re-review this build as a keyboard sound utility that uses user-approved Input Monitoring solely for listen-only local sound playback.
