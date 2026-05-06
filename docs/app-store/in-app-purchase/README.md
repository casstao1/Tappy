# In-App Purchase Artwork

The TestFlight purchase confirmation sheet gets its product artwork from App Store Connect metadata, not from Tappy's SwiftUI purchase code.

Upload `unlock-all-packs-image.png` to the `Unlock All Packs` in-app purchase image field in App Store Connect:

1. Open App Store Connect.
2. Select Tappy.
3. Go to Monetization -> In-App Purchases.
4. Open `Unlock All Packs` (`com.castao.tappy.unlockall`).
5. Upload `unlock-all-packs-image.png` to the App Store image/image field.
6. Save and submit the IAP metadata for review if App Store Connect requires it.

Apple's requirements for this image are PNG or JPG, 1024 x 1024 pixels, 72 dpi, RGB, flattened, and no rounded corners.
