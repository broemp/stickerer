# App Store release

Everything for the App Store listing lives in the repo, split in two:

| What | Where | Command |
|---|---|---|
| Screenshots + preview video | `AppStoreScreenshots/` | `AppStoreScreenshots/make-screenshots.sh` |
| Listing text, URLs, review notes | `fastlane/metadata/` | `cd fastlane && fastlane metadata` |

## Screenshots
`make-screenshots.sh` builds a Debug app, boots clean simulators (iPhone 6.9", iPad 13"), launches the app with
`-screenshot "<scene>"` and grabs the screen. The app fills itself with offline demo stickers
(`make-demo-stickers.sh` makes them from `spinning-cat.gif`), so no network, account or WhatsApp is needed.
Then fastlane frameit adds bezel, background and caption, and exports exact App Store sizes.

    brew install xcodegen imagemagick ffmpeg fastlane
    AppStoreScreenshots/make-screenshots.sh                # everything
    AppStoreScreenshots/make-screenshots.sh --no-video     # stills only
    DEVICES=iphone ./make-screenshots.sh 02-converting     # one shot

Output: `AppStoreScreenshots/appstore-frames/output/en-US/{iphone-6.9,iphone-6.3,ipad-13}/` and
`AppStoreScreenshots/previews/en-US/preview-{iphone,ipad}.mp4`. Screens, captions and the video tour are in
`AppStoreScreenshots/screenshots.conf`. The scene code is `Stickerer/ScreenshotMode.swift` (`#if DEBUG` only).

`05-share` (the iOS share sheet) can't be automated: take it by hand on a simulator or device, save it as
`appstore-frames/fastlane/screenshots/en-US/05-share.png` and re-run with `--no-build --no-shots`.

## App Store Connect: first-time setup
1. **Create the app record**: `cd fastlane && FASTLANE_USER=<apple id> fastlane create_app`, or by hand
   (Apps → + → New App, bundle ID `me.broe.stickerer`, SKU `me.broe.stickerer`). The name "Stickerer" must be
   available; if not, change `fastlane/metadata/en-US/name.txt` and the display name in `project.yml`.
   The share extension's ID `me.broe.stickerer.share` is created automatically when you archive.
2. **Upload listing text**: `fastlane metadata` (validates field lengths first with `fastlane check`).
3. **Upload screenshots**: `fastlane screenshots` (after `make-screenshots.sh`). The preview videos have to be
   added in the web UI (deliver can't upload them): iPhone 6.9" and iPad 13" slots.
4. **Build**: set the Team in Xcode, Product → Archive, Distribute → App Store Connect. `MARKETING_VERSION` and
   `CURRENT_PROJECT_VERSION` are in `project.yml`.
5. Fill in what has to be done in the web UI:
   - **Privacy policy URL**: `PRIVACY.md` must be pushed to `main` first (the URL in `privacy_url.txt` points at it).
   - **App Privacy**: recommended answer is **Data Not Collected**. The only third party is the tweet lookup
     (`api.fxtwitter.com`, receives the tweet ID and the IP address, nothing else, not linked to the user). If you
     want to be stricter, declare it. No tracking.
   - **Age rating**: answer the questionnaire. The app fetches arbitrary public media chosen by the user, so
     answer the "user-generated / unrestricted content" questions honestly rather than all "None".
   - **Export compliance**: already answered by `ITSAppUsesNonExemptEncryption = NO` (HTTPS only).
   - **Pricing & availability**, **Content rights** (the app handles third-party content the user picks; answer
     accordingly), **App Review contact** (name, phone, email) and the **test link** in
     `fastlane/metadata/review_information/notes.txt` (search for TODO).
   - Choose the build, then Submit for Review.

## Review risks to be aware of
- **Third-party content / trademarks.** The app downloads other people's videos and mentions WhatsApp and X. The
  description carries a non-affiliation line, and name, subtitle and keywords deliberately don't contain
  "WhatsApp" or "Twitter". Reviewers may still ask about content rights (guideline 5.2).
- **WhatsApp is not on the review device.** The "Add to WhatsApp" button is disabled without it; the review notes
  explain that. Consider mentioning it in a screen recording if review pushes back.
- **Minimum functionality (4.2).** The app is small; the share extension, library and split mode are the answer.
