# Tappy

`Tappy` is a sandboxed macOS Swift app that plays low-latency keyboard click sounds from bundled and user-provided audio files.

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

- `AMR & Meme Keyboard Sounds`

The subtitle is set in App Store Connect, not in the Xcode project.

## Where To Put Your Sounds

Run the app once, then click `Reveal Sounds Folder`.

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
