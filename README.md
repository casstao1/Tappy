# Tappy

`Tappy` is a sandboxed macOS Swift app that plays low-latency keyboard click sounds from user-provided audio files.

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
