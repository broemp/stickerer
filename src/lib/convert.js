import { FFmpeg } from '@ffmpeg/ffmpeg';
import { toBlobURL } from '@ffmpeg/util';

const MAX_BYTES = 500 * 1024; // WhatsApp animated sticker limit
const MAX_SECONDS = 10;

// Progressively cheaper settings until the file fits under 500 KB.
const ATTEMPTS = [
	{ fps: 15, q: 70 },
	{ fps: 15, q: 50 },
	{ fps: 12, q: 40 },
	{ fps: 10, q: 30 },
	{ fps: 8, q: 20 }
];

const TWEET_RE =
	/(?:twitter|x|fxtwitter|vxtwitter|fixupx|fixvx)\.com\/(?:[^/]+)\/status(?:es)?\/(\d+)/i;

/** Looks up a tweet's videos/GIFs through the (CORS-enabled) fxtwitter API. */
export async function resolveTweet(url) {
	const m = TWEET_RE.exec(String(url ?? ''));
	if (!m) throw new Error('That does not look like a tweet link.');

	const res = await fetch(`https://api.fxtwitter.com/status/${m[1]}`);
	if (!res.ok) throw new Error(`Tweet lookup failed (${res.status}).`);
	const data = await res.json();

	const media = (data.tweet?.media?.all ?? [])
		.filter((x) => x.type === 'video' || x.type === 'gif')
		.map((x) => ({ type: x.type, url: x.url, thumbnail: x.thumbnail_url, duration: x.duration }));
	if (!media.length) throw new Error('No video or GIF found in that tweet.');

	return { author: data.tweet.author?.screen_name, text: data.tweet.text, media };
}

/**
 * Downloads the video. Safari can reuse a cached non-CORS response (e.g. from a previous
 * <video>/<img> load of the same URL) and then fail the CORS check, so bypass the HTTP cache and
 * retry once with a cache-busting query before giving up.
 */
async function download(url) {
	const opts = { cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer', mode: 'cors' };
	let lastErr;
	for (const u of [url, `${url}${url.includes('?') ? '&' : '?'}_=${Date.now()}`]) {
		try {
			const res = await fetch(u, opts);
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			return new Uint8Array(await res.arrayBuffer());
		} catch (e) {
			lastErr = e;
		}
	}
	throw new Error(`Video download failed: ${lastErr?.message ?? lastErr}`);
}

let ffmpegPromise;

/** Loads ffmpeg.wasm once (single-threaded core: no special COOP/COEP headers needed). */
function getFFmpeg() {
	ffmpegPromise ??= (async () => {
		const ff = new FFmpeg();
		const base = `${import.meta.env.BASE_URL.replace(/\/$/, '')}/ffmpeg`;
		await ff.load({
			coreURL: await toBlobURL(`${base}/ffmpeg-core.js`, 'text/javascript'),
			wasmURL: await toBlobURL(`${base}/ffmpeg-core.wasm`, 'application/wasm')
		});
		return ff;
	})();
	ffmpegPromise.catch(() => (ffmpegPromise = undefined));
	return ffmpegPromise;
}

/**
 * Downloads the video and converts it to a 512x512 animated WebP, entirely in the browser.
 * @returns {Promise<{blob: Blob, size: number, fits: boolean}>}
 */
export async function convertToSticker(videoUrl, fit = 'contain', onStatus = () => {}) {
	onStatus('Loading converter…');
	const ff = await getFFmpeg();

	onStatus('Downloading video…');
	const input = await download(videoUrl);
	await ff.writeFile('in.mp4', input);

	const scale =
		fit === 'cover'
			? 'scale=512:512:force_original_aspect_ratio=increase,crop=512:512'
			: 'scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2:color=black@0';

	const onProgress = ({ progress }) => {
		if (progress > 0 && progress <= 1) onStatus(`Encoding… ${Math.round(progress * 100)}%`);
	};
	ff.on('progress', onProgress);

	try {
		let data;
		for (const [i, { fps, q }] of ATTEMPTS.entries()) {
			onStatus(i ? `Too big, retrying smaller (${i + 1}/${ATTEMPTS.length})…` : 'Encoding…');
			const code = await ff.exec([
				'-y', '-i', 'in.mp4', '-an', '-t', String(MAX_SECONDS),
				'-vf', `fps=${fps},format=rgba,${scale}`,
				'-c:v', 'libwebp_anim', '-lossless', '0', '-q:v', String(q),
				'-compression_level', '4', '-loop', '0',
				'out.webp'
			]);
			if (code !== 0) throw new Error('Conversion failed.');
			data = await ff.readFile('out.webp');
			if (data.byteLength <= MAX_BYTES) break;
		}
		const blob = new Blob([data], { type: 'image/webp' });
		return { blob, size: blob.size, fits: blob.size <= MAX_BYTES };
	} finally {
		ff.off('progress', onProgress);
		await ff.deleteFile('in.mp4').catch(() => {});
		await ff.deleteFile('out.webp').catch(() => {});
	}
}
