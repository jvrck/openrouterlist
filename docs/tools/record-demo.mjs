#!/usr/bin/env node

import { spawn } from 'node:child_process';
import { access, copyFile, mkdir, mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const FPS = 15;
const WIDTH = 1280;
const HEIGHT = 720;
const SHOTS = [
  [5, 'Every OpenRouter model, priced per 1M tokens, updated twice a day'],
  [6, 'Search as you type'],
  [7, 'Filter by capability, context, price and modality'],
  [8, 'Compare up to four models side by side'],
  [7, 'Estimate the cost of your workload'],
  [7, 'Card View on phones, with live search'],
  [5, 'Every model has its own page'],
  [5, 'Static X vs Y pricing pages'],
  [4, 'Price changes, also as an Atom feed'],
  [3, 'openrouterlist.jvrck.com · free and open source'],
];

if (typeof WebSocket === 'undefined') {
  console.error('WebSocket is not available. On Node 20, rerun with: node --experimental-websocket docs/tools/record-demo.mjs ...');
  process.exit(1);
}

function usage(exitCode = 0) {
  const out = exitCode ? console.error : console.log;
  out(`Usage: node docs/tools/record-demo.mjs [options]

Options:
  --out DIR          Output directory (default: docs/media)
  --base URL         Site origin (default: https://openrouterlist.jvrck.com)
  --chrome PATH      Chrome/Chromium executable (also accepts $CHROME)
  --frames-only      Write frames, poster.png and manifest.json; skip ffmpeg
  --help             Show this help`);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const args = { out: 'docs/media', base: 'https://openrouterlist.jvrck.com', chrome: process.env.CHROME || '', framesOnly: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--frames-only') args.framesOnly = true;
    else if (arg === '--help' || arg === '-h') usage();
    else if (arg === '--out' || arg === '--base' || arg === '--chrome') {
      if (!argv[i + 1]) usage(2);
      args[arg.slice(2).replace('frames-only', 'framesOnly')] = argv[++i];
    } else {
      console.error(`Unknown option: ${arg}`);
      usage(2);
    }
  }
  args.out = resolve(args.out);
  args.base = args.base.replace(/\/$/, '');
  return args;
}

const sleep = ms => new Promise(resolvePromise => setTimeout(resolvePromise, ms));

async function exists(path) {
  try { await access(path); return true; } catch { return false; }
}

async function findChrome(explicit) {
  const candidates = [
    explicit,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    'google-chrome',
    'chromium',
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (candidate.includes('/') && await exists(candidate)) return candidate;
    if (!candidate.includes('/')) {
      const child = spawn('sh', ['-c', 'command -v "$1"', 'sh', candidate], { stdio: ['ignore', 'pipe', 'ignore'] });
      let output = '';
      child.stdout.on('data', chunk => { output += chunk; });
      const code = await new Promise(resolvePromise => child.on('close', resolvePromise));
      if (code === 0 && output.trim()) return output.trim();
    }
  }
  throw new Error('Chrome was not found. Pass --chrome PATH or set $CHROME.');
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0 OpenRouterList demo recorder' } });
  if (!response.ok) throw new Error(`GET ${url} returned ${response.status}`);
  return response.json();
}

async function fetchText(url) {
  const response = await fetch(url, { headers: { 'user-agent': 'Mozilla/5.0 OpenRouterList demo recorder' } });
  if (!response.ok) throw new Error(`GET ${url} returned ${response.status}`);
  return response.text();
}

class Cdp {
  constructor(url) {
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    this.ws = new WebSocket(url);
  }

  async open() {
    await new Promise((resolvePromise, reject) => {
      this.ws.addEventListener('open', resolvePromise, { once: true });
      this.ws.addEventListener('error', () => reject(new Error('Could not connect to Chrome DevTools')), { once: true });
    });
    this.ws.addEventListener('message', event => {
      const message = JSON.parse(String(event.data));
      if (message.id) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(message.error.message));
        else pending.resolve(message.result || {});
        return;
      }
      for (const listener of this.listeners.get(message.method) || []) listener(message.params || {});
    });
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolvePromise, reject) => {
      this.pending.set(id, { resolve: resolvePromise, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) || [];
    listeners.push(listener);
    this.listeners.set(method, listeners);
  }

  close() { this.ws.close(); }
}

async function startChrome(executable, profile) {
  const chrome = spawn(executable, [
    '--headless=new',
    '--disable-gpu',
    '--hide-scrollbars',
    '--no-first-run',
    '--no-default-browser-check',
    '--remote-debugging-address=127.0.0.1',
    '--remote-debugging-port=0',
    `--user-data-dir=${profile}`,
    'about:blank',
  ], { stdio: 'ignore' });
  const portFile = join(profile, 'DevToolsActivePort');
  for (let tries = 0; tries < 150; tries += 1) {
    if (chrome.exitCode !== null) throw new Error(`Chrome exited early with status ${chrome.exitCode}`);
    try {
      const [port] = (await readFile(portFile, 'utf8')).trim().split('\n');
      const response = await fetch(`http://127.0.0.1:${port}/json/list`);
      const targets = await response.json();
      const page = targets.find(target => target.type === 'page');
      if (page) return { chrome, debuggerUrl: page.webSocketDebuggerUrl };
    } catch { /* Chrome is still starting. */ }
    await sleep(100);
  }
  chrome.kill('SIGTERM');
  throw new Error('Timed out waiting for Chrome DevTools');
}

function captionScript(caption) {
  return `(() => {
    let overlay = document.getElementById('orl-demo-caption');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'orl-demo-caption';
      document.documentElement.appendChild(overlay);
    }
    overlay.textContent = ${JSON.stringify(caption)};
    Object.assign(overlay.style, {
      position: 'fixed', left: '50%', bottom: '20px', transform: 'translateX(-50%)',
      zIndex: '2147483647', color: '#fff', background: 'rgba(10, 15, 25, .82)',
      border: '1px solid rgba(255,255,255,.18)', borderRadius: '10px',
      boxSizing: 'border-box', padding: '11px 22px', maxWidth: '1120px',
      font: '600 28px/1.25 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      textAlign: 'center', boxShadow: '0 4px 18px rgba(0,0,0,.3)', pointerEvents: 'none'
    });
  })()`;
}

function htmlDataUrl(html) {
  return `data:text/html;charset=utf-8,${encodeURIComponent(html)}`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const framesDir = join(args.out, 'frames');
  if (await exists(framesDir)) throw new Error(`${framesDir} already exists; choose an empty --out directory`);
  await mkdir(framesDir, { recursive: true });

  const chromePath = await findChrome(args.chrome);
  const profile = await mkdtemp(join(process.env.TMPDIR || tmpdir(), 'openrouterlist-demo-'));
  let chrome;
  let cdp;
  const pageErrors = [];
  try {
    const launched = await startChrome(chromePath, profile);
    chrome = launched.chrome;
    cdp = new Cdp(launched.debuggerUrl);
    await cdp.open();
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    cdp.on('Runtime.exceptionThrown', event => pageErrors.push(`exception: ${event.exceptionDetails?.text || 'unknown'}`));
    cdp.on('Runtime.consoleAPICalled', event => {
      if (event.type === 'error' || event.type === 'assert') pageErrors.push(`console.${event.type}: ${event.args?.map(arg => arg.value || arg.description || '').join(' ')}`);
    });
    cdp.on('Log.entryAdded', event => {
      const entry = event.entry || {};
      if (entry.level === 'error' && entry.source !== 'network') pageErrors.push(`${entry.source || 'log'}: ${entry.text || 'unknown error'}`);
    });

    const pairs = await fetchJson(`${args.base}/compare/pairs.json`);
    if (!Array.isArray(pairs) || !pairs[0]?.a || !pairs[0]?.b || !pairs[0]?.slug) throw new Error('The live compare pair feed has no usable first pair');
    const firstPair = pairs[0];
    const uniquePairModels = [];
    for (const pair of pairs) {
      for (const id of [pair.a, pair.b]) if (id && !uniquePairModels.includes(id)) uniquePairModels.push(id);
      if (uniquePairModels.length >= 3) break;
    }
    if (uniquePairModels.length < 3) throw new Error('Could not find three live model IDs for the compare shot');
    const models = await fetchJson(`${args.base}/api/models.json`);
    const modelList = Array.isArray(models) ? models : models.models;
    const firstModel = modelList?.find(model => model.id === firstPair.a);
    const modelUrl = firstModel?.model_page_url || firstModel?.url || `/m/${firstPair.a.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase()}/`;
    const feedXml = await fetchText(`${args.base}/feed.xml`);

    let frameNumber = 0;
    const manifest = [];
    const evalJs = async expression => {
      const result = await cdp.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
      if (result.exceptionDetails) throw new Error(`Page evaluation failed: ${result.exceptionDetails.text}`);
      return result.result?.value;
    };
    const viewport = async (width = WIDTH, height = HEIGHT, mobile = false) => {
      await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile, screenWidth: width, screenHeight: height });
    };
    const navigate = async (url, selector = '') => {
      await cdp.send('Page.navigate', { url });
      for (let tries = 0; tries < 100; tries += 1) {
        const ready = await evalJs(`document.readyState === 'complete' && ${selector ? `!!document.querySelector(${JSON.stringify(selector)})` : 'true'}`).catch(() => false);
        if (ready) break;
        await sleep(100);
        if (tries === 99) throw new Error(`Timed out loading ${url}`);
      }
      await sleep(900);
    };
    const setCaption = caption => evalJs(captionScript(caption));
    const screenshot = async (format = 'jpeg') => {
      const result = await cdp.send('Page.captureScreenshot', { format, quality: format === 'jpeg' ? 82 : undefined, fromSurface: true, captureBeyondViewport: false });
      return Buffer.from(result.data, 'base64');
    };
    const writeFrames = async (buffer, count) => {
      for (let i = 0; i < count; i += 1) {
        frameNumber += 1;
        await writeFile(join(framesDir, `${String(frameNumber).padStart(6, '0')}.jpg`), buffer);
      }
    };
    const shot = async (index, phases) => {
      const [seconds, caption] = SHOTS[index - 1];
      const startFrame = frameNumber + 1;
      const total = seconds * FPS;
      let remaining = total;
      for (let i = 0; i < phases.length; i += 1) {
        const phasesLeft = phases.length - i;
        const count = Math.floor(remaining / phasesLeft);
        const buffer = await phases[i](caption);
        await writeFrames(buffer, count);
        remaining -= count;
      }
      manifest.push({ shot: index, start_frame: startFrame, end_frame: frameNumber, caption });
      console.log(`Shot ${index}/10: frames ${startFrame}-${frameNumber} — ${caption}`);
    };
    const pagePhase = async (caption, script = '') => {
      if (script) await evalJs(script);
      await setCaption(caption);
      await sleep(180);
      return screenshot();
    };

    await viewport();
    await navigate(`${args.base}/`, '#csvTable');
    await shot(1, Array.from({ length: 15 }, (_, index) => index * 30).map(y => caption => pagePhase(caption, `scrollTo({top:${y},behavior:'instant'})`)));
    await navigate(`${args.base}/`, '#globalSearch');
    await shot(2, ['', 'c', 'cl', 'clau', 'claude'].map(value => caption => pagePhase(caption, `(() => { const input=document.querySelector('#globalSearch'); input.value=${JSON.stringify(value)}; input.dispatchEvent(new Event('input',{bubbles:true})); })()`)));

    const filterUrl = `${args.base}/?capabilities=tool_calling&capMode=all&ctx=128-256,ge256&afx=1`;
    await navigate(filterUrl, '#filtersPanel.open');
    await shot(3, [
      caption => pagePhase(caption, `scrollTo(0, document.querySelector('#filtersPanel').offsetTop - 120)`),
      caption => pagePhase(caption, `document.querySelector('#filter-tool-calling')?.scrollIntoView({block:'center'})`),
      caption => pagePhase(caption, `document.querySelector('#contextFilters')?.scrollIntoView({block:'center'})`),
    ]);

    const compareUrl = `${args.base}/?cmp=${uniquePairModels.slice(0, 3).map(encodeURIComponent).join(',')}`;
    await navigate(compareUrl, '#compareTray.open');
    await shot(4, [
      caption => pagePhase(caption, `scrollTo(0, 260)`),
      caption => pagePhase(caption, `document.querySelector('#openCompare').click()`),
      caption => pagePhase(caption, `document.querySelector('#compareResults')?.scrollIntoView({block:'start'})`),
    ]);

    const calcUrl = `${args.base}/?calc=1&cm=${uniquePairModels.slice(0, 3).map(encodeURIComponent).join(',')}&cp=1000&cc=500&cr=100`;
    await navigate(calcUrl, '#calculatorModal[aria-hidden="false"]');
    await shot(5, [
      caption => pagePhase(caption),
      caption => pagePhase(caption, `document.querySelector('.calculator-preset[data-prompt="1000"]')?.click()`),
      caption => pagePhase(caption, `document.querySelector('#calcResults')?.scrollIntoView({block:'center'})`),
    ]);

    const phoneComposite = async (caption, search) => {
      await viewport(390, 844, true);
      await navigate(`${args.base}/`, '#cardView');
      await evalJs(`(() => { const input=document.querySelector('#globalSearch'); input.value=${JSON.stringify(search)}; input.dispatchEvent(new Event('input',{bubbles:true})); })()`);
      await sleep(200);
      const phone = await screenshot('png');
      const phoneData = `data:image/png;base64,${phone.toString('base64')}`;
      await viewport();
      const composite = `<!doctype html><meta charset="utf-8"><style>*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:radial-gradient(circle at 50% 40%,#263552,#090d17 68%);font-family:system-ui}.phone{position:absolute;left:50%;top:50%;height:680px;width:314px;transform:translate(-50%,-50%);object-fit:fill;border:8px solid #101827;border-radius:30px;box-shadow:0 24px 70px #000;overflow:hidden}</style><img class="phone" src="${phoneData}">`;
      await navigate(htmlDataUrl(composite), '.phone');
      return pagePhase(caption);
    };
    await shot(6, ['', 'c', 'cl', 'clau', 'claude'].map(value => caption => phoneComposite(caption, value)));

    await viewport();
    await navigate(new URL(modelUrl, args.base).href, 'main');
    await shot(7, Array.from({ length: 10 }, (_, index) => index * 70).map(y => caption => pagePhase(caption, `scrollTo({top:${y},behavior:'instant'})`)));
    await navigate(`${args.base}/compare/${firstPair.slug}/`, 'main');
    await shot(8, Array.from({ length: 10 }, (_, index) => index * 75).map(y => caption => pagePhase(caption, `scrollTo({top:${y},behavior:'instant'})`)));

    await navigate(`${args.base}/`, '#changesStrip');
    await shot(9, [
      caption => pagePhase(caption, `(() => { const strip=document.querySelector('#changesStrip'); strip?.scrollIntoView({block:'start'}); document.querySelector('#changesToggle')?.click(); })()`),
      async caption => {
        const visibleFeed = escapeHtml(feedXml.slice(0, 9000));
        const feedPage = `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:#f7f8fb;color:#172033;font-family:ui-monospace,SFMono-Regular,Menlo,monospace}.bar{padding:16px 28px;background:#172033;color:white;font:600 20px system-ui}.xml{white-space:pre-wrap;word-break:break-word;padding:22px 34px;font-size:15px;line-height:1.45}</style><div class="bar">${escapeHtml(args.base)}/feed.xml</div><pre class="xml">${visibleFeed}</pre>`;
        await navigate(htmlDataUrl(feedPage), '.xml');
        return pagePhase(caption);
      },
    ]);

    const endCard = `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;display:grid;place-items:center;background:radial-gradient(circle at center,#233457,#080c15);color:white;font-family:system-ui}.mark{text-align:center;margin-bottom:72px}.mark h1{font-size:58px;margin:0 0 14px}.mark p{font-size:24px;color:#b9c7e3;margin:0}</style><div class="mark"><h1>OpenRouterList</h1><p>Clear pricing for every OpenRouter model</p></div>`;
    await navigate(htmlDataUrl(endCard), '.mark');
    await shot(10, [caption => pagePhase(caption)]);

    // Revisit the opening title frame in PNG for the poster.
    await viewport();
    await navigate(`${args.base}/`, '#csvTable');
    await setCaption(SHOTS[0][1]);
    const posterPng = await screenshot('png');
    await writeFile(join(args.out, 'poster.png'), posterPng);

    const outputManifest = {
      fps: FPS,
      width: WIDTH,
      height: HEIGHT,
      total_frames: frameNumber,
      duration_seconds: frameNumber / FPS,
      base_url: args.base,
      first_pair: firstPair,
      shots: manifest,
      page_errors: pageErrors,
    };
    await writeFile(join(framesDir, 'manifest.json'), `${JSON.stringify(outputManifest, null, 2)}\n`);
    if (pageErrors.length) throw new Error(`Page errors were reported:\n${pageErrors.map(error => `- ${error}`).join('\n')}`);

    if (!args.framesOnly) {
      const outputVideo = join(args.out, 'demo.mp4');
      let encoded = false;
      for (const crf of [28, 30, 32, 34]) {
        const ffmpeg = spawn('ffmpeg', ['-y', '-framerate', String(FPS), '-i', join(framesDir, '%06d.jpg'), '-an', '-c:v', 'libx264', '-crf', String(crf), '-preset', 'medium', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', outputVideo], { stdio: 'inherit' });
        const code = await new Promise(resolvePromise => ffmpeg.on('close', resolvePromise));
        if (code !== 0) throw new Error('ffmpeg failed; install ffmpeg or use --frames-only');
        if ((await stat(outputVideo)).size < 10 * 1024 * 1024) { encoded = true; break; }
      }
      if (!encoded) throw new Error('Encoded video is still 10 MB or larger at CRF 34');
      await copyFile(join(args.out, 'poster.png'), join(args.out, 'demo-poster.png'));
      console.log(`Wrote ${outputVideo} and ${join(args.out, 'demo-poster.png')}`);
    } else {
      console.log(`Frames-only proof complete: ${frameNumber} frames, ${frameNumber / FPS}s, no page errors`);
    }
  } finally {
    cdp?.close();
    if (chrome && chrome.exitCode === null) {
      chrome.kill('SIGTERM');
      await Promise.race([new Promise(resolvePromise => chrome.once('exit', resolvePromise)), sleep(3000)]);
      if (chrome.exitCode === null) chrome.kill('SIGKILL');
    }
    await rm(profile, { recursive: true, force: true });
  }
}

main().catch(error => {
  console.error(`record-demo: ${error.message}`);
  process.exitCode = 1;
});
