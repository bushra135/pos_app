const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
test('every build loads a versioned app bundle without touching saved data', () => {
  const template = fs.readFileSync('web/flutter_bootstrap.js', 'utf8');
  let loaded = 0;
  const context = {_flutter: {buildConfig: {builds: [{mainJsPath: 'main.dart.js'}]}, loader: {load() {loaded++;}}}};
  const source = template.replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '').replace('{{flutter_service_worker_version}}', '"new-build"');
  vm.runInNewContext(source, context);
  assert.equal(context._flutter.buildConfig.builds[0].mainJsPath, 'main.dart.js?release=new-build');
  assert.equal(loaded, 1);
  assert.ok(!source.includes('localStorage'));
  assert.ok(!source.includes('indexedDB'));
});
