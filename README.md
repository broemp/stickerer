# Stickerer (iOS)

Native twin of the website. WhatsApp only imports sticker *packs* from native apps, so this app
converts a tweet's video to animated 512x512 WebP stickers and hands a pack to
WhatsApp via the official pasteboard + `whatsapp://stickerPack` mechanism.

    brew install xcodegen
    xcodegen && open Stickerer.xcodeproj

Set your Team under Signing & Capabilities, run on a real iPhone with WhatsApp installed
(the simulator has no WhatsApp).

## Share from X / Twitter
The `StickererShare` extension adds "Stickerer" to the iOS share sheet. Share a tweet and the app opens
(`stickerer://make?url=…`) and starts converting it right away. Both targets need your Team set under
Signing & Capabilities.

## App Store
Screenshots, preview video and the listing text are generated and kept in this repo; see
[docs/APP_STORE.md](docs/APP_STORE.md). Privacy policy: [PRIVACY.md](PRIVACY.md).
