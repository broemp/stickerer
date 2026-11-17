/**
 * WhatsApp only treats a WebP as a (animated) sticker when it carries an EXIF chunk with
 * sticker-pack metadata. Without it, sharing / drag-and-drop sends it as a plain static image.
 * This injects that chunk into an existing WebP (animated or not) without re-encoding.
 */

function exifPayload() {
	const json = new TextEncoder().encode(
		JSON.stringify({
			'sticker-pack-id': crypto.randomUUID(),
			'sticker-pack-name': 'Stickerer',
			'sticker-pack-publisher': 'Stickerer',
			emojis: []
		})
	);
	// Minimal little-endian TIFF header + one IFD entry pointing at the JSON (the layout WhatsApp expects).
	const head = new Uint8Array([
		0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00, 0x01, 0x00, 0x41, 0x57, 0x07, 0x00, 0, 0, 0, 0, 0x16,
		0x00, 0x00, 0x00
	]);
	new DataView(head.buffer).setUint32(14, json.length, true);
	const out = new Uint8Array(head.length + json.length);
	out.set(head);
	out.set(json, head.length);
	return out;
}

/** @param {Uint8Array} webp @returns {Uint8Array} */
export function addStickerExif(webp) {
	const dv = new DataView(webp.buffer, webp.byteOffset, webp.byteLength);
	const tag = (o) => String.fromCharCode(...webp.subarray(o, o + 4));
	if (tag(0) !== 'RIFF' || tag(8) !== 'WEBP' || tag(12) !== 'VP8X') return webp; // ffmpeg always writes VP8X for animations

	const exif = exifPayload();
	const pad = exif.length & 1;
	const chunk = new Uint8Array(8 + exif.length + pad);
	chunk.set(new TextEncoder().encode('EXIF'));
	new DataView(chunk.buffer).setUint32(4, exif.length, true);
	chunk.set(exif, 8);

	const out = new Uint8Array(webp.length + chunk.length);
	out.set(webp);
	out.set(chunk, webp.length);
	out[20] |= 0x08; // VP8X flags: EXIF present
	new DataView(out.buffer).setUint32(4, out.length - 8, true);
	return out;
}
