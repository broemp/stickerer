<script>
	import { base } from '$app/paths';
	import { resolveTweet, convertToSticker } from '$lib/convert.js';

	let link = $state('');
	let fit = $state('contain');
	let loading = $state('');
	let err = $state('');
	let info = $state(null);
	let stickers = $state({}); // media index -> {url,blob,size,fits}
	let note = $state('');

	const canShare = typeof navigator !== 'undefined' && !!navigator.canShare;

	function clear() {
		for (const s of Object.values(stickers)) URL.revokeObjectURL(s.url);
		stickers = {};
	}

	async function go(e) {
		e.preventDefault();
		err = note = '';
		info = null;
		clear();
		loading = 'Looking up tweet…';
		try {
			info = await resolveTweet(link);
			for (const [i, m] of info.media.entries()) {
				const prefix = info.media.length > 1 ? `${i + 1}/${info.media.length} · ` : '';
				const { blob, size, fits } = await convertToSticker(m.url, fit, (t) => (loading = prefix + t));
				stickers[i] = { blob, size, fits, url: URL.createObjectURL(blob) };
			}
		} catch (x) {
			err = x.message;
		} finally {
			loading = '';
		}
	}

	const kb = (n) => `${Math.round(n / 1024)} KB`;
	const file = (s) => new File([s.blob], 'sticker.webp', { type: 'image/webp' });

	function dragstart(e, s) {
		e.dataTransfer.effectAllowed = 'copy';
		e.dataTransfer.items.add(file(s));
	}

	async function share(s) {
		try {
			await navigator.share({ files: [file(s)] });
		} catch (x) {
			if (x.name !== 'AbortError') note = `Share failed: ${x.message}`;
		}
	}
</script>

<main>
	<header>
		<span class="badge" aria-hidden="true">🏷️</span>
		<h1>Tweet <span class="arrow">→</span> <em>sticker</em></h1>
		<p class="sub">Paste a tweet with a video or GIF. Get a WhatsApp sticker. Runs entirely in your browser.</p>
	</header>

	<form onsubmit={go}>
		<input bind:value={link} placeholder="https://x.com/user/status/123…" required />
		<button disabled={!!loading}>{loading || 'Make sticker'}</button>
	</form>

	<div class="seg" role="radiogroup" aria-label="Fit">
		<label><input type="radio" bind:group={fit} value="contain" /><span>Fit · padded</span></label>
		<label><input type="radio" bind:group={fit} value="cover" /><span>Fill · cropped</span></label>
	</div>

	{#if loading}
		<div class="loader" role="status" aria-live="polite">
			<img src="{base}/spinning-cat.gif" alt="" width="120" height="120" draggable="false" />
			<span class="status">{loading}</span>
		</div>
	{/if}

	{#if err}<p class="err">{err}</p>{/if}
	{#if note}<p class="note">{note}</p>{/if}

	{#if info}
		<p class="meta">from <b>@{info.author}</b></p>
		<div class="grid">
			{#each Object.entries(stickers) as [i, s] (i)}
				<div class="card" style="--tilt: {i % 2 ? 1.5 : -1.5}deg">
					<img
						src={s.url}
						alt="sticker"
						width="256"
						height="256"
						draggable="true"
						ondragstart={(e) => dragstart(e, s)}
					/>
					<div class="size" class:bad={!s.fits}>
						{kb(s.size)}{s.fits ? '' : ' — over 500 KB, WhatsApp may reject'}
					</div>
					<div class="btns">
						<a class="btn" href={s.url} download="sticker.webp">Download</a>
						{#if canShare}<button class="ghost" onclick={() => share(s)}>Share</button>{/if}
					</div>
					<small>or drag the sticker into WhatsApp Web</small>
				</div>
			{/each}
		</div>
	{/if}

	<footer>
		<a href="https://github.com/broemp/stickerer" target="_blank" rel="noopener noreferrer">
			Source on GitHub
		</a>
	</footer>
</main>

<style>
	:global(:root) {
		--bg: #0e1411;
		--panel: #17201b;
		--line: #26342c;
		--text: #eef5f0;
		--muted: #8fa398;
		--green: #25d366;
		--ink: #05220f;
		--pink: #ff5fa2;
	}
	:global(body) {
		margin: 0;
		min-height: 100vh;
		font-family: ui-rounded, 'SF Pro Rounded', system-ui, sans-serif;
		color: var(--text);
		background:
			radial-gradient(600px 400px at 85% -5%, #25d36633, transparent 70%),
			radial-gradient(500px 400px at -5% 40%, #ff5fa222, transparent 70%),
			var(--bg);
	}
	main {
		max-width: 620px;
		margin: 0 auto;
		padding: 56px 16px;
	}
	header { margin-bottom: 28px; }
	.badge {
		display: inline-grid;
		place-items: center;
		width: 52px;
		height: 52px;
		font-size: 28px;
		background: #fff;
		border-radius: 16px;
		transform: rotate(-8deg);
		box-shadow: 0 6px 0 var(--green);
		margin-bottom: 18px;
	}
	h1 {
		margin: 0 0 8px;
		font-size: clamp(34px, 7vw, 48px);
		letter-spacing: -0.03em;
		line-height: 1.05;
	}
	h1 .arrow { color: var(--green); }
	h1 em {
		font-style: normal;
		background: var(--pink);
		color: #fff;
		padding: 0 0.2em;
		border-radius: 0.2em;
		display: inline-block;
		transform: rotate(-2deg);
	}
	.sub { color: var(--muted); margin: 0; }

	form { display: flex; gap: 8px; }
	form input {
		flex: 1;
		min-width: 0;
		padding: 14px 18px;
		border-radius: 999px;
		border: 2px solid var(--line);
		background: var(--panel);
		color: inherit;
		font: inherit;
		outline: none;
		transition: border-color 0.15s;
	}
	form input:focus { border-color: var(--green); }

	button, .btn {
		padding: 12px 20px;
		border-radius: 999px;
		border: 0;
		background: var(--green);
		color: var(--ink);
		font: inherit;
		font-weight: 700;
		font-size: 15px;
		cursor: pointer;
		text-decoration: none;
		white-space: nowrap;
		box-shadow: 0 3px 0 #17803f;
		transition: transform 0.1s, box-shadow 0.1s;
	}
	button:hover:not(:disabled), .btn:hover { transform: translateY(-1px); }
	button:active:not(:disabled), .btn:active { transform: translateY(3px); box-shadow: 0 0 0 #17803f; }
	button:disabled { opacity: 0.7; cursor: wait; }
	button.ghost {
		background: transparent;
		color: var(--text);
		box-shadow: inset 0 0 0 2px var(--line);
	}
	button.ghost:active:not(:disabled) { box-shadow: inset 0 0 0 2px var(--line); }

	.seg {
		display: inline-flex;
		margin: 14px 0 4px;
		padding: 4px;
		gap: 4px;
		background: var(--panel);
		border-radius: 999px;
		border: 2px solid var(--line);
		font-size: 14px;
	}
	.seg input { position: absolute; opacity: 0; pointer-events: none; }
	.seg span {
		display: block;
		padding: 6px 14px;
		border-radius: 999px;
		color: var(--muted);
		cursor: pointer;
		transition: background 0.15s, color 0.15s;
	}
	.seg label:has(input:checked) span { background: var(--text); color: var(--bg); font-weight: 600; }
	.seg label:has(input:focus-visible) span { outline: 2px solid var(--green); outline-offset: 2px; }

	.err { color: #ff7a7a; }
	.note { color: var(--green); }
	.meta { color: var(--muted); margin: 28px 0 12px; }
	.meta b { color: var(--text); }

	.grid { display: grid; gap: 20px; }
	.card {
		background: var(--panel);
		border: 2px solid var(--line);
		border-radius: 24px;
		padding: 20px;
		text-align: center;
		transform: rotate(var(--tilt));
		transition: transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1);
		animation: pop 0.35s cubic-bezier(0.2, 0.8, 0.2, 1) both;
	}
	.card:hover { transform: rotate(0deg); }
	@keyframes pop { from { opacity: 0; transform: scale(0.92) rotate(var(--tilt)); } }

	img {
		max-width: 100%;
		height: auto;
		border-radius: 8px;
		cursor: grab;
		/* die-cut sticker outline */
		filter: drop-shadow(2px 0 0 #fff) drop-shadow(-2px 0 0 #fff) drop-shadow(0 2px 0 #fff)
			drop-shadow(0 -2px 0 #fff) drop-shadow(0 8px 10px #0008);
		transition: transform 0.2s;
	}
	img:hover { transform: scale(1.04) rotate(-2deg); }
	img:active { cursor: grabbing; }

	.size { font-size: 13px; color: var(--muted); margin: 16px 0 12px; }
	.size.bad { color: #ffb347; }
	.btns { display: flex; gap: 8px; justify-content: center; flex-wrap: wrap; }
	.loader { display: flex; flex-direction: column; align-items: center; gap: 10px; margin: 28px 0 4px; }
	.loader img { width: 120px; height: 120px; cursor: default; filter: none; border-radius: 0; }
	.loader img:hover { transform: none; }
	.status { color: var(--muted); font-size: 14px; }

	footer { margin-top: 48px; text-align: center; font-size: 13px; }
	footer a { color: var(--muted); text-decoration: none; }
	footer a:hover { color: var(--green); text-decoration: underline; }
	small { display: block; margin-top: 12px; color: var(--muted); opacity: 0.7; }

	@media (prefers-reduced-motion: reduce) {
		.card, img, button, .btn { transition: none; animation: none; }
	}
</style>
