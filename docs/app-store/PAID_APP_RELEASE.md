# Paid App Release

Tappy 1.1.0 changes the Mac App Store edition to a $0.99 paid app with every bundled sound pack included.

## Binary requirements
- No StoreKit configuration is attached to the shared scheme.
- No StoreKit product is loaded by the App Store target.
- No trial, purchase, locked-pack, or restore UI is visible.
- Every pack is selectable without an entitlement.
- The `TAPPY_DIRECT` build keeps its independent Stripe/license behavior.

## App Store Connect rollout
The currently published free binary still contains premium locks. Do not make the app paid while that binary is live.

1. Upload and submit version 1.1.0 (build 54) with manual release selected. Completed August 19, 2026; submission `44d7c164-c6fd-4a54-bc6b-af36c74fec11` is waiting for review.
2. Keep `com.castao.tappy.unlockall` available while the currently published free/locked binary remains live.
3. After version 1.1.0 is approved, remove the IAP from sale without deleting its purchase history.
4. Set the app price to $0.99 across storefronts, then manually release version 1.1.0 once the paid price is active.
5. Verify the public product page charges $0.99, no longer advertises in-app purchases, and the downloaded build exposes every sound.

Current review-stage storefront state:

- App price: Free (`$0.00` in the United States)
- Legacy IAP: Approved and available in all storefronts
- Version 1.1.0 release mode: Manual

## Verification
Run the full test suite:

```sh
xcodebuild test -project Tappy.xcodeproj -scheme Tappy -destination 'platform=macOS'
```

Also build both compilation paths:

```sh
xcodebuild build -project Tappy.xcodeproj -scheme Tappy -configuration Release -destination 'platform=macOS'
xcodebuild build -project Tappy.xcodeproj -scheme Tappy -configuration Debug -destination 'platform=macOS' SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG TAPPY_DIRECT'
```

Archive and upload without changing the live storefront:

```sh
xcodebuild archive -project Tappy.xcodeproj -scheme Tappy -configuration Release -destination 'generic/platform=macOS' -archivePath /tmp/Tappy-1.1.0-54-AppStore.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath /tmp/Tappy-1.1.0-54-AppStore.xcarchive -exportOptionsPlist docs/app-store/ExportOptions.plist -exportPath /tmp/Tappy-1.1.0-54-AppStore-export -allowProvisioningUpdates
```
