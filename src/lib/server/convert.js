import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const run = promisify(execFile);

export const OUT_DIR = join(tmpdir(), 'tweet-sticker');
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

export function idFor(url, fit) {
	return createHash('sha1').update(`${url}|${fit}`).digest('hex').slice(0, 16);
}

export function filePath(id) {
	return join(OUT_DIR, `${id}.webp`);
}

/** Downloads the video and converts it to a 512x512 animated WebP. */
export async function convertToSticker(videoUrl, fit = 'contain') {
	await mkdir(OUT_DIR, { recursive: true });
	const id = idFor(videoUrl, fit);
	const out = filePath(id);

	try {
		const s = await stat(out);
		return { id, size: s.size, fits: s.size <= MAX_BYTES };
	} catch {}

	const work = await mkdtemp(join(tmpdir(), 'tweet-sticker-work-'));
	try {
		const res = await fetch(videoUrl);
		if (!res.ok) throw new Error(`Video download failed (${res.status})`);
		const src = join(work, 'in.mp4');
		await writeFile(src, Buffer.from(await res.arrayBuffer()));

		const scale =
			fit === 'cover'
				? 'scale=512:512:force_original_aspect_ratio=increase,crop=512:512'
				: 'scale=512:512:force_original_aspect_ratio=decrease,pad=512:512:(ow-iw)/2:(oh-ih)/2:color=black@0';

		let size = Infinity;
		for (const { fps, q } of ATTEMPTS) {
			const frames = join(work, 'frames');
			await rm(frames, { recursive: true, force: true });
			await mkdir(frames);
			await run('ffmpeg', [
				'-y', '-v', 'error', '-i', src, '-t', String(MAX_SECONDS),
				'-vf', `fps=${fps},format=rgba,${scale}`,
				join(frames, '%04d.png')
			]);
			const files = (await readdir(frames)).sort().map((f) => join(frames, f));
			if (!files.length) throw new Error('No frames decoded');
			await run('img2webp', [
				'-loop', '0', '-d', String(Math.round(1000 / fps)),
				'-lossy', '-q', String(q), '-m', '4',
				...files, '-o', out
			]);
			size = (await stat(out)).size;
			if (size <= MAX_BYTES) break;
		}
		return { id, size, fits: size <= MAX_BYTES };
	} finally {
		await rm(work, { recursive: true, force: true });
	}
}
