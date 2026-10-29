const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
test('CSV download preserves content and cleans up the browser URL', () => {
  let blob, removed = false, clicked = false, cleanup;
  const link = {style: {}, click() { clicked = true; }, remove() { removed = true; }};
  const context = {
    window: {}, Blob,
    URL: { createObjectURL(value) { blob = value; return 'blob:test'; },
      revokeObjectURL(url) { assert.equal(url, 'blob:test'); } },
    document: { createElement(tag) { assert.equal(tag, 'a'); return link; },
      body: { append(value) { assert.equal(value, link); } } },
    setTimeout(callback, delay) { assert.equal(delay, 60000); cleanup = callback; },
  };
  vm.runInNewContext(fs.readFileSync('web/report_export.js', 'utf8'), context);
  context.window.ShopPadReportExport.download('receipt,total\r\n1,3.000', 'sales.csv');
  assert.equal(link.download, 'sales.csv');
  assert.equal(link.href, 'blob:test');
  assert.equal(blob.type, 'text/csv;charset=utf-8');
  assert.ok(clicked && removed);
  cleanup();
  return blob.text().then(text => assert.equal(text, 'receipt,total\r\n1,3.000'));
});
