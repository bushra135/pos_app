const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
test('Excel download preserves binary content and cleans up the browser URL', () => {
  let blob, removed = false, clicked = false, cleanup;
  const link = {style: {}, click() { clicked = true; }, remove() { removed = true; }};
  const context = {
    window: {}, Blob, Uint8Array, atob,
    URL: { createObjectURL(value) { blob = value; return 'blob:test'; },
      revokeObjectURL(url) { assert.equal(url, 'blob:test'); } },
    document: { createElement(tag) { assert.equal(tag, 'a'); return link; },
      body: { append(value) { assert.equal(value, link); } } },
    setTimeout(callback, delay) { assert.equal(delay, 60000); cleanup = callback; },
  };
  vm.runInNewContext(fs.readFileSync('web/report_export.js', 'utf8'), context);
  const bytes = Buffer.from([0x50,0x4b,0x03,0x04,0,255,128]);
  context.window.ShopPadReportExport.download(bytes.toString('base64'), 'sales.xlsx');
  assert.equal(link.download, 'sales.xlsx');
  assert.equal(link.href, 'blob:test');
  assert.equal(blob.type, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  assert.ok(clicked && removed);
  cleanup();
  return blob.arrayBuffer().then(value => assert.deepEqual(Buffer.from(value), bytes));
});
