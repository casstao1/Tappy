# Tappy

`Tappy` is a sandboxed macOS Swift app that provides low-latency auditory typing feedback from bundled and user-provided audio cues.

## Download Site

This repo includes a Vercel-ready website in [docs](/Users/castao/Desktop/Tappy/docs). The site downloads the latest notarized macOS DMG from GitHub Releases:

`https://github.com/casstao1/Tappy/releases/latest/download/Tappy.dmg`

See [docs/VERCEL_RELEASES_SETUP.md](/Users/castao/Desktop/Tappy/docs/VERCEL_RELEASES_SETUP.md) for the Vercel + local Developer ID notarization setup. Apple signing secrets stay on your Mac and are not stored in GitHub.

The direct-release build sells the premium ASMR pack unlock through Stripe Checkout. See [docs/STRIPE_CHECKOUT_SETUP.md](/Users/castao/Desktop/Tappy/docs/STRIPE_CHECKOUT_SETUP.md) for the Stripe product, Vercel environment variables, and license-key flow.

## Repo Scope

This public repo is intentionally slimmed down to the shippable app:

- Swift source in [Tappy](/Users/castao/Desktop/KeyboardSoundApp/Tappy)
- Xcode project in [Tappy.xcodeproj](/Users/castao/Desktop/KeyboardSoundApp/Tappy.xcodeproj)
- bundled launch-ready packs in [BundledSounds](/Users/castao/Desktop/KeyboardSoundApp/Tappy/Resources/BundledSounds)
- GitHub Pages / App Store support assets in [docs](/Users/castao/Desktop/KeyboardSoundApp/docs)

The local sound-design pipeline used to cut candidates, build review boards, and iterate on source clips is not tracked in the public repo.

## Open In Xcode

Open [Tappy.xcodeproj](/Users/castao/Desktop/KeyboardSoundApp/Tappy.xcodeproj) in Xcode and set your own team and bundle identifier before archiving for the Mac App Store.

## App Store Metadata

Planned App Store name:

- `Tappy`

Planned App Store subtitle:

- `Auditory typing feedback`

The subtitle is set in App Store Connect, not in the Xcode project.

## Where To Put Your Feedback Cues

Run the app once, then open the feedback cue folder from the app.

The app stores sound files in:

`~/Library/Application Support/<bundle-id>/Sounds/`

When sandboxed, the real location becomes the app container equivalent of that path. The app creates these folders:

- `default`
- `space`
- `return`
- `delete`
- `modifier`

If a category folder is empty, the app falls back to `default`.

## Best Formats

For the tightest response, use short uncompressed files:

- `.wav`
- `.aiff`
- `.caf`

Compressed formats such as `.mp3` and `.m4a` are supported, but uncompressed clips usually feel snappier.
