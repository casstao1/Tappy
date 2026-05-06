# Tappy App Review Notes

## What the app does
Tappy is a macOS keyboard sound utility. It plays local sound effects when the user presses keys and allows switching between curated sound packs.

## Keyboard event handling
Tappy uses a listen-only `CGEventTap` to detect key-down, key-up, and modifier-key events while the user is typing in other apps. This requires the macOS Input Monitoring permission under System Settings > Privacy & Security > Input Monitoring.

Tappy also uses `NSEvent.addLocalMonitorForEvents` for key events delivered directly to Tappy's own menu-bar popover. The local monitor prevents duplicate playback while Tappy is focused.

This follows Apple DTS guidance that inactive keyboard monitoring in a sandboxed Mac App Store app should use `CGEventTap` with Input Monitoring rather than an `NSEvent` global monitor requiring Accessibility trust:
- https://developer.apple.com/forums/thread/707680
- https://developer.apple.com/forums/thread/789896

## What the app does not do
- Tappy does not record or store typed text as user data.
- Tappy does not upload keystrokes to a remote server.
- Tappy does not sell or share typed content.
- Tappy does not inject synthetic keyboard events.
- Tappy does not modify, block, replace, or repost keyboard events.
- Tappy does not use Accessibility APIs such as `AXIsProcessTrusted` or `AXUIElement`.

## Premium purchase model
- Free packs: Plastic Tapping, Farming
- Premium packs unlock with one non-consumable purchase
- Product identifier: `com.castao.tappy.unlockall`

## Suggested App Review submission note
Tappy is a keyboard sound utility for macOS. It uses a listen-only `CGEventTap` with the macOS Input Monitoring permission only to detect keyboard event timing/key codes and play local sound effects. Tappy does not record or store typed text, transmit typed content, inject keyboard input, modify keyboard input, or use Accessibility APIs. This matches Apple DTS guidance for sandboxed Mac App Store apps that need inactive keyboard monitoring: https://developer.apple.com/forums/thread/707680 and https://developer.apple.com/forums/thread/789896. Premium content is unlocked via a single non-consumable in-app purchase.
