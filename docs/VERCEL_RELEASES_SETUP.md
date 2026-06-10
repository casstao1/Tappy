# Tappy Vercel + Manual Notarized Release Setup

This repo is set up so GitHub never needs Apple signing secrets:

- Vercel hosts the static website from `docs/`.
- Your Mac signs and notarizes `Tappy.dmg` locally.
- GitHub Releases hosts only the finished `Tappy.dmg` and checksum.

The website download button points to:

```text
https://github.com/casstao1/Tappy/releases/latest/download/Tappy.dmg
```

That URL works when the latest GitHub Release includes an asset named `Tappy.dmg`.

## 1. Publish the Website on Vercel

1. Push this repo to `https://github.com/casstao1/Tappy`.
2. In Vercel, import the GitHub repo as a new project.
3. Keep the project root at the repository root.
4. Vercel reads `vercel.json` and serves `docs/` as the output directory.

## 2. Keep Signing Secrets Local

Local signing materials live under:

```text
build/certificates/
```

This folder is ignored by git. Do not commit:

- `TappyDeveloperID.key`
- `TappyDeveloperID.p12`
- `github-secrets.env`
- app-specific passwords

## 3. Build a Notarized DMG Locally

Run:

```sh
./scripts/manual-notarized-release.sh
```

The script:

1. Imports the local Developer ID `.p12` into a temporary keychain.
2. Builds and signs `Tappy.app` with Developer ID Application.
3. Creates and signs `Tappy.dmg`.
4. Submits the DMG to Apple notarization.
5. Staples the notarization ticket.
6. Writes a SHA-256 checksum.

Outputs:

```text
build/Tappy.dmg
build/Tappy.dmg.sha256
```

## 4. Upload the Release to GitHub

Create a GitHub Release manually at:

```text
https://github.com/casstao1/Tappy/releases/new
```

Use a tag such as:

```text
v1.0.0
```

Upload both release assets:

- `build/Tappy.dmg`
- `build/Tappy.dmg.sha256`

After publishing, the website download button will fetch the latest release asset automatically.
