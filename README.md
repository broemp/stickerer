# Stickerer

Turn a tweet's video or GIF into an animated WhatsApp sticker. Paste a tweet link, pick how the
video should fit the square, and download the 512×512 animated WebP (or drag it straight into
WhatsApp Web).

- Converts to 512×512 animated WebP, max 10 s
- Automatically lowers fps/quality until the file fits WhatsApp's 500 KB limit
- `contain` (letterbox, transparent padding) or `cover` (crop) fit modes
- SvelteKit + `adapter-node`; `ffmpeg` and `img2webp` do the encoding

## Run with Docker Compose

```sh
git clone https://github.com/broemp/stickerer.git
cd stickerer
docker compose up -d
```

Open http://localhost:3000.

By default this pulls `ghcr.io/broemp/stickerer:main`. To build from source instead, run
`docker compose up -d --build` after removing the `image:` line in `docker-compose.yml`.

### Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `3000` | Host port to publish |

`PORT` can go in a `.env` file next to `docker-compose.yml`. When serving behind a reverse proxy over
HTTPS, uncomment the `environment:` block in `docker-compose.yml` and set `ORIGIN` to your public URL
(e.g. `https://stickers.example.com`), otherwise SvelteKit rejects POST requests.

## Local development

Requires Node 24, pnpm, `ffmpeg` and `webp` (for `img2webp`) on your `PATH`.

```sh
pnpm install
pnpm dev
```

Production build: `pnpm build && pnpm start`.

## How it works

1. `/api/resolve` looks up the tweet via the fxtwitter API and returns its video variants.
2. `/api/convert` downloads the video and encodes it with ffmpeg + `img2webp`, retrying with cheaper
   settings until it is under 500 KB.
3. `/api/file/[id]` serves the result; `/api/copy` supports copying the file to the clipboard.

Results are cached in the system temp directory (`/tmp/tweet-sticker`).
