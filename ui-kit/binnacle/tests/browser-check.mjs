// Drives headless Edge over CDP against the local demo: real mouse input, full-rate animation, screenshots.
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';

const OUT = process.argv[2];
if (!OUT) { console.error('usage: node browser-check.mjs <screenshot folder>'); process.exit(64); }
const URL_ = 'http://127.0.0.1:25191/binnacle/demo.html';
const EDGE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const PORT = 9347;
const profile = join(OUT, '..', 'edge-profile');
mkdirSync(OUT, { recursive: true });
const sleep = ms => new Promise(r => setTimeout(r, ms));

const edge = spawn(EDGE, ['--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`, '--window-size=1280,800',
  '--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows','--disable-features=CalculateNativeWinOcclusion','--no-first-run', '--no-default-browser-check', '--autoplay-policy=no-user-gesture-required', '--mute-audio', 'about:blank'], { stdio: 'ignore' });

let target;
for (let i = 0; i < 60 && !target; i++) {
  await sleep(250);
  try { target = (await (await fetch(`http://127.0.0.1:${PORT}/json`)).json()).find(t => t.type === 'page'); } catch {}
}
if (!target) throw new Error('no edge');
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener('open', r));
let seq = 0; const pending = new Map(); const errors = [];
ws.addEventListener('message', e => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { const { res, rej } = pending.get(m.id); pending.delete(m.id); m.error ? rej(new Error(JSON.stringify(m.error))) : res(m.result); }
  if (m.method === 'Runtime.exceptionThrown') errors.push(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text);
  if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') errors.push(m.params.args.map(a => a.value).join(' '));
});
const send = (method, params = {}) => new Promise((res, rej) => { const id = ++seq; pending.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params })); });
const ev = async expr => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
  return r.result.value;
};
const shot = async (name, clip) => {
  const r = await send('Page.captureScreenshot', { format: 'png', ...(clip ? { clip: { ...clip, scale: 1 } } : {}) });
  writeFileSync(join(OUT, name + '.png'), Buffer.from(r.data, 'base64'));
};
const mouse = (type, x, y, extra = {}) => send('Input.dispatchMouseEvent', { type, x, y, button: 'left', buttons: type === 'mouseReleased' ? 0 : 1, clickCount: 1, ...extra });
const hover = (x, y) => send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none', buttons: 0 });
const results = [];
const check = (name, ok, detail) => { results.push({ name, ok: !!ok, detail }); console.log((ok ? 'PASS ' : 'FAIL ') + name + (detail !== undefined ? '  ' + JSON.stringify(detail) : '')); };
const pos = () => ev('binnacleDemo.main.position');
const load = async () => { await send('Page.navigate', { url: URL_ }); await sleep(900); };

await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable'); await send('Network.setCacheDisabled',{cacheDisabled:true}); await send('Page.bringToFront'); await send('Emulation.setFocusEmulationEnabled',{enabled:true});
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });
await load();
await ev(`localStorage.clear()`); await load();

// default position
const p0 = await pos();
check('starts bottom right', p0.x > 1000 && p0.y > 550, p0);

// drag with a real mouse
await mouse('mouseMoved', p0.x, p0.y, { buttons: 0, button: 'none' });
await mouse('mousePressed', p0.x, p0.y);
for (let i = 1; i <= 20; i++) { await mouse('mouseMoved', p0.x - i * 30, p0.y - i * 15); await sleep(12); }
const dragging = await ev(`document.querySelector('.binnacle:not(.inline)').classList.contains('dragging')`);
await mouse('mouseReleased', p0.x - 600, p0.y - 300);
const p1 = await pos();
check('drag moves orb with the mouse', Math.abs(p1.x - (p0.x - 600)) < 2 && Math.abs(p1.y - (p0.y - 300)) < 2, p1);
check('dragging class set during drag', dragging);
check('dragging class cleared', !(await ev(`document.querySelector('.binnacle:not(.inline)').classList.contains('dragging')`)));

// a drag must not trigger activate; a plain click must
await ev(`window.__act=0; window.__o=Binnacle.mount({id:'act',persist:false,x:150,y:150,size:200,onActivate:()=>window.__act++}); 0`);
await mouse('mousePressed', 150, 150); await mouse('mouseMoved', 200, 170); await mouse('mouseReleased', 200, 170);
check('drag does not fire activate', (await ev('window.__act')) === 0);
const q = await ev('window.__o.position');
await mouse('mousePressed', q.x, q.y); await mouse('mouseReleased', q.x, q.y);
check('click fires activate', (await ev('window.__act')) === 1);
await ev(`window.__o.destroy(); 0`);

// clamped to the screen
const p2 = await pos();
await mouse('mousePressed', p2.x, p2.y);
await mouse('mouseMoved', 5000, 5000); await mouse('mouseReleased', 5000, 5000);
const p3 = await pos();
check('clamped at bottom right', p3.x <= 1280 - 112 && p3.y <= 800 - 112, p3);
await mouse('mousePressed', p3.x, p3.y);
await mouse('mouseMoved', -5000, -5000); await mouse('mouseReleased', -5000, -5000);
const p4 = await pos();
check('clamped at top left', p4.x >= 112 && p4.y >= 112, p4);

// window shrinks
await ev(`binnacleDemo.main.moveTo(1100, 650); 0`);
await send('Emulation.setDeviceMetricsOverride', { width: 700, height: 500, deviceScaleFactor: 1, mobile: false }); await sleep(200);
const p5 = await pos();
check('stays on screen when window shrinks', p5.x <= 700 - 112 && p5.y <= 500 - 112, p5);
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false }); await sleep(200);
const p5b = await pos();
check('returns when window grows', Math.abs(p5b.x - 1100) < 2 && Math.abs(p5b.y - 650) < 2, p5b);

// remembered after reload
await ev(`binnacleDemo.main.moveTo(640, 420); binnacleDemo.main.setLook('mesh'); 0`);
await load();
const p6 = await pos();
check('position remembered after reload', p6.x === 640 && p6.y === 420, p6);
check('look remembered after reload', (await ev('binnacleDemo.main.look')) === 'mesh');
await ev(`localStorage.setItem('binnacle:assistant','{bad json'); 0`); await load();
check('survives corrupt saved data', (await ev('binnacleDemo.main.look')) === 'ring');

// page clicks pass through the square corners of the orb, and are blocked only by the disc
const b = await ev(`(()=>{const k=document.getElementById('clicker');k.scrollIntoView({block:'center'});const r=k.getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2}})()`);
await ev(`binnacleDemo.main.moveTo(${b.x + 118}, ${b.y + 118}); 0`);   // button sits in the top-left corner of the orb's square
const inside = await ev(`(()=>{const o=document.querySelector('.binnacle:not(.inline)').getBoundingClientRect();const c=${JSON.stringify(b)};return c.x>o.left&&c.x<o.right&&c.y>o.top&&c.y<o.bottom})()`);
check('button is inside the orb square', inside);
await mouse('mouseMoved', b.x, b.y, { buttons: 0, button: 'none' });
await mouse('mousePressed', b.x, b.y); await mouse('mouseReleased', b.x, b.y);
check('click beside the disc reaches the page', (await ev(`document.getElementById('clicker').textContent`)) === 'Clicked 1 time');

// keyboard
await ev(`binnacleDemo.main.moveTo(640,400); document.querySelector('.binnacle:not(.inline) .binnacle-hit').focus(); 0`);
await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'ArrowLeft', code: 'ArrowLeft', windowsVirtualKeyCode: 37 });
await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'ArrowLeft', code: 'ArrowLeft', windowsVirtualKeyCode: 37 });
check('arrow key moves orb', (await pos()).x === 624);
check('hit target has a label', /orb, Point ring, Aurora, Standing by/.test(await ev(`document.querySelector('.binnacle:not(.inline) .binnacle-hit').getAttribute('aria-label')`)));

// picker
await hover(640, 400); await sleep(300);
const pv = await ev(`getComputedStyle(document.querySelector('.binnacle:not(.inline) .binnacle-pick')).visibility`);
check('picker shows on hover', pv === 'visible', pv);
await ev(`document.activeElement.blur(); 0`);
const pk = await ev(`(()=>{const r=document.querySelector('.binnacle:not(.inline) [data-look=lightning]').getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2}})()`);
await hover(pk.x, pk.y); await sleep(100);
await mouse('mousePressed', pk.x, pk.y); await mouse('mouseReleased', pk.x, pk.y);
check('picker changes look', (await ev('binnacleDemo.main.look')) === 'lightning');

// contract event
await ev(`window.dispatchEvent(new CustomEvent('fleet:voice',{detail:{schema:'fleet.voice/1',state:'working',level:0.2,text:'Reading'}})); 0`);
check('fleet:voice event, alias working', (await ev(`Binnacle.voice.state`)) === 'thinking');
check('caption shows text', /Thinking: Reading/.test(await ev(`document.querySelector('.binnacle:not(.inline) .binnacle-cap').textContent`)));
await ev(`Binnacle.voice.simulate(false); window.dispatchEvent(new CustomEvent('fleet:voice',{detail:{state:'nonsense',level:9}})); 0`);
check('unknown state ignored, level clamped', (await ev(`Binnacle.voice.state+':'+Binnacle.voice.level`)) === 'thinking:1');
await ev(`Binnacle.voice.simulate(true); 0`);

// every look in every state; then every look in every theme
await ev(`scrollTo(0,0); binnacleDemo.main.moveTo(640,400); Binnacle.voice.set('idle',0,''); 0`);
const clip = { x: 490, y: 250, width: 300, height: 330 };
const looks = ['ring', 'mesh', 'lightning', 'ribbon', 'eclipse'], states = ['idle', 'listening', 'thinking', 'speaking', 'approval'], themes = ['aurora', 'brass', 'ember', 'glacier', 'reef'];
const text = { listening: 'Go ahead.', thinking: 'Checking 212 files.', speaking: 'Turnover is ready.', approval: 'Move 14 screenshots to Archive?' };
for (const look of looks) {
  await ev(`binnacleDemo.main.setLook('${look}'); 0`);
  for (const s of states) {
    await ev(`Binnacle.voice.set('${s}', undefined, ${JSON.stringify(text[s] || '')}); 0`);
    await sleep(1100);
    await shot(`${look}-${s}-aurora`, clip);
    const m = await ev(`(async()=>{const c=document.querySelector('.binnacle:not(.inline) canvas'),g=c.getContext('2d');
      const a=g.getImageData(0,0,c.width,c.height).data; await new Promise(r=>setTimeout(r,250));
      const b=g.getImageData(0,0,c.width,c.height).data; let d=0,lit=0; for(let i=0;i<a.length;i+=4){d+=Math.abs(a[i]-b[i])+Math.abs(a[i+2]-b[i+2]); if(b[i]+b[i+1]+b[i+2]>120)lit++}
      return {change:Math.round(d/1000),lit,fps:binnacleDemo.main.stats().fps}})()`);
    check(`${look}/${s} animates`, m.change > 5 && m.lit > 200, m);
  }
}
await ev(`Binnacle.voice.set('speaking',undefined,''); 0`);
for (const theme of themes) {
  await ev(`binnacleDemo.main.setTheme('${theme}'); 0`);
  for (const look of looks) { await ev(`binnacleDemo.main.setLook('${look}'); 0`); await sleep(220); await shot(`matrix-${look}-${theme}`, { x: 520, y: 280, width: 240, height: 240 }); }
}
await ev(`binnacleDemo.main.setTheme('aurora'); binnacleDemo.main.setLook('ring'); 0`);

// tiles must each keep their own theme (looks hold per-orb state)
const tileColours = await ev(`[...document.querySelectorAll('.binnacle.inline canvas')].slice(0,5).map(c=>{const d=c.getContext('2d').getImageData(0,0,c.width,c.height).data;let r=0,g=0,b=0;for(let i=0;i<d.length;i+=4){r+=d[i];g+=d[i+1];b+=d[i+2]}return Math.round(r/(g+1)*100)})`);
check('tiles differ by theme', new Set(tileColours).size === 5, tileColours);

// the picker's theme swatch, and a gallery tile applied to the orb
await hover(640, 400); await sleep(250);
const sw = await ev(`(()=>{const r=document.querySelector('.binnacle:not(.inline) [data-theme=reef]').getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2}})()`);
await hover(sw.x, sw.y); await sleep(80); await mouse('mousePressed', sw.x, sw.y); await mouse('mouseReleased', sw.x, sw.y);
check('swatch changes theme', (await ev('binnacleDemo.main.theme')) === 'reef');
check('gallery has 25 tiles', (await ev(`document.querySelectorAll('.binnacle.inline').length`)) === 25);
await ev(`document.querySelectorAll('.binnacle.inline .binnacle-hit')[18].click(); 0`);
check('tile applies look and theme', (await ev(`binnacleDemo.main.look+'/'+binnacleDemo.main.theme`)) === 'ribbon/glacier');
await ev(`binnacleDemo.main.setTheme('aurora'); binnacleDemo.main.setLook('ring'); 0`);

// speaking must follow the level: compare lit radius loud vs silent
await ev(`document.getElementById('simulate').click(); binnacleDemo.main.setLook('ring'); Binnacle.voice.set('speaking',0,''); 0`);
const extent = `(async()=>{await new Promise(r=>setTimeout(r,700));const c=document.querySelector('.binnacle:not(.inline) canvas'),g=c.getContext('2d'),w=c.width,d=g.getImageData(0,0,w,w).data;let far=0,sum=0;
  for(let y=0;y<w;y++)for(let x=0;x<w;x++){const i=(y*w+x)*4;if(d[i]+d[i+1]+d[i+2]>160){const r=Math.hypot(x-w/2,y-w/2);sum+=r>w*.37?1:0;if(r>far)far=r}}return {far:Math.round(far),outside:sum}})()`;
const quiet = await ev(extent);
await ev(`Binnacle.voice.setLevel(0.4); 0`);
const loud = await ev(extent);
check('speaking reacts to level', loud.outside > quiet.outside * 1.5 + 20, { quiet, loud });
await ev(`Binnacle.voice.setLevel(0); 0`);

// real audio path: <audio> -> Web Audio -> level -> speaking -> idle
await ev(`Binnacle.voice.set('idle',0,''); document.getElementById('tone').click(); 0`);
let peak = 0, spoke = false;   // sampled in the page: polling from here can outlast the 4 s clip on a busy machine
for (let i = 0; i < 30; i++) { await sleep(60); const v = await ev(`({l:Binnacle.voice.level,s:Binnacle.voice.state})`); if (v.s === 'speaking') { spoke = true; peak = Math.max(peak, v.l); } }
check('fromAudio goes to speaking with a real level', spoke && peak > 0.03, { spoke, peak });
await ev(`new Promise(r => { const t = setInterval(() => { if (Binnacle.voice.state === 'idle') { clearInterval(t); r(); } }, 50); setTimeout(r, 6000); })`);
const after = await ev(`({l:Binnacle.voice.level,s:Binnacle.voice.state})`);
check('fromAudio returns to idle at the end', after.s === 'idle' && after.l === 0, after);

// frame rate
await load();
const measure = async (label, ms = 3000) => {
  const r = await ev(`(async()=>{await new Promise(r=>setTimeout(r,${ms}));const s=binnacleDemo.main.stats();return s})()`);
  return r;
};
const perf = {};
for (const look of looks) {
  await ev(`binnacleDemo.main.setLook('${look}'); Binnacle.voice.set('speaking'); 0`);
  perf[look] = await measure(look);
}
console.log('PERF unthrottled', JSON.stringify(perf));
check('smooth on this machine', Object.values(perf).every(s => s.fps >= 40), Object.values(perf).map(s => s.fps));
await send('Emulation.setCPUThrottlingRate', { rate: 6 });
await ev(`localStorage.clear(); 0`); await load();
await ev(`binnacleDemo.tiles.forEach(t => t.destroy()); 0`);   // one orb, as on a real page
const slow = {};
for (const look of looks) {
  await ev(`binnacleDemo.main.setLook('${look}'); Binnacle.voice.set('speaking'); 0`);
  await sleep(4000);
  slow[look] = await measure(look, 2000);
}
console.log('PERF 6x CPU throttle', JSON.stringify(slow));
check('usable at 6x CPU throttle', Object.values(slow).every(s => s.fps >= 20), Object.values(slow).map(s => [s.fps, s.tier]));
await send('Emulation.setCPUThrottlingRate', { rate: 1 });

// reduced motion
await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
await load();
const still = await ev(`(async()=>{const c=document.querySelector('.binnacle:not(.inline) canvas'),g=c.getContext('2d');Binnacle.voice.set('speaking',.3);g.getImageData(0,0,1,1);await new Promise(r=>setTimeout(r,100));
  const a=g.getImageData(0,0,c.width,c.height).data;await new Promise(r=>setTimeout(r,500));const b=g.getImageData(0,0,c.width,c.height).data;let d=0;for(let i=0;i<a.length;i++)d+=Math.abs(a[i]-b[i]);
  const speak=Array.from(a.slice(0,0));Binnacle.voice.set('approval');const e=g.getImageData(0,0,c.width,c.height).data;let d2=0;for(let i=0;i<a.length;i++)d2+=Math.abs(a[i]-e[i]);
  return {diffOverTime:d,diffBetweenStates:d2,reduced:binnacleDemo.main.stats().reduced}})()`);
check('reduced motion: still, but states differ', still.reduced && still.diffOverTime === 0 && still.diffBetweenStates > 1000, still);
await ev(`scrollTo(0,0); binnacleDemo.main.moveTo(640,400); 0`); await sleep(100); await shot('reduced-approval', clip);
await send('Emulation.setEmulatedMedia', { features: [] });
await ev(`Binnacle.voice.set('idle',0,''); 0`);

// whole-page shots: all three on the demo page, and on the light theme
await load();
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 1000, deviceScaleFactor: 1, mobile: false });
await ev(`binnacleDemo.main.moveTo(1100,820); Binnacle.voice.set('speaking',undefined,'Turnover is ready.'); document.getElementById('h-gallery').scrollIntoView(); 0`);
await sleep(2500); await shot('page-gallery-dark');
const gfps = await ev(`binnacleDemo.main.stats()`);
check('smooth with all 26 orbs running', gfps.fps >= 30, gfps);
await ev(`Kit.theme.apply('light'); 0`); await sleep(500); await shot('page-gallery-light');
await ev(`Kit.theme.apply('dark'); localStorage.clear(); 0`);

check('no page errors', errors.length === 0, errors.slice(0, 5));
writeFileSync(join(OUT, '..', 'results.json'), JSON.stringify(results, null, 1));
console.log(`\n${results.filter(r => r.ok).length}/${results.length} passed`);
ws.close(); edge.kill(); await sleep(500);
try { rmSync(profile, { recursive: true, force: true }); } catch {}
process.exit(results.every(r => r.ok) ? 0 : 1);
