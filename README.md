# Stickerer

Turn a tweet's video or GIF into an animated WhatsApp sticker. Paste a tweet link, pick how the
video should fit the square, and download the 512×512 animated WebP (or drag it into WhatsApp Web,
or use Share on mobile).

**Everything runs in your browser.** There is no backend: the page looks up the tweet through the
[fxtwitter](https://github.com/FixTweet/FxTwitter) API, downloads the video from Twitter's CDN and
converts it locally with [ffmpeg.wasm](https://github.com/ffmpegwasm/ffmpeg.wasm). Nothing is
uploaded to a server of ours, and nothing is stored.

- 512×512 animated WebP, max 10 s
- Automatically lowers fps/quality until the file fits WhatsApp's 500 KB limit
- Fit (letterboxed, transparent padding) or fill (cropped) modes

## Host it

It's a static site (SvelteKit + `adapter-static`), so any static host works. With Docker Compose:

```sh
git clone https://github.com/broemp/stickerer.git
cd stickerer
docker compose up -d
```

Open http://localhost:3000. Change the port with `PORT=8080 docker compose up -d` or a `.env` file.

By default this pulls `ghcr.io/broemp/stickerer:main`. To build from source instead, remove the
`image:` line in `docker-compose.yml` and run `docker compose up -d --build`.

Without Docker: `pnpm install && pnpm build`, then serve the `build/` directory with anything
(make sure `.wasm` is served as `application/wasm`).

## Local development

```sh
pnpm install
pnpm dev
```

The ffmpeg core (~30 MB wasm) is copied from `node_modules` into `static/ffmpeg/` automatically
before `dev` and `build`, and is loaded only when you make your first sticker.

## Limitations

- Conversion happens on your device, so long or large videos are slower on phones.
- Depends on the public fxtwitter API and on Twitter's video CDN allowing cross-origin downloads.
