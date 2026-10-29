const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('web/browser_scanner.js', 'utf8');
function harness(getMedia) {
  let now = 10000;
  const elements = [];
  let stopped = 0;
  let decode;
  const stream = {getTracks: () => [{stop: () => stopped++}]};
  const document = {
    getElementById: () => null,
    body: {append() {}},
    createElement(tag) {
      const element = {tag, style: {}, setAttribute() {}, append(...children) {this.children = [...(this.children || []), ...children];}, remove() {this.removed = true;}};
      elements.push(element); return element;
    }
  };
  const context = {Date: {now: () => now}, document, navigator: {mediaDevices: {getUserMedia: getMedia || (() => Promise.resolve(stream))}}, window: {ZXing: {
    BrowserMultiFormatReader: class {
      reset() {}
      decodeFromStream(s, video, callback) {
        assert.equal(video.playsInline, true); assert.equal(video.muted, true);
        decode = callback; return Promise.resolve();
      }
    }
  }}};
  vm.runInNewContext(source, context);
  return {open: (callback, summary) => context.window.ShopPadBrowserScanner.open(callback, summary),
    close: () => context.window.ShopPadBrowserScanner.close(),
    position: bounds => context.window.ShopPadBrowserScanner.position(JSON.stringify(bounds)), advance: ms => now += ms, elements, stream,
    get stopped() {return stopped;}, detect(code) {decode({getText: () => code});}};
}
const tick = () => new Promise(resolve => setImmediate(resolve));
test('recognized barcode resolves once and stops the camera', async () => {
  const h = harness(); const result = h.open(); await tick();
  h.detect('3017620422003'); h.detect('3017620422003');
  assert.equal(await result, '3017620422003');
  assert.equal(h.stopped, 1); assert.equal(h.elements[0].removed, true);
});
test('closing while permission is pending releases the late camera stream', async () => {
  let grant; const h = harness(() => new Promise(resolve => {grant = resolve;}));
  const result = h.open(); h.elements.find(e => e.textContent === 'Close').onclick();
  assert.equal(await result, null); grant(h.stream); await tick();
  assert.equal(h.stopped, 1);
});
test('denied permission displays a reason and permits a retry', async () => {
  const h = harness(() => Promise.reject(Object.assign(new Error('Permission denied'), {name:'NotAllowedError'})));
  const result = h.open(); await tick();
  assert.match(h.elements.find(e => e.tag === 'p').textContent, /NotAllowedError/);
  assert.equal(h.elements.find(e => e.textContent === 'Start \/ retry camera').disabled, false);
  h.elements.find(e => e.textContent === 'Close').onclick();
  assert.equal(await result, null);
});

test('continuous checkout serializes scans and reports the actual cart summary', async () => {
  const h = harness(); const codes = []; let releaseFirst;
  const first = new Promise(resolve => {releaseFirst = resolve;});
  const result = h.open(async code => {
    codes.push(code); if (codes.length === 1) await first;
    return JSON.stringify({ok:true, message:code+' added',summary:codes.length+' items · BD 2.000'});
  }, '0 items · BD 0.000');
  await tick(); h.detect('A'); h.detect('A'); h.detect('B'); h.detect('A');
  assert.deepEqual(codes, ['A']); releaseFirst(); await tick();
  assert.deepEqual(codes, ['A','B']);
  assert.equal(h.elements.find(e => e.tag === 'strong' && e.textContent.includes('items')).textContent, '2 items · BD 2.000');
  h.elements.find(e => e.textContent === 'Review sale').onclick();
  assert.equal(await result, 'review'); assert.equal(h.stopped, 1);
});
test('a continuously held label stays blocked and identical units use the repeat button', async () => {
  const h = harness(); const codes = [];
  const result = h.open(async code => {codes.push(code); return JSON.stringify({ok:true,message:'Added',summary:'1 item'});});
  await tick(); h.detect('A'); await tick();
  for (let i=0;i<10;i++) {h.advance(1000);h.detect('A');await tick();}
  assert.deepEqual(codes,['A']);
  h.elements.find(e => e.textContent === 'Add same item').onclick(); await tick();
  assert.deepEqual(codes,['A','A']);
  h.advance(1700); h.detect('A'); await tick(); assert.deepEqual(codes,['A','A','A']);
  h.close(); assert.equal(await result,null);
});
test('closing while a cart lookup runs drops queued scans and never updates the closed overlay', async () => {
  const h = harness(); let finishLookup; const codes=[];
  const result = h.open(code => {codes.push(code); return new Promise(resolve => {finishLookup=resolve;});});
  await tick(); h.detect('A'); h.detect('B'); h.close();
  finishLookup(JSON.stringify({ok:true,message:'Added',summary:'1 item'})); await tick();
  assert.deepEqual(codes,['A']); assert.equal(await result,null); assert.equal(h.stopped,1);
});

test('cashier camera is positioned inside Scan and has no full-screen navigation layer', async () => {
  const h = harness();
  h.position({left:16,top:120,width:300,height:180});
  const result = h.open(async () => JSON.stringify({ok:true,message:'Pen added',summary:'1 item'}));
  await tick();
  const overlay = h.elements[0];
  assert.equal(overlay.style.left,'16px'); assert.equal(overlay.style.top,'120px');
  assert.equal(overlay.style.width,'300px'); assert.equal(overlay.style.height,'180px');
  assert.ok(overlay.children.some(child => child.tag === 'video'));
  assert.equal(overlay.children.some(child => child.textContent === 'Review sale'),false);
  assert.equal(overlay.children.some(child => child.tag === 'div'),false);
  h.position({left:8,top:110,width:320,height:160});
  assert.equal(overlay.style.width,'320px'); assert.equal(overlay.style.height,'160px');
  h.close(); assert.equal(await result,null); assert.equal(h.stopped,1);
});

