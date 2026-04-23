# StoreKit Testing Setup

Apple’s current guidance is to create the local `.storekit` configuration file in Xcode’s editor rather than hand-authoring the file.

Reference:
- [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)

## Create the local StoreKit config
1. In Xcode, create a new file.
2. Choose `StoreKit Configuration File`.
3. Save it into this project, for example as `Tappy/TappyLocal.storekit`.
4. Add one non-consumable product:
   - Reference Name: `Unlock All Packs`
   - Product ID: `com.castao.tappy.unlockall`
   - Price: `$4.99`

## Enable it for local runs
1. Edit the `Tappy` scheme.
2. Open the `Run` action.
3. Under `Options`, select the `.storekit` file as the active StoreKit configuration.

## What to verify
- Locked packs stay preview-only before purchase
- `Unlock All` succeeds locally
- `Restore Purchases` restores the entitlement
- Premium packs become selectable after unlock

