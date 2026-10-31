const {test, before} = require('node:test');
const assert = require('node:assert/strict');
// Hard-coded demo emulator: these tests must never write to a live project.
const base = 'http://127.0.0.1:9080/v1/projects/demo-shoppad-security/databases/(default)/documents';
function token(uid, verified=true) {
  const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  return b64({alg:'none', typ:'JWT'})+'.'+b64({iss:'https://securetoken.google.com/demo-shoppad-security',aud:'demo-shoppad-security',sub:uid,user_id:uid,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,email:uid+'@test.invalid',email_verified:verified,firebase:{sign_in_provider:'password',identities:{}}})+'.';
}
function value(v) {
  if (v === null) return {nullValue:null};
  if (Array.isArray(v)) return {arrayValue:{values:v.map(value)}};
  if (typeof v === 'object') return {mapValue:{fields:fields(v)}};
  if (typeof v === 'boolean') return {booleanValue:v};
  if (typeof v === 'number') return Number.isInteger(v)?{integerValue:String(v)}:{doubleValue:v};
  return {stringValue:v};
}
function fields(data) { return Object.fromEntries(Object.entries(data).map(([k,v])=>[k,value(v)])); }
async function request(path, uid, {method='GET',data,query='',verified=true}={}) {
  const headers={'Content-Type':'application/json'};
  if(uid) headers.Authorization='Bearer '+(uid==='ADMIN'?'owner':token(uid,verified));
  const response=await fetch(base+path+query,{method,headers,body:data?JSON.stringify(data):undefined});
  const body=await response.json();
  return {status:response.status,body};
}
async function put(path,data,uid='ADMIN',verified=true) { return request('/'+path,uid,{method:'PATCH',data:{fields:fields(data)},verified}); }
async function patch(path,data,uid) { return request('/'+path,uid,{method:'PATCH',data:{fields:fields(data)},query:'?'+Object.keys(data).map(k=>'updateMask.fieldPaths='+k).join('&')}); }
async function commit(writes,uid,verified=true) {
  return request(':commit',uid,{method:'POST',verified,data:{writes:writes.map(([path,data])=>({update:{name:'projects/demo-shoppad-security/databases/(default)/documents/'+path,fields:fields(data)}}))}});
}
async function query(collection,filters,uid) {
  return request(':runQuery',uid,{method:'POST',data:{structuredQuery:{from:[{collectionId:collection}],where:{compositeFilter:{op:'AND',filters:Object.entries(filters).map(([field,v])=>({fieldFilter:{field:{fieldPath:field},op:'EQUAL',value:value(v)}}))}}}}});
}
function allowed(result) { assert.ok(result.status>=200 && result.status<300, JSON.stringify(result)); }
function denied(result) { assert.equal(result.status,403,JSON.stringify(result)); }
before(async()=>{
  const cleared=await fetch('http://127.0.0.1:9080/emulator/v1/projects/demo-shoppad-security/databases/(default)/documents',{method:'DELETE'});
  assert.ok(cleared.ok);

  for (const code of ['A','B']) {
    allowed(await put('users/owner'+code,{uid:'owner'+code,role:'owner',email:'owner'+code+'@test.invalid',storeCode:code}));
    allowed(await put('stores/'+code,{storeCode:code,ownerUid:'owner'+code,storeName:'Demo'}));
    allowed(await put('users/cashier'+code,{uid:'cashier'+code,role:'cashier',storeCode:code,isActive:true,status:'active'}));
    allowed(await put('products/product'+code,{storeCode:code,name:'Pen',price:2,stock:3,barcode:'123'}));
    allowed(await put('sales/sale'+code,{storeCode:code,cashierUid:'cashier'+code,total:2,status:'completed'}));
  }
});
test('anonymous and unverified accounts cannot access store data',async()=>{
  denied(await request('/products/productA',null));
  denied(await put('products/hacked',{storeCode:'A'},null));
  denied(await request('/products/productA','cashierA',{verified:false}));
});
test('store boundaries apply to owners, cashiers and queries',async()=>{
  allowed(await request('/products/productA','cashierA'));
  denied(await request('/products/productB','cashierA'));
  denied(await request('/stores/B','ownerA'));
  allowed(await query('products',{storeCode:'A'},'ownerA'));
  denied(await query('products',{storeCode:'B'},'ownerA'));
});
test('cashier cannot promote, move, or approve their own account',async()=>{
  denied(await patch('users/cashierA',{role:'owner'},'cashierA'));
  denied(await patch('users/cashierA',{storeCode:'B'},'cashierA'));
  denied(await patch('users/cashierA',{isActive:false},'cashierA'));
  allowed(await patch('users/cashierA',{onDuty:false},'cashierA'));
});
test('cashier sees only their own receipts and cannot rewrite history',async()=>{
  allowed(await query('sales',{storeCode:'A',cashierUid:'cashierA'},'cashierA'));
  denied(await query('sales',{storeCode:'A'},'cashierA'));
  denied(await request('/sales/saleB','cashierA'));
  denied(await patch('sales/saleA',{total:0},'cashierA'));
});
test('approved cashier edits own-store catalogue but cannot cross stores or forge audit',async()=>{
  allowed(await put('products/editable',{storeCode:'A',name:'Book',category:'Stationery',price:2,stock:3,minStock:1,barcode:'456',image:''}));
  allowed(await patch('products/editable',{name:'Notebook',category:'School',price:20,stock:8,minStock:1,barcode:'789',image:'data:image/png;base64,AA==',catalogueSource:null,updatedAt:'2026-10-31'},'cashierA'));
  denied(await patch('products/productB',{price:1},'cashierA'));
  denied(await patch('products/editable',{storeCode:'B'},'cashierA'));
  denied(await patch('products/editable',{lastStockCorrection:{addedQuantity:99}},'cashierA'));
  denied(await patch('products/editable',{price:-1},'cashierA'));
  denied(await patch('products/editable',{stock:-1},'cashierA'));
  denied(await patch('products/editable',{price:1},null));
  denied(await request('/products/editable','cashierA',{method:'PATCH',data:{fields:fields({price:1})},query:'?updateMask.fieldPaths=price',verified:false}));
  denied(await put('sales/forged',{id:'forged',cashierUid:'ownerA',storeCode:'A',items:[{}],productIds:['productA'],total:2,status:'completed',type:'sale'},'cashierA'));
});
test('sale transaction updates stock but cashier cannot rewrite its audit linkage',async()=>{
  const sale={id:'new-sale',cashierUid:'cashierA',storeCode:'A',items:[{name:'Pen',price:2,quantity:1}],productIds:['productA'],total:2,status:'completed',type:'sale'};
  allowed(await commit([['sales/new-sale',sale],['products/productA',{storeCode:'A',name:'Pen',price:2,stock:2,barcode:'123',lastSaleId:'new-sale'}]],'cashierA'));
  denied(await patch('products/productA',{stock:1,lastSaleId:'fake-sale'},'cashierA'));
});
test('a receipt cannot be used to inflate inventory',async()=>{
  const sale={id:'inflate',cashierUid:'cashierA',storeCode:'A',items:[{name:'Pen',price:2,quantity:1}],productIds:['productA'],total:2,status:'completed',type:'sale'};
  denied(await commit([['sales/inflate',sale],['products/productA',{storeCode:'A',name:'Pen',price:2,stock:99,barcode:'123',lastSaleId:'inflate'}]],'cashierA'));
});
test('new owner must create their own store atomically and cannot claim an existing one',async()=>{
  denied(await put('users/attacker',{uid:'attacker',email:'attacker@test.invalid',role:'owner',storeCode:'A'},'attacker'));
  allowed(await commit([['users/newowner',{uid:'newowner',email:'newowner@test.invalid',role:'owner',storeCode:'NEW'}],['stores/NEW',{storeCode:'NEW',ownerUid:'newowner'}]],'newowner',false));
  denied(await patch('stores/A',{ownerUid:'cashierA'},'cashierA'));
});
test('new cashier is blocked until approved by the correct store owner',async()=>{
  allowed(await put('users/pending',{uid:'pending',email:'pending@test.invalid',role:'cashier',storeCode:'A',isActive:false,status:'pending'},'pending',false));
  denied(await request('/products/productA','pending'));
  denied(await patch('products/editable',{price:1},'pending'));
  denied(await patch('users/pending',{isActive:true,status:'active'},'pending'));
  denied(await patch('users/pending',{isActive:true,status:'active'},'ownerB'));
  allowed(await patch('users/pending',{isActive:true,status:'active'},'ownerA'));
  allowed(await request('/products/productA','pending'));
});
test('backups belong only to their owner and completed snapshots are immutable',async()=>{
  allowed(await put('stores/A/backups/copy',{storeCode:'A',ownerUid:'ownerA',complete:false},'ownerA'));
  denied(await request('/stores/A/backups/copy','cashierA'));
  allowed(await put('stores/A/backups/copy/products/p',{storeCode:'A'},'ownerA'));
  allowed(await patch('stores/A/backups/copy',{complete:true},'ownerA'));
  denied(await put('stores/A/backups/copy/products/late',{storeCode:'A'},'ownerA'));
  denied(await patch('stores/A/backups/copy',{complete:false},'ownerA'));
});
test('unknown collections and store listing stay closed',async()=>{
  denied(await put('admin/secrets',{value:'test'},'ownerA'));
  denied(await query('stores',{storeCode:'B'},'cashierA'));
});

test('barcode duplicate checks must be scoped to the authenticated store',async()=>{
  allowed(await put('products/same-barcode-other-store',{storeCode:'B',name:'Other book',price:5,stock:2,barcode:'789'}));
  denied(await query('products',{barcode:'789'},'cashierA'));
  const result=await query('products',{storeCode:'A',barcode:'789'},'cashierA');
  allowed(result);
  const docs=result.body.filter(row=>row.document).map(row=>row.document);
  assert.equal(docs.length,1);
  assert.equal(docs[0].fields.storeCode.stringValue,'A');
});

test('approved cashier deletes own-store product but cannot delete foreign products or receipts',async()=>{
  allowed(await put('products/delete-ours',{storeCode:'A',name:'Remove me',price:2,stock:1}));
  allowed(await put('products/delete-foreign',{storeCode:'B',name:'Keep me',price:2,stock:1}));
  denied(await request('/products/delete-ours',null,{method:'DELETE'}));
  denied(await request('/products/delete-ours','cashierA',{method:'DELETE',verified:false}));
  allowed(await put('users/disabled-delete',{uid:'disabled-delete',role:'cashier',storeCode:'A',isActive:false,status:'disabled'}));
  denied(await request('/products/delete-ours','disabled-delete',{method:'DELETE'}));
  denied(await request('/products/delete-foreign','cashierA',{method:'DELETE'}));
  denied(await request('/sales/saleA','cashierA',{method:'DELETE'}));
  allowed(await request('/products/delete-ours','cashierA',{method:'DELETE'}));
  assert.equal((await request('/products/delete-ours','ADMIN')).status,404);
  allowed(await request('/products/delete-foreign','ADMIN'));
  allowed(await request('/sales/saleA','ADMIN'));
});
