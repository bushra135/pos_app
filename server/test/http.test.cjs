'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');const http=require('node:http');const {createHandler}=require('../index.cjs');
async function run(fn,options={}){const server=http.createServer(createHandler({checkout:async()=>({id:'ok',status:'completed'}),verifyToken:async token=>{if(token!=='valid')throw Error('Invalid token');return {uid:'cashier',email_verified:true};},origins:['https://shop.example'],...options}));await new Promise(r=>server.listen(0,'127.0.0.1',r));try{await fn('http://127.0.0.1:'+server.address().port+'/checkout');}finally{await new Promise(r=>server.close(r));}}
test('missing or forged bearer credentials are rejected before checkout',async()=>{let calls=0;await run(async url=>{for(const token of ['', 'fake']){const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:'{}'});assert.equal(r.status,401);}assert.equal(calls,0);},{checkout:async()=>{calls++;}});});
test('CORS is exact, preflight works, and successful requests are never cached',async()=>{await run(async url=>{assert.equal((await fetch(url,{method:'OPTIONS',headers:{Origin:'https://evil.example'}})).status,403);const preflight=await fetch(url,{method:'OPTIONS',headers:{Origin:'https://shop.example'}});assert.equal(preflight.status,204);const response=await fetch(url,{method:'POST',headers:{Origin:'https://shop.example',Authorization:'Bearer valid','Content-Type':'application/json'},body:'{}'});assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');assert.equal(response.headers.get('access-control-allow-origin'),'https://shop.example');});});
test('malformed bodies and internal errors do not disclose SDK details',async()=>{await run(async url=>{const headers={Authorization:'Bearer valid','Content-Type':'application/json'};assert.equal((await fetch(url,{method:'POST',headers,body:'not json'})).status,400);const failed=await fetch(url,{method:'POST',headers,body:'{}'});assert.equal(failed.status,503);assert.deepEqual(await failed.json(),{error:'unavailable'});},{checkout:async()=>{throw Error('private credential and document data');}});});

test('public receipt verification renders escaped metadata and never exposes internal fields',async()=>{
 await run(async url=>{const verify=url.replace('/checkout','/verify');const response=await fetch(verify+'?token=token');assert.equal(response.status,200);const html=await response.text();assert.ok(html.includes('&lt;script&gt;'));assert.ok(!html.includes('<script>'));assert.ok(html.includes('BHD 2.000'));assert.match(response.headers.get('content-security-policy'),/default-src 'none'/);assert.equal(response.headers.get('referrer-policy'),'no-referrer');
 const invalid=await fetch(verify,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:'invalid'})});assert.equal(invalid.status,400);assert.deepEqual(await invalid.json(),{valid:false});
 },{verifyReceipt:async token=>token==='token'?{valid:true,merchant:'<script>',receipt:'RCPT-1',totalFils:2000,currency:'BHD',date:'2026-11-27'}:null});
});


test('receipt verification browser preflight allows only the configured origin without reading receipts',async()=>{
 let reads=0,authCalls=0,checkoutCalls=0;
 await run(async url=>{
  const verify=url.replace('/checkout','/verify');
  const headers={Origin:'https://shop.example','Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'content-type'};
  const preflight=await fetch(verify,{method:'OPTIONS',headers});
  assert.equal(preflight.status,204);
  assert.equal(preflight.headers.get('access-control-allow-origin'),'https://shop.example');
  assert.match(preflight.headers.get('access-control-allow-methods'),/POST/);
  assert.match(preflight.headers.get('access-control-allow-headers'),/Content-Type/i);
  assert.equal(preflight.headers.get('cache-control'),'no-store');
  assert.equal(await preflight.text(),'');
  assert.equal(reads,0);assert.equal(authCalls,0);assert.equal(checkoutCalls,0);
  assert.equal((await fetch(verify,{method:'OPTIONS',headers:{...headers,Origin:'https://evil.example'}})).status,403);
  const result=await fetch(verify,{method:'POST',headers:{Origin:'https://shop.example','Content-Type':'application/json'},body:JSON.stringify({token:'valid'})});
  assert.equal(result.status,200);assert.equal((await result.json()).valid,true);
  assert.equal(result.headers.get('access-control-allow-origin'),'https://shop.example');
  assert.equal(reads,1);
  assert.equal((await fetch(verify,{method:'DELETE',headers})).status,405);
  assert.equal((await fetch(url.replace('/checkout','/missing'),{method:'OPTIONS',headers})).status,404);
 },{verifyReceipt:async token=>{reads++;return token==='valid'?{valid:true}:null;},verifyToken:async()=>{authCalls++;},checkout:async()=>{checkoutCalls++;}});
});
