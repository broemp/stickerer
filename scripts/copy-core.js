// Copies the ffmpeg.wasm core out of node_modules so it is served from our own origin.
import { cp, mkdir } from 'node:fs/promises';

const from = new URL('../node_modules/@ffmpeg/core/dist/esm/', import.meta.url);
const to = new URL('../static/ffmpeg/', import.meta.url);
await mkdir(to, { recursive: true });
for (const f of ['ffmpeg-core.js', 'ffmpeg-core.wasm']) await cp(new URL(f, from), new URL(f, to));
