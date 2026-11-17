import { error } from '@sveltejs/kit';
import { readFile } from 'node:fs/promises';
import { filePath } from '$lib/server/convert.js';

export async function GET({ params }) {
	if (!/^[a-f0-9]{16}$/.test(params.id)) error(400, 'Bad id');
	try {
		const buf = await readFile(filePath(params.id));
		return new Response(buf, {
			headers: {
				'Content-Type': 'image/webp',
				'Content-Disposition': 'inline; filename="sticker.webp"',
				'Cache-Control': 'no-store'
			}
		});
	} catch {
		error(404, 'Not found');
	}
}
