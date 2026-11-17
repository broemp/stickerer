import { error, json } from '@sveltejs/kit';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { filePath } from '$lib/server/convert.js';

const run = promisify(execFile);

/** macOS: put the .webp *file* on the clipboard so Cmd+V in WhatsApp Web attaches it. */
export async function POST({ request }) {
	const { id } = await request.json();
	if (!/^[a-f0-9]{16}$/.test(id ?? '')) error(400, 'Bad id');
	if (process.platform !== 'darwin') error(501, 'File copy is only supported on macOS.');
	await run('osascript', ['-e', `set the clipboard to (POSIX file "${filePath(id)}")`]);
	return json({ ok: true });
}
