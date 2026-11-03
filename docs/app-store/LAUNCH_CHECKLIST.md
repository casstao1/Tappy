# Tappy Launch Checklist

## Product
- [x] Include all eight sound packs in the paid Mac App Store edition
- [x] Remove App Store trials, premium locks, purchases, and restore controls
- [x] Keep the direct-download license behavior behind `TAPPY_DIRECT`

## App Store Connect
- [x] Upload and submit version 1.1.0 (build 54) with manual release (`44d7c164-c6fd-4a54-bc6b-af36c74fec11`)
- [x] Keep `com.castao.tappy.unlockall` on sale while the free/locked binary remains live
- [ ] After approval, remove the IAP from sale without deleting its purchase history
- [ ] Set the app price to `$0.99`, then manually release the all-unlocked binary
- [ ] Verify the public product page charges `$0.99`, advertises no IAP, and downloads the all-unlocked build
- [ ] Add the privacy policy URL
- [ ] Add the support URL
- [ ] Add subtitle, keywords, and category data

## Signing and build
- [x] Confirm valid Apple Development certificate on the machine
- [x] Confirm distribution signing during App Store export
- [x] Archive and upload a release build successfully

## Review readiness
- [x] Review [APP_REVIEW_NOTES.md](/Users/castao/Desktop/Tappy/docs/app-store/APP_REVIEW_NOTES.md)
- [ ] Verify auditory-feedback copy matches Input Monitoring setup and system-wide behavior
- [ ] Confirm App Review notes explain listen-only `CGEventTap`, no typed-text collection, assistive feedback purpose, and no Accessibility API usage
- [x] Verify every sound pack selects directly with no purchase prompt

## Content and legal
- [ ] Confirm final shipped feedback packs
- [ ] Keep source/license records for every shipped pack
- [ ] Recheck any sound that could look franchise-adjacent

## Marketing
- [ ] Finalize App Store screenshots
- [ ] Finalize icon
- [ ] Finalize privacy/support GitHub Pages site
