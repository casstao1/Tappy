# Tappy App Review Notes

## What the app does
Tappy is a paid macOS auditory typing feedback utility. Every bundled sound pack is included in the purchase price; this version contains no in-app purchases, subscriptions, trials, locked content, or Restore Purchases control.

Tappy provides local, non-visual confirmation of physical typing activity for users who benefit from hearing key-category cues while they type across macOS. It is not a text-entry app, keyboard logger, automation tool, analytics product, or custom input source.

## Changes in this update
- Changed Tappy to a $0.99 paid app with all eight sound packs included.
- Removed the App Store trial, premium locks, purchase prompts, and Restore Purchases control.
- Made every sound pack immediately selectable for both new customers and existing users updating from an earlier version.
- Removed StoreKit product loading and purchase code from the Mac App Store target.
- Kept the direct-download Stripe implementation isolated behind the `TAPPY_DIRECT` compilation condition and out of the App Store binary.

## Keyboard event handling
Tappy uses macOS Input Monitoring because macOS requires that permission for a sandboxed app to provide system-wide feedback while the user types in other apps.

The app creates a listen-only `CGEventTap` for key down, key up, and modifier state changes. The event tap reads only hardware key codes and modifier flags so it can choose a local feedback cue category such as standard key, space, return, delete, or modifier. It returns every event unchanged and does not read typed characters or text from the event stream.

## What the app does not do
- Tappy does not record or store typed text as user data.
- Tappy does not upload typed content or input data to a remote server.
- Tappy does not sell or share typed content.
- Tappy does not collect typing analytics.
- Tappy does not inject, modify, block, replace, or repost keyboard events.
- Tappy does not use Accessibility APIs such as `AXIsProcessTrusted` or `AXUIElement`.
- Tappy does not use `NSEvent.addGlobalMonitorForEvents`.
- Tappy does not use InputMethodKit or install a custom keyboard/input source.

## How to test
1. Launch Tappy and complete the Input Monitoring instructions.
2. Enable Tappy under System Settings > Privacy & Security > Input Monitoring if requested.
3. Click the keyboard icon in the macOS menu bar.
4. Select any of the eight sound packs. Every pack is immediately available with no purchase or account step.
5. Type in another app and verify that local auditory feedback matches the selected pack.

## Suggested submission note
Tappy is now a $0.99 paid macOS app with all eight sound packs included. This update removes all in-app purchases, trials, premium locks, purchase prompts, and restore controls. Existing users who update also receive every sound pack automatically.

Tappy requests macOS Input Monitoring because macOS requires that permission for system-wide typing feedback. It creates a listen-only `CGEventTap`, reads only hardware key codes and modifier flags to select local sound categories, and returns keyboard events unchanged. Tappy never reads typed characters or text, records typed text, transmits typed content, collects typing analytics, injects or modifies keyboard input, uses `NSEvent.addGlobalMonitorForEvents`, uses InputMethodKit, or uses Accessibility APIs such as `AXIsProcessTrusted` or `AXUIElement`.

Previous appeal ticket: APL444601.
