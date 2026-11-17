import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [sveltekit()],
	// ffmpeg.wasm spawns its own worker via import.meta.url; pre-bundling breaks that.
	optimizeDeps: { exclude: ['@ffmpeg/ffmpeg', '@ffmpeg/util'] }
});
