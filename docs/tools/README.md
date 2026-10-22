# Demo recording tool

`record-demo.mjs` records the live OpenRouterList site as a silent 1280×720 demo. It uses only Node built-ins and the Chrome DevTools Protocol; the repository does not need an npm package or `node_modules`.

Requirements:

- Chrome or Chromium
- Node 22 or newer (Node 20 also works with its experimental WebSocket flag)
- ffmpeg for the final H.264 encode; it is not needed for `--frames-only`

From the repository root, record the final video and poster with Node 22+:

```sh
node docs/tools/record-demo.mjs --out docs/media
```

On Node 20, enable the built-in WebSocket implementation:

```sh
node --experimental-websocket docs/tools/record-demo.mjs --out docs/media
```

The recorder looks for Chrome in `$CHROME`, the standard macOS application path, `google-chrome`, then `chromium`. Override that search with `--chrome /path/to/chrome`. Use `--base URL` to record another deployment.

To prove all shots on a machine without ffmpeg:

```sh
node docs/tools/record-demo.mjs --frames-only --out /tmp/openrouterlist-demo-check
```

Frames-only mode writes constant-rate JPEG frames, `poster.png`, and `frames/manifest.json`. The manifest lists each shot's frame range and caption and includes any detected JavaScript page errors. Full mode uses those intermediates to write `demo.mp4` (H.264, yuv420p, silent, fast-start, under 10 MB) and `demo-poster.png`, then removes `frames/`, `frames/manifest.json`, and `poster.png` after a successful encode.

The script launches its own headless Chrome process with a temporary profile and removes only that profile when it exits.
