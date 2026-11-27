const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('web/browser_scanner.js','utf8');
test('a user gesture unlocks audio and rapid scans schedule distinct short pulses',()=>{
 const gestures={},starts=[],stops=[],frequencies=[];
 class AudioContext {
  constructor(){this.state='suspended';this.currentTime=1;this.destination={};}
  resume(){this.state='running';return Promise.resolve();}
  createOscillator(){const frequency={};frequencies.push(frequency);return {frequency,connect(){},disconnect(){},start(t){starts.push(t);},stop(t){stops.push(t);}};}
  createGain(){return {gain:{setValueAtTime(){},linearRampToValueAtTime(){}},connect(){},disconnect(){}};}
 }
 const window={AudioContext},document={addEventListener:(event,callback)=>gestures[event]=callback};
 vm.runInNewContext(source,{window,document});assert.equal(typeof gestures.pointerdown,'function');gestures.pointerdown();
 window.ShopPadBrowserScanner.playScanSound();window.ShopPadBrowserScanner.playScanSound();
 assert.equal(starts.length,2);assert.ok(starts[1]>stops[0]);assert.ok(stops[0]>starts[0]&&stops[0]-starts[0]<0.2);
});
test('missing or blocked audio does not stop barcode handling',()=>{
 for(const AudioContext of [undefined,class{constructor(){throw Error('Blocked');}}]){
  const window={AudioContext},document={};vm.runInNewContext(source,{window,document});assert.doesNotThrow(()=>window.ShopPadBrowserScanner.playScanSound());
 }
});
