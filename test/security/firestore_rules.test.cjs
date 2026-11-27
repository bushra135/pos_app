const {test, before} = require('node:test');
const assert = require('node:assert/strict');
// Hard-coded demo emulator: these tests must never write to a live project.
const port=process.env.SHOPPAD_EMULATOR_PORT || '9080';
assert.match(port,/^\d{4,5}$/);
const emulator='http://127.0.0.1:'+port;
const base = emulator+'/v1/projects/demo-shoppad-security/databases/(default)/documents';
function token(uid, verified=true) {
  const b64 = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  return b64({alg:'none', typ:'JWT'})+'.'+b64({iss:'https://securetoken.google.com/demo-shoppad-security',aud:'demo-shoppad-security',sub:uid,user_id:uid,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,email:uid+'@test.invalid',email_verified:verified,firebase:{sign_in_provider:'password',identities:{}}})+'.';
}
function value(v) {
  if (v === null) return {nullValue:null};
  if (v instanceof Date) return {timestampValue:v.toISOString()};
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
// A write may name fields to set to the server's request time ($serverTime) and may be a
// partial update of an existing document ($mask), like the app's transactions.
async function commit(writes,uid,verified=true) {
  return request(':commit',uid,{method:'POST',verified,data:{writes:writes.map(([path,data])=>{
    const {$serverTime=[],$mask=false,...plain}=data;
    const write={update:{name:'projects/demo-shoppad-security/databases/(default)/documents/'+path,fields:fields(plain)}};
    if($mask){write.updateMask={fieldPaths:Object.keys(plain)};write.currentDocument={exists:true};}
    if($serverTime.length) write.updateTransforms=$serverTime.map(f=>({fieldPath:f,setToServerValue:'REQUEST_TIME'}));
    return write;
  })}});
}
// A cashier receipt as the app writes it: consistent totals, sale time and server sync time.
function receipt(id,cashier,extra={}) {
  return {id,cashierUid:cashier,storeCode:'A',items:[{name:'Pen',price:2,quantity:1}],productIds:['productA'],
    subtotal:2,discount:0,total:2,status:'completed',type:'sale',createdAt:new Date(),$serverTime:['syncedAt'],...extra};
}
async function query(collection,filters,uid) {
  return request(':runQuery',uid,{method:'POST',data:{structuredQuery:{from:[{collectionId:collection}],where:{compositeFilter:{op:'AND',filters:Object.entries(filters).map(([field,v])=>({fieldFilter:{field:{fieldPath:field},op:'EQUAL',value:value(v)}}))}}}}});
}
function allowed(result) { assert.ok(result.status>=200 && result.status<300, JSON.stringify(result)); }
function denied(result) { assert.equal(result.status,403,JSON.stringify(result)); }
before(async()=>{
  const cleared=await fetch(emulator+'/emulator/v1/projects/demo-shoppad-security/databases/(default)/documents',{method:'DELETE'});
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
  const edit={name:'Notebook',category:'School',price:20,minStock:1,barcode:'789',image:'data:image/png;base64,AA==',catalogueSource:null,updatedAt:'2026-10-31'};
  // Not allowed until the owner grants it; the cashier cannot grant it to themselves.
  denied(await patch('products/editable',edit,'cashierA'));
  denied(await patch('users/cashierA',{canEditProducts:true},'cashierA'));
  denied(await patch('users/cashierA',{canEditProducts:true},'ownerB'));
  allowed(await patch('users/cashierA',{canEditProducts:true},'ownerA'));
  allowed(await commit([['products/editable',{...edit,$mask:true}],['productBarcodes/A_789',{storeCode:'A',barcode:'789',productId:'editable'}]],'cashierA'));
  // Stock is not part of a catalogue edit any more.
  denied(await patch('products/editable',{stock:8},'cashierA'));
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
  const sale=receipt('new-sale','cashierA');
  allowed(await commit([['sales/new-sale',sale],['products/productA',{storeCode:'A',name:'Pen',price:2,stock:2,barcode:'123',lastSaleId:'new-sale'}]],'cashierA'));
  denied(await patch('products/productA',{stock:1,lastSaleId:'fake-sale'},'cashierA'));
});
test('a receipt cannot be used to inflate inventory',async()=>{
  const sale=receipt('inflate','cashierA');
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
test('cashier invites accept only the fields the invite screen writes',async()=>{
  // Same payload as CashiersManagementScreen: still allowed for the store owner.
  const invite={uid:'',fullName:'New Cashier',email:'new@test.invalid',role:'cashier',storeCode:'A',isActive:true,status:'invited',createdAt:'now',createdBy:'ownerA'};
  allowed(await put('users/invite-ok',invite,'ownerA'));
  // Extra fields are rejected, whatever they are called.
  denied(await put('users/invite-extra',{...invite,permissions:'admin'},'ownerA'));
  denied(await put('users/invite-store',{...invite,storeName:'Other'},'ownerA'));
  // The existing checks still apply: other stores, other roles, cashiers.
  denied(await put('users/invite-foreign',{...invite,storeCode:'B'},'ownerA'));
  denied(await put('users/invite-owner',{...invite,role:'owner'},'ownerA'));
  denied(await put('users/invite-by-cashier',invite,'cashierA'));
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
  allowed(await patch('users/cashierA',{canEditProducts:false},'ownerA'));
  denied(await request('/products/delete-ours','cashierA',{method:'DELETE'}));
  allowed(await patch('users/cashierA',{canEditProducts:true},'ownerA'));
  allowed(await request('/products/delete-ours','cashierA',{method:'DELETE'}));
  assert.equal((await request('/products/delete-ours','ADMIN')).status,404);
  allowed(await request('/products/delete-foreign','ADMIN'));
  allowed(await request('/sales/saleA','ADMIN'));
});
// Shared barcode names: createdAt must be the server time, exactly like the app's serverTimestamp().
async function shareName(code,data,uid,verified=true) {
  if (data.contributedBy === uid) data = {...data, contributedBy:'store'};
  return request(':commit',uid,{method:'POST',verified,data:{writes:[{
    update:{name:'projects/demo-shoppad-security/databases/(default)/documents/catalog/'+code,fields:fields(data)},
    updateTransforms:[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'}],
  }]}});
}
test('shared barcode names are readable by active stores and cannot be overwritten',async()=>{
  allowed(await shareName('6287017260083',{name:'Juice',category:'Drinks',contributedBy:'ownerA'},'ownerA'));
  allowed(await request('/catalog/6287017260083','cashierB'));
  denied(await request('/catalog/6287017260083',null));
  denied(await request('/catalog/6287017260083','cashierB',{verified:false}));
  denied(await shareName('6287017260083',{name:'Vandal',category:'',contributedBy:'ownerB'},'ownerB'));
  denied(await request('/catalog/6287017260083','ownerA',{method:'DELETE'}));
  denied(await request('/catalog','ownerA'));
});
test('shared barcode names reject private fields, forged authors and custom codes',async()=>{
  denied(await shareName('12345678',{name:'Pen',category:'',contributedBy:'ownerA',storeCode:'A'},'ownerA'));
  denied(await shareName('12345670',{name:'Pen',category:'',contributedBy:'ownerB'},'ownerA'));
  denied(await shareName('SKU-1',{name:'Pen',category:'',contributedBy:'ownerA'},'ownerA'));
  denied(await shareName('12345679',{name:'',category:'',contributedBy:'ownerA'},'ownerA'));
  denied(await shareName('12345671',{name:'Pen',category:'',contributedBy:'anon'},null));
});
test('shared suggested prices and images are validated and stock is never stored',async()=>{
  allowed(await shareName('12345672',{name:'Pen',category:'',price:0.25,image:'data:image/png;base64,AA==',contributedBy:'ownerA'},'ownerA'));
  denied(await shareName('12345673',{name:'Pen',category:'',price:-1,contributedBy:'ownerA'},'ownerA'));
  denied(await shareName('12345674',{name:'Pen',category:'',price:'free',contributedBy:'ownerA'},'ownerA'));
  denied(await shareName('12345675',{name:'Pen',category:'',image:'javascript:alert(1)',contributedBy:'ownerA'},'ownerA'));
  denied(await shareName('12345676',{name:'Pen',category:'',stock:9,contributedBy:'ownerA'},'ownerA'));
});
test('stores may fill a missing shared price or photo but never change existing values',async()=>{
  allowed(await shareName('12345677',{name:'Ruler',category:'',contributedBy:'ownerA'},'ownerA'));
  denied(await patch('catalog/12345677',{price:0.4},'cashierB'));
  allowed(await patch('catalog/12345677',{price:0.4},'ownerB'));
  denied(await patch('catalog/12345677',{price:9},'ownerB'));
  denied(await patch('catalog/12345677',{name:'Hacked'},'ownerB'));
  allowed(await patch('catalog/12345677',{image:'https://images.example/ruler.png'},'ownerB'));
  denied(await patch('catalog/12345677',{image:'https://images.example/other.png'},'ownerA'));
  denied(await patch('catalog/12345678',{image:'javascript:alert(1)'},'ownerB'));
  denied(await patch('catalog/12345677',{price:0.4},null));
});

test('cashier stock changes need the owner permission and a matching stock move',async()=>{
  allowed(await put('products/counted',{storeCode:'A',name:'Tape',price:1,stock:5,barcode:'555'}));
  const move=(id,before,after,extra={})=>({storeCode:'A',productId:'counted',productName:'Tape',before,after,
    delta:after-before,reason:'restock',byUid:'cashierA',byName:'A',$serverTime:['createdAt'],...extra});
  const adjust=(id,after)=>({stock:after,lastStockMoveId:id,$mask:true});
  allowed(await patch('users/cashierA',{canAdjustStock:false},'ownerA'));
  denied(await commit([['stockMoves/m0',move('m0',5,17)],['products/counted',adjust('m0',17)]],'cashierA'));
  allowed(await patch('users/cashierA',{canAdjustStock:true},'ownerA'));
  allowed(await commit([['stockMoves/m1',move('m1',5,17)],['products/counted',adjust('m1',17)]],'cashierA'));
  // A stock change without its move, with a move for another amount, or reusing an old move.
  denied(await patch('products/counted',{stock:999},'cashierA'));
  denied(await commit([['stockMoves/m2',move('m2',17,20)],['products/counted',adjust('m2',99)]],'cashierA'));
  denied(await commit([['products/counted',adjust('m1',30)]],'cashierA'));
  // Moves are append-only, must add up, and only the owner reads them.
  denied(await commit([['stockMoves/m3',move('m3',17,20,{delta:50})],['products/counted',adjust('m3',20)]],'cashierA'));
  denied(await patch('stockMoves/m1',{reason:'other'},'cashierA'));
  denied(await request('/stockMoves/m1','cashierA'));
  allowed(await request('/stockMoves/m1','ownerA'));
  denied(await request('/stockMoves/m1','ownerB'));
});
test('cost prices are owner-only',async()=>{
  allowed(await put('products/costed',{storeCode:'A',name:'Glue',price:2,stock:4,barcode:'777'}));
  allowed(await put('productCosts/costed',{storeCode:'A',cost:1.2},'ownerA'));
  allowed(await request('/productCosts/costed','ownerA'));
  denied(await request('/productCosts/costed','cashierA'));
  denied(await request('/productCosts/costed','ownerB'));
  denied(await put('productCosts/costed',{storeCode:'A',cost:0.1},'cashierA'));
  denied(await put('productCosts/costed',{storeCode:'A',cost:-1},'ownerA'));
  denied(await put('productCosts/productB',{storeCode:'A',cost:1},'ownerA'));
});
test('cashier receipts must add up and carry a real sale time',async()=>{
  const saleWith=(id,extra)=>[['sales/'+id,receipt(id,'cashierA',{productIds:[],...extra})]];
  allowed(await commit(saleWith('ok-receipt',{}),'cashierA'));
  denied(await commit(saleWith('zero-total',{total:0}),'cashierA'));
  denied(await commit(saleWith('big-discount',{discount:5,total:0}),'cashierA'));
  denied(await commit(saleWith('negative-discount',{discount:-1,total:3}),'cashierA'));
  denied(await commit(saleWith('backdated',{createdAt:new Date(Date.now()-40*86400000)}),'cashierA'));
  denied(await commit(saleWith('future',{createdAt:new Date(Date.now()+86400000)}),'cashierA'));
  denied(await commit(saleWith('fake-sync',{$serverTime:[],syncedAt:new Date()}),'cashierA'));
  // Offline sales may sync later within the 30-day window.
  allowed(await commit(saleWith('offline-receipt',{createdAt:new Date(Date.now()-3*86400000)}),'cashierA'));
});

test('users edit their own phone and confirmed email, nothing else',async()=>{
  allowed(await patch('users/cashierA',{phone:'+973 3300 0000'},'cashierA'));
  allowed(await patch('users/cashierA',{phone:''},'cashierA'));
  denied(await patch('users/cashierA',{phone:'1'.repeat(21)},'cashierA'));
  denied(await patch('users/cashierA',{phone:12345},'cashierA'));
  // The email must be the one Firebase Auth confirmed for this sign-in.
  allowed(await patch('users/cashierA',{email:'cashierA@test.invalid'},'cashierA'));
  denied(await patch('users/cashierA',{email:'ownerA@test.invalid'},'cashierA'));
  // Nobody edits another person's phone or email.
  denied(await patch('users/cashierA',{phone:'+973 1'},'cashierB'));
  denied(await patch('users/ownerA',{email:'cashierA@test.invalid'},'cashierA'));
});

test('bundle offers: only the owner starts them, and receipts may record them',async()=>{
  allowed(await put('users/editorA',{uid:'editorA',role:'cashier',storeCode:'A',isActive:true,status:'active',canEditProducts:true,canAdjustStock:true}));
  allowed(await put('products/offerSlowA',{storeCode:'A',name:'Ruler',price:0.4,stock:5,barcode:'999'}));
  const offer={offerActive:true,offerWithId:'productA',offerWithName:'Pen',offerPercent:20};
  // Even a cashier allowed to edit products cannot start or change an offer.
  denied(await patch('products/offerSlowA',offer,'editorA'));
  denied(await patch('products/offerSlowA',{offerPercent:50},'cashierA'));
  allowed(await patch('products/offerSlowA',offer,'ownerA'));
  denied(await patch('products/offerSlowA',{offerActive:false},'editorA'));
  allowed(await patch('products/offerSlowA',{offerActive:false},'ownerA'));
  // A cashier receipt carries the offer's share of the discount; totals must still add up.
  const withOffer=receipt('offer-receipt','cashierA',{productIds:[],subtotal:2,discount:0.2,total:1.8,offerDiscount:0.2,offers:['Pen + Ruler 20%']});
  allowed(await commit([['sales/offer-receipt',withOffer]],'cashierA'));
  const wrong=receipt('offer-wrong','cashierA',{productIds:[],subtotal:2,discount:0.2,total:2,offerDiscount:0.2});
  denied(await commit([['sales/offer-wrong',wrong]],'cashierA'));
});

test('VAT invoice details: owner only, 15-digit number required when registered',async()=>{
  const ok={vatRegistered:true,vatNumber:'123456789012345',storeAddress:'Seef Mall, Shop 12, Manama, Kingdom of Bahrain'};
  allowed(await patch('stores/A',ok,'ownerA'));
  denied(await patch('stores/A',ok,'cashierA'));
  denied(await patch('stores/B',ok,'ownerA'));
  denied(await patch('stores/A',{vatRegistered:true,vatNumber:'12345'},'ownerA'));
  denied(await patch('stores/A',{vatRegistered:true,vatNumber:''},'ownerA'));
  denied(await patch('stores/A',{vatNumber:'12345678901234X'},'ownerA'));
  denied(await patch('stores/A',{storeAddress:'x'.repeat(201)},'ownerA'));
  denied(await patch('stores/A',{vatRegistered:'yes'},'ownerA'));
  // Not registered: no number needed.
  allowed(await patch('stores/A',{vatRegistered:false,vatNumber:''},'ownerA'));
});

test('existing apps keep working: store settings saved without the new VAT fields',async()=>{
  // What the current production app writes: no VAT fields at all.
  allowed(await patch('stores/B',{storeName:'Demo B',benefitNumber:'33000000'},'ownerB'));
  allowed(await patch('stores/B',{benefitQrBase64:'aGVsbG8='},'ownerB'));
  // Cashiers still cannot change store settings, old fields or new.
  denied(await patch('stores/B',{benefitNumber:'1'},'cashierB'));
  denied(await patch('stores/B',{vatRegistered:false},'cashierB'));
});

// ---------- Unknown barcodes: shared catalogue details, owner policy, requests ----------
const del=(path,uid)=>request('/'+path,uid,{method:'DELETE'});
test('shared catalogue keeps brand, size, description and source; a shared price carries its time',async()=>{
  allowed(await commit([['catalog/6281036002100',{name:"Lay's",category:'Chips',brand:"Lay's",size:'21 g',description:'Potato chips',source:'Open Food Facts',price:0.1,contributedBy:'store',$serverTime:['createdAt','priceAt']}]],'ownerA'));
  denied(await commit([['catalog/6281036002200',{name:'Chips',category:'',priceAt:new Date(),contributedBy:'store',$serverTime:['createdAt']}]],'ownerA'));
  denied(await commit([['catalog/6281036002300',{name:'Chips',category:'',brand:'x'.repeat(61),contributedBy:'store',$serverTime:['createdAt']}]],'ownerA'));
  denied(await commit([['catalog/6281036002400',{name:'Chips',category:'',description:'x'.repeat(301),contributedBy:'store',$serverTime:['createdAt']}]],'ownerA'));
  // Fill-in only: a missing brand may be added, an existing one never changes.
  allowed(await shareName('6281036002500',{name:'Shampoo',category:'',contributedBy:'ownerB'},'ownerB'));
  allowed(await patch('catalog/6281036002500',{brand:'Pantene',size:'400 ml'},'cashierA'));
  denied(await patch('catalog/6281036002500',{brand:'Other'},'ownerA'));
  denied(await patch('catalog/6281036002100',{size:'50 g'},'ownerB'));
});
test('only the owner sets the unknown-product policy, within limits',async()=>{
  allowed(await patch('stores/A',{sharedPriceSales:true,sharedPriceMax:1},'ownerA'));
  denied(await patch('stores/A',{sharedPriceSales:true,sharedPriceMax:1},'cashierA'));
  denied(await patch('stores/A',{sharedPriceMax:5000},'ownerA'));
  denied(await patch('stores/A',{sharedPriceMax:-1},'ownerA'));
  denied(await patch('stores/A',{sharedPriceSales:'yes'},'ownerA'));
  denied(await patch('stores/B',{sharedPriceSales:true},'ownerA'));
});
test('cashiers cannot create permanent inventory even under a shared-price policy',async()=>{
  allowed(await patch('stores/A',{sharedPriceSales:true,sharedPriceMax:1},'ADMIN'));
  allowed(await patch('stores/B',{sharedPriceSales:false,sharedPriceMax:1},'ADMIN'));
  allowed(await put('catalog/6281036003000',{name:"Lay's Salt",category:'Chips',price:0.3,contributedBy:'store'}));
  allowed(await put('catalog/6281036003100',{name:'Perfume',category:'Beauty',price:12,contributedBy:'store'}));
  allowed(await put('catalog/6281036003200',{name:'Pen',category:'',contributedBy:'store'}));
  const item=(code,extra={},store='A',by='cashierA')=>[`products/${store}_${code}`,{storeCode:store,barcode:code,name:'Item',price:0.3,stock:0,minStock:0,addedVia:'shared_price',addedBy:by,$serverTime:['createdAt'],...extra}];
  denied(await commit([item('6281036003000',{price:0.25})],'cashierA'));          // not the shared price
  denied(await commit([item('6281036003000',{stock:5})],'cashierA'));             // invents stock
  denied(await commit([item('6281036003100',{price:12})],'cashierA'));            // above the owner's maximum
  denied(await commit([item('6281036003200',{price:0.3})],'cashierA'));           // no shared price at all
  denied(await commit([item('6281036009900')],'cashierA'));                      // not in the shared catalogue
  denied(await commit([item('6281036003000',{addedBy:'ownerA'})],'cashierA'));    // forged author
  denied(await commit([item('6281036003000',{},'B','cashierB')],'cashierB'));     // store B has the policy off
  denied(await commit([item('6281036003000',{},'A','cashierB')],'cashierB'));     // another store's cashier
  denied(await commit([[`products/X_6281036003000`,item('6281036003000')[1]]],'cashierA')); // id must be store_barcode
  denied(await commit([item('6281036003000',{cost:0.1})],'cashierA'));            // extra private field
  denied(await commit([item('6281036003000')],'cashierA'));
  denied(await commit([item('6281036003000')],'cashierA'));                      // the same barcode twice
  allowed(await patch('stores/A',{sharedPriceSales:false},'ADMIN'));
  allowed(await put('catalog/6281036003300',{name:'Juice',category:'',price:0.2,contributedBy:'store'}));
  denied(await commit([item('6281036003300',{price:0.2})],'cashierA'));          // owner turned it off
});
test('product requests: a cashier asks, only the owner lists and removes them',async()=>{
  const ask=(code,uid,extra={},store='A')=>commit([[`productRequests/${store}_${code}`,{storeCode:store,barcode:code,name:'Shampoo',brand:'Pantene',requestedBy:uid,$serverTime:['createdAt'],...extra}]],uid);
  allowed(await ask('6281036004000','cashierA'));
  denied(await ask('6281036004000','cashierA'));                    // already pending
  denied(await ask('6281036004100','cashierA',{requestedBy:'ownerA'}));
  denied(await ask('6281036004200','cashierB',{},'A'));             // another store
  denied(await ask('6281036004300','cashierA',{price:0.5}));        // a request can never set a price
  denied(await ask('SKU-1','cashierA'));
  allowed(await query('productRequests',{storeCode:'A'},'ownerA'));
  denied(await query('productRequests',{storeCode:'A'},'cashierA'));
  denied(await query('productRequests',{storeCode:'A'},'ownerB'));
  allowed(await request('/productRequests/A_6281036004000','cashierA'));
  denied(await request('/productRequests/A_6281036004000','cashierB'));
  denied(await del('productRequests/A_6281036004000','cashierA'));
  denied(await del('productRequests/A_6281036004000','ownerB'));
  allowed(await del('productRequests/A_6281036004000','ownerA'));
});


test('reference receipts require exact owner-authorized price and never inventory writes', async()=>{
  allowed(await patch('stores/A',{sharedPriceSales:true,sharedPriceMax:1},'ownerA'));
  allowed(await put('catalog/12340001',{name:'Notebook',category:'Stationery',price:0.7,contributedBy:'store'}));
  const make=(id,extra={})=>receipt(id,'cashierA',{
    items:[{productId:'unknown_A_12340001',barcode:'12340001',name:'Notebook',price:0.7,quantity:2}],
    productIds:['unknown_A_12340001'],subtotal:1.4,total:1.4,
    unknownBarcode:'12340001',pricingPolicy:'owner_authorized_shared_reference',...extra});
  allowed(await commit([['sales/reference-ok',make('reference-ok')]],'cashierA'));
  allowed(await request('/sales/reference-ok','ownerA'));
  const inventory=await request('/products/unknown_A_12340001','ownerA'); assert.equal(inventory.status,404);
  denied(await commit([['sales/reference-fake',make('reference-fake',{items:[{productId:'unknown_A_12340001',barcode:'12340001',name:'Notebook',price:0.1,quantity:2}],subtotal:0.2,total:0.2})]],'cashierA'));
  denied(await commit([['sales/reference-discount',make('reference-discount',{discount:0.2,total:1.2})]],'cashierA'));
  denied(await commit([['sales/reference-spoof',make('reference-spoof',{storeCode:'B'})]],'cashierA'));
  denied(await patch('sales/reference-ok',{total:0.1},'cashierA'));
  allowed(await patch('stores/A',{sharedPriceSales:false},'ownerA'));
  denied(await commit([['sales/reference-disabled',make('reference-disabled')]],'cashierA'));
});

test('catalogue privacy: no identity, stock, costs or store settings may be published',async()=>{
  for(const extra of [{storeCode:'A'},{ownerUid:'ownerA'},{email:'ownerA@test.invalid'},{cost:0.1},{stock:2}]) {
    denied(await shareName('12340999',{name:'Private',category:'',contributedBy:'store',...extra},'ownerA'));
  }
  denied(await shareName('12340999',{name:'Private',category:'',contributedBy:'ownerA'},'cashierA'));
  denied(await shareName('12340999',{name:'Fake price',category:'',price:99,contributedBy:'store'},'cashierB'));
  allowed(await put('catalog/12340998',{name:'Legacy private',category:'',contributedBy:'ownerA'}));
  denied(await request('/catalog/12340998','ownerB'));
});


test('atomic barcode claims prevent duplicate creates and unauthorized claim changes', async()=>{
  const product={storeCode:'A',name:'Book',price:1,stock:4,barcode:'12348888'};
  const claim={storeCode:'A',barcode:'12348888',productId:'unique-book'};
  denied(await put('products/without-claim',product,'ownerA'));
  allowed(await commit([['products/unique-book',product],['productBarcodes/A_12348888',claim]],'ownerA'));
  denied(await commit([['products/duplicate-book',product],['productBarcodes/A_12348888',{...claim,productId:'duplicate-book'}]],'ownerA'));
  denied(await patch('products/unique-book',{barcode:'12348889'},'ownerA'));
  denied(await patch('productBarcodes/A_12348888',{productId:'other'},'cashierB'));
  denied(await request('/productBarcodes/A_12348888','ownerB'));
  denied(await del('productBarcodes/A_12348888','ownerA'));
  // A barcode edit remains available when its new claim accompanies the product.
  allowed(await commit([['products/unique-book',{barcode:'12348889',$mask:true}],['productBarcodes/A_12348889',{storeCode:'A',barcode:'12348889',productId:'unique-book'}]],'ownerA'));
});

test('five-product import batches remain within rule access limits', async()=>{
  const writes=[];
  for(let i=0;i<5;i++) {
    const code='1234777'+i, id='import-'+i;
    writes.push(['products/'+id,{storeCode:'A',barcode:code,name:'Imported '+i,price:1,stock:3}]);
    writes.push(['productBarcodes/A_'+code,{storeCode:'A',barcode:code,productId:id}]);
  }
  allowed(await commit(writes,'ownerA'));
});


test('approval requests cannot invent the shared price shown to the owner', async()=>{
  allowed(await put('catalog/12346666',{name:'Notebook',category:'School',price:0.8,contributedBy:'store'}));
  const ask=price=>commit([['productRequests/A_12346666',{storeCode:'A',barcode:'12346666',name:'Notebook',sharedPrice:price,requestedBy:'cashierA',$serverTime:['createdAt']}]],'cashierA');
  denied(await ask(0.2));
  denied(await ask(100));
  allowed(await ask(0.8));
});

test('profile photo: own JPEG only, bounded size, role/store permissions remain locked',async()=>{
  const photo='data:image/jpeg;base64,/9j/AAAA';
  allowed(await patch('users/cashierA',{photo},'cashierA'));
  const user=await request('/users/cashierA','cashierA');allowed(user);
  assert.equal(user.body.fields.photo.stringValue,photo);
  assert.equal(user.body.fields.role.stringValue,'cashier');
  denied(await patch('users/cashierA',{photo:photo+'A'},'cashierB'));
  denied(await patch('users/cashierA',{photo:photo+'A'},'ownerA'));
  denied(await patch('users/cashierA',{photo,role:'owner'},'cashierA'));
  denied(await patch('users/cashierA',{photo:'https://evil.example/image.jpg'},'cashierA'));
  denied(await patch('users/cashierA',{photo:'data:image/svg+xml;base64,AAAA'},'cashierA'));
  denied(await patch('users/cashierA',{photo:'data:image/jpeg;base64,'+'A'.repeat(120001)},'cashierA'));
  denied(await patch('users/cashierA',{photo},null));
  allowed(await request('/users/cashierA','cashierA',{method:'PATCH',data:{fields:{}},query:'?updateMask.fieldPaths=photo'}));
  assert.equal((await request('/users/cashierA','cashierA')).body.fields.photo,undefined);
});
