import { error, json } from '@sveltejs/kit';
import { convertToSticker } from '$lib/server/convert.js';

export async function POST({ request }) {
	const { url, fit } = await request.json();
	let host;
	try {
		host = new URL(url).hostname;
	} catch {
		error(400, 'Bad URL');
	}
	if (host !== 'video.twimg.com') error(400, 'Only Twitter video URLs are allowed.');

	try {
		return json(await convertToSticker(url, fit === 'cover' ? 'cover' : 'contain'));
	} catch (e) {
		error(500, e instanceof Error ? e.message : 'Conversion failed');
	}
}
