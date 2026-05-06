# Tappy Launch Checklist

## Product
- [ ] Finalize the App Store submission build behavior
- [ ] Confirm the premium model stays as one-time unlock-all
- [ ] Confirm free packs remain Plastic Tapping and Farming

## App Store Connect
- [ ] Create the app record for bundle ID `com.castao.tappy`
- [ ] Create the non-consumable IAP `com.castao.tappy.unlockall`
- [ ] Set the unlock price to `$4.99`
- [ ] Upload `docs/app-store/in-app-purchase/unlock-all-packs-image.png` as the IAP image so the TestFlight/App Store purchase sheet does not show placeholder artwork
- [ ] Add the privacy policy URL
- [ ] Add the support URL
- [ ] Add subtitle, keywords, and category data

## Signing and build
- [ ] Confirm valid Apple Development certificate on the machine
- [ ] Confirm distribution signing for archive submission
- [ ] Archive a release build successfully in Xcode

## Review readiness
- [ ] Review [APP_REVIEW_NOTES.md](/Users/castao/Desktop/KeyboardSoundApp/docs/app-store/APP_REVIEW_NOTES.md)
- [ ] Verify keyboard-event copy matches Input Monitoring and system-wide behavior
- [ ] Confirm App Review notes explain listen-only `CGEventTap` usage and no Accessibility API usage
- [ ] Verify the premium unlock flow with App Store Connect or local StoreKit testing

## Content and legal
- [ ] Confirm final shipped sound packs
- [ ] Keep source/license records for every shipped pack
- [ ] Recheck any sound that could look franchise-adjacent

## Marketing
- [ ] Finalize App Store screenshots
- [ ] Finalize icon
- [ ] Finalize privacy/support GitHub Pages site
