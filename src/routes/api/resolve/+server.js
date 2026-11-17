import { error, json } from '@sveltejs/kit';

const TWEET_RE = /(?:twitter|x|fxtwitter|vxtwitter|fixupx|fixvx)\.com\/(?:[^/]+)\/status(?:es)?\/(\d+)/i;

export async function POST({ request }) {
	const { url } = await request.json();
	const m = TWEET_RE.exec(String(url ?? ''));
	if (!m) error(400, 'That does not look like a tweet link.');

	const res = await fetch(`https://api.fxtwitter.com/status/${m[1]}`, {
		headers: { 'User-Agent': 'tweet-sticker-local' }
	});
	if (!res.ok) error(502, `Tweet lookup failed (${res.status}).`);
	const data = await res.json();

	const media = (data.tweet?.media?.all ?? [])
		.filter((x) => x.type === 'video' || x.type === 'gif')
		.map((x) => ({
			type: x.type,
			url: x.url,
			thumbnail: x.thumbnail_url,
			width: x.width,
			height: x.height,
			duration: x.duration
		}));
	if (!media.length) error(404, 'No video or GIF found in that tweet.');

	return json({ author: data.tweet.author?.screen_name, text: data.tweet.text, media });
}
