# Tappy App Review Notes

## What the app does
Tappy is a macOS auditory typing feedback utility. It provides local, non-visual confirmation of physical typing activity for users who benefit from hearing key-category cues while they type across macOS.

Tappy is not a text-entry app, keyboard logger, automation tool, analytics product, or novelty soundboard. The shipped interface now describes the feature as auditory typing feedback and exposes neutral feedback packs only.

## Keyboard event handling
Tappy uses macOS Input Monitoring because macOS requires that permission for a sandboxed app to provide system-wide feedback while the user types in other apps.

The app creates a listen-only `CGEventTap` for key down, key up, and modifier state changes. The event tap reads only hardware key codes and modifier flags so it can choose a local feedback cue category such as standard key, space, return, delete, or modifier. It returns every event unchanged and does not read typed characters or text from the event stream.

## Changes in this resubmission
- Repositioned the product and in-app copy around assistive auditory typing feedback.
- Removed novelty/entertainment pack presentation from the shipped picker.
- Removed joke/game-themed bundled pack resources from the submitted app bundle.
- Updated support, privacy, screenshot, and review-note copy to match the feedback purpose.
- Kept the implementation listen-only and local-only.

## What the app does not do
- Tappy does not record or store typed text as user data.
- Tappy does not upload typed content or input data to a remote server.
- Tappy does not sell or share typed content.
- Tappy does not collect typing analytics.
- Tappy does not inject synthetic keyboard events.
- Tappy does not modify, block, replace, or repost keyboard events.
- Tappy does not use Accessibility APIs such as `AXIsProcessTrusted` or `AXUIElement`.
- Tappy does not use `NSEvent.addGlobalMonitorForEvents`.
- Tappy does not use InputMethodKit or install a custom keyboard/input source.

## Premium purchase model
- Free feedback packs: Plastic Tapping, Organic Taps
- Premium feedback packs unlock with one non-consumable purchase
- Product identifier: `com.castao.tappy.unlockall`

## Suggested App Review submission note
Tappy is a macOS auditory typing feedback utility. This resubmission revises the app, support page, privacy page, screenshots, and review notes to present the feature as local assistive auditory feedback rather than an entertainment effect.

Tappy requests macOS Input Monitoring because macOS requires that permission for system-wide typing feedback while the user types in other apps. Tappy creates a listen-only `CGEventTap` and reads only hardware key codes plus modifier flags to select local feedback cue categories. Tappy returns keyboard events unchanged.

Tappy does not read typed characters or text, record typed text, store key activity as user data, transmit typed content, collect typing analytics, inject keyboard input, modify keyboard input, use `NSEvent.addGlobalMonitorForEvents`, use InputMethodKit, or use Accessibility APIs such as `AXIsProcessTrusted` or `AXUIElement`. Premium feedback content is unlocked via a single non-consumable in-app purchase.

Previous appeal ticket: APL444601.
