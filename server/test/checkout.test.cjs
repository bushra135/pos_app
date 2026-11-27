'use strict';
const {test,before,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {createCheckout}=require('../checkout.cjs');
const host=process.env.FIRESTORE_EMULATOR_HOST;
assert.match(host??'',/^127\.0\.0\.1:9184$/,'Integration tests must use the dedicated local emulator');
const app=initializeApp({projectId:'demo-shoppad-security'},'trusted-checkout-tests'),db=getFirestore(app),checkout=createCheckout(db);
const identity={uid:'cashierA',email_verified:true};
function sale(id,extra={}){return {id,storeCode:'A',storeName:'Store A',cashierUid:'cashierA',cashierName:'Cashier',paymentMethod:'Cash',createdAt:new Date().toISOString(),items:[{productId:'pen',barcode:'123',name:'Pen',price:2,quantity:1}],total:2,...extra};}
async function absent(id){assert.equal((await db.doc('sales/'+id).get()).exists,false);}
async function rejectsUnchanged(input,who=identity){const stock=(await db.doc('products/pen').get()).data().stock;await assert.rejects(()=>checkout(input,who));await absent(input.id);assert.equal((await db.doc('products/pen').get()).data().stock,stock);}
before(async()=>{const r=await fetch(`http://${host}/emulator/v1/projects/demo-shoppad-security/databases/(default)/documents`,{method:'DELETE'});assert.ok(r.ok);});
beforeEach(async()=>{await Promise.all([
 db.doc('users/cashierA').set({role:'cashier',storeCode:'A',isActive:true,status:'active',fullName:'Cashier'}),
 db.doc('users/ownerA').set({role:'owner',storeCode:'A',fullName:'Owner'}),
 db.doc('stores/A').set({ownerUid:'ownerA',storeName:'Store A',vatRegistered:false}),
 db.doc('products/pen').set({storeCode:'A',name:'Pen',barcode:'123',price:2,stock:50,quantity:50}),
 db.doc('products/foreign').set({storeCode:'B',name:'Foreign',barcode:'456',price:2,stock:50}),
 db.doc('catalog/12345678').set({name:'Chips',price:0.2,contributedBy:'store'})
]);});
after(async()=>deleteApp(app));
test('confirmed sale atomically saves server-computed amounts and deducts stock',async()=>{
 const input=sale('confirmed');assert.deepEqual(await checkout(input,identity),{id:input.id,status:'completed'});
 const saved=(await db.doc('sales/confirmed').get()).data();assert.equal(saved.total,2);assert.equal(saved.subtotal,2);assert.equal(saved.cashierName,'Cashier');assert.equal(saved.status,'completed');assert.ok(saved.requestDigest);assert.equal((await db.doc('products/pen').get()).data().stock,49);
});
test('underpriced direct request is rejected with no receipt or stock change',async()=>{const input=sale('underpriced');input.items[0].price=0.01;input.total=0.01;await rejectsUnchanged(input);});
test('unknown item at the second position is rejected even with matching totals',async()=>{
 const input=sale('second-unknown');input.items.push({productId:'unknown_A_12345678',barcode:'12345678',name:'Chips',price:0.01,quantity:1});input.total=2.01;await rejectsUnchanged(input);
});
test('unknown item at the final position in a 100-line request cannot bypass policy',async()=>{
 const input=sale('last-unknown');input.items=Array.from({length:99},()=>({...input.items[0]}));input.items.push({productId:'unknown_A_12345678',barcode:'12345678',name:'Chips',price:0.2,quantity:1});input.total=198.2;await rejectsUnchanged(input);
});
test('owner-authorized reference price confirms without permanent inventory',async()=>{
 await db.doc('stores/A').update({sharedPriceSales:true,sharedPriceMax:1});const input=sale('authorized-unknown',{items:[{productId:'unknown_A_12345678',barcode:'12345678',name:'Chips',price:0.2,quantity:2}],total:0.4});await checkout(input,identity);const saved=(await db.doc('sales/'+input.id).get()).data();assert.equal(saved.unknownBarcode,'12345678');assert.equal(saved.total,0.4);assert.equal((await db.doc('products/unknown_A_12345678').get()).exists,false);assert.equal((await db.doc('products/pen').get()).data().stock,50);
});
test('unknown price, discounts, wrong store, unshared author and disabled policy are rejected',async()=>{
 for(const [index,extra] of [{},{items:[{productId:'unknown_A_12345678',barcode:'12345678',name:'Chips',price:0.01,quantity:1}],total:0.01},{discountAmount:0.1,total:0.1},{storeCode:'B'}].entries()){
 const input=sale('unknown-deny-'+index,{items:[{productId:'unknown_A_12345678',barcode:'12345678',name:'Chips',price:0.2,quantity:1}],total:0.2,...extra});await rejectsUnchanged(input);
 }
 await db.doc('stores/A').update({sharedPriceSales:true,sharedPriceMax:1});await db.doc('catalog/12345678').update({contributedBy:'private-owner'});await rejectsUnchanged(sale('private-shared',{items:[{productId:'unknown_A_12345678',barcode:'12345678',name:'Chips',price:0.2,quantity:1}],total:0.2}));
});
test('foreign products, impersonation, disabled and unverified accounts are rejected',async()=>{
 await rejectsUnchanged(sale('foreign',{items:[{productId:'foreign',barcode:'456',name:'Foreign',price:2,quantity:1}]}));
 await rejectsUnchanged(sale('impersonation',{cashierUid:'ownerA'}));
 await rejectsUnchanged(sale('unverified'),{uid:'cashierA',email_verified:false});
 await db.doc('users/cashierA').update({status:'disabled'});await rejectsUnchanged(sale('disabled'));
});
test('retries, concurrent duplicate IDs and lost acknowledgements never deduct twice',async()=>{
 const input=sale('retry');await Promise.all([checkout(input,identity),checkout(input,identity)]);await checkout(input,identity);assert.equal((await db.doc('products/pen').get()).data().stock,49);
 await assert.rejects(()=>checkout({...input,items:[{...input.items[0],quantity:2}],total:4},identity));assert.equal((await db.doc('products/pen').get()).data().stock,49);
});
test('stale price, forged totals and invented offers are rejected',async()=>{
 await rejectsUnchanged(sale('fake-total',{total:0.01}));await rejectsUnchanged(sale('fake-offer',{discountAmount:1,offerDiscount:1,total:1}));
 await db.doc('products/pen').update({price:3});await rejectsUnchanged(sale('stale'));
});
test('manual discounts and owner bundle offers remain supported',async()=>{
 await checkout(sale('manual',{discountAmount:0.2,total:1.8}),identity);
 await db.doc('products/ruler').set({storeCode:'A',name:'Ruler',barcode:'789',price:1,stock:5,offerActive:true,offerWithId:'pen',offerPercent:20});
 const input=sale('offer',{items:[{productId:'pen',barcode:'123',name:'Pen',price:2,quantity:1},{productId:'ruler',barcode:'789',name:'Ruler',price:1,quantity:1}],discountAmount:0.2,offerDiscount:0.2,total:2.8});await checkout(input,identity);const offerReceipt=(await db.doc('sales/offer').get()).data();assert.equal(offerReceipt.total,2.8);assert.deepEqual(offerReceipt.offers,['Pen + Ruler 20%']);
});
test('VAT-inclusive receipt uses current store registration and correct tax',async()=>{
 await db.doc('stores/A').update({vatRegistered:true,vatNumber:'123456789012345',storeAddress:'Address'});await rejectsUnchanged(sale('stale-vat'));
 await checkout(sale('vat',{vatRate:10}),identity);const saved=(await db.doc('sales/vat').get()).data();assert.equal(saved.tax,0.182);assert.equal(saved.total,2);assert.equal(saved.storeVatNumber,'123456789012345');
});
test('stock shortage requires explicit correction and server derives the audit',async()=>{
 await db.doc('products/pen').update({stock:0,quantity:0});await rejectsUnchanged(sale('shortage'));
 await checkout(sale('correction',{correctStockShortages:true}),identity);const saved=(await db.doc('sales/correction').get()).data();assert.equal(saved.stockCorrectionUnits,1);assert.equal(saved.stockCorrections[0].addedQuantity,1);assert.equal((await db.doc('products/pen').get()).data().stock,0);
});
test('100 distinct products commit in one transaction without rules read limits',async()=>{
 const batch=db.batch(),items=[];for(let i=0;i<100;i++){batch.set(db.doc('products/many-'+i),{storeCode:'A',name:'Item',barcode:String(10000000+i),price:1,stock:2});items.push({productId:'many-'+i,name:'Item',barcode:String(10000000+i),price:1,quantity:1});}await batch.commit();await checkout(sale('many',{items,total:100}),identity);assert.equal((await db.doc('sales/many').get()).data().items.length,100);for(const doc of await db.getAll(...items.map(line=>db.doc('products/'+line.productId))))assert.equal(doc.data().stock,1);
});
test('30-day offline receipts are accepted but future and expired receipts are rejected',async()=>{
 await checkout(sale('offline',{createdAt:new Date(Date.now()-3*86400000).toISOString()}),identity);await rejectsUnchanged(sale('expired',{createdAt:new Date(Date.now()-31*86400000).toISOString()}));await rejectsUnchanged(sale('future',{createdAt:new Date(Date.now()+86400000).toISOString()}));
});

test('owner cost snapshots remain supported and cashier-supplied costs are ignored',async()=>{
 await db.doc('productCosts/pen').set({storeCode:'A',cost:0.5});
 const owner=sale('owner-cost',{cashierUid:'ownerA'});await checkout(owner,{uid:'ownerA',email_verified:true});assert.equal((await db.doc('sales/owner-cost').get()).data().items[0].cost,0.5);
 const cashier=sale('cashier-cost');cashier.items[0].cost=999;await checkout(cashier,identity);assert.equal((await db.doc('sales/cashier-cost').get()).data().items[0].cost,undefined);
});

test('pre-migration confirmed receipt retries remain idempotent',async()=>{
 const input=sale('legacy');const {Timestamp}=require('firebase-admin/firestore');await db.doc('sales/legacy').set({...input,createdAt:Timestamp.fromDate(new Date(input.createdAt)),status:'completed',type:'sale',receiptNumber:'RCPT-legacy'});
 await db.doc('products/pen').update({stock:49});await checkout(input,identity);assert.equal((await db.doc('products/pen').get()).data().stock,49);assert.equal((await db.doc('sales/legacy').get()).data().requestDigest,undefined);
});
test('competing transactions cannot sell the last recorded unit twice without correction',async()=>{
 await db.doc('products/pen').update({stock:1,quantity:1});const results=await Promise.allSettled([checkout(sale('last-one-a'),identity),checkout(sale('last-one-b'),identity)]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal((await db.doc('products/pen').get()).data().stock,0);
});

test('legacy unset VAT configuration keeps the existing rate and plain receipt format',async()=>{
 await db.doc('stores/A').set({ownerUid:'ownerA',storeName:'Legacy store'});await checkout(sale('legacy-vat',{vatRate:10}),identity);const saved=(await db.doc('sales/legacy-vat').get()).data();assert.equal(saved.tax,0.182);assert.equal(saved.invoiceKind,'receipt');
});
test('registered buyer invoices derive their format and retain validated buyer details',async()=>{
 await db.doc('stores/A').update({vatRegistered:true,vatNumber:'123456789012345',storeAddress:'Shop address'});await checkout(sale('buyer-invoice',{vatRate:10,buyerName:'Buyer',buyerAddress:'Buyer address',buyerVatNumber:'543210987654321'}),identity);const saved=(await db.doc('sales/buyer-invoice').get()).data();assert.equal(saved.invoiceKind,'full');assert.equal(saved.buyerVatNumber,'543210987654321');
});

test('only the trusted completed transaction issues a verifiable receipt seal',async()=>{
 const {generateKeyPairSync}=require('node:crypto'),{createReceiptSeals}=require('../receipt_seals.cjs');const keys=generateKeyPairSync('ed25519'),seals=createReceiptSeals({keyId:'integration',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})});
 const signedCheckout=createCheckout(db,{seals});await signedCheckout(sale('signed'),identity);const saved=(await db.doc('sales/signed').get()).data();assert.ok(saved.receiptSeal);const verified=await seals.check(saved.receiptSeal,db);assert.equal(verified.valid,true);assert.equal(verified.totalFils,2000);
 await signedCheckout(sale('signed',{createdAt:saved.createdAt.toDate().toISOString()}),identity);assert.equal((await db.doc('products/pen').get()).data().stock,49);
});
