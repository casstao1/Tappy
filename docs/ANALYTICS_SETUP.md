# Optional App Store usage analytics

Tappy can send optional app interaction events to PostHog. Sharing is off by default and can be turned off in the menu. Tappy does not send typed text, individual key events, or error messages. A random installation identifier links opted-in events; opting out deletes it locally and cancels pending requests. Previously received events remain in PostHog according to its retention and deletion settings.

## Configure a release

The Xcode project contains Tappy's US PostHog host and public, write-only project token. Do not use a personal API key in the app. PostHog's project setting to discard client IP data is enabled; the service still receives the network connection. Review PostHog's privacy and retention settings before release, publish the updated privacy policy, and accurately complete the App Store privacy disclosures. Existing installations do not send these events until the updated build is released and users opt in.

## Reading the results

Use `analytics_enabled`, `app_launched`, `setup_changed` (filter `setup=complete`), and `pack_selected` to understand usage after opt-in. Break down sound selections by `pack_id` and compare unique installations as well as total selections. For locked packs, `demo_played` measures sample plays, and `purchase_requested` and `purchase_finished` show the path toward an in-app purchase. Restore actions use `restore_requested` and `restore_finished`. The old typing-preview and upgrade-prompt events may remain in historical data, but the current interface no longer offers that preview.

The `access` property of `purchase_finished` and `restore_finished` is `unlocked` or `not_unlocked`. It reports the resulting access state. For `purchase_finished`, `result` also reports `success`, `pending`, `cancelled`, `failed`, or `unavailable`; these app events are not a substitute for the App Store's sales records. StoreKit handles purchases and restores. Use App Store Connect for storefront acquisition and completed purchase figures. The previously created PostHog sound-interest report is a starting point; direct-download checkout and license funnel events do not represent this App Store purchase flow and must be replaced with the App Store events above.

Reports cover only people who opt in and successfully send events; they cannot reconstruct behavior from previous downloads. Events are sent on a best-effort basis without an offline queue or retry, so reports can miss events and may see them out of order. Pack selection indicates interest, not necessarily whether someone likes a sound. Voluntary feedback or user conversations can help explain why they chose it.
