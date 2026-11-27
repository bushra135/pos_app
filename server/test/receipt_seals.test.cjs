'use strict';
const {test}=require('node:test');const assert=require('node:assert/strict');const {generateKeyPairSync}=require('node:crypto');
const {createReceiptSeals}=require('../receipt_seals.cjs');
function signer(id='test'){const keys=generateKeyPairSync('ed25519');return {keys,seals:createReceiptSeals({keyId:id,privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})})};}
const record=()=>({id:'random-id',receiptNumber:'RCPT-random-id',storeName:'Local Shop',createdAt:new Date('2026-11-27T12:00:00.000Z'),subtotal:2,discount:0,total:2,tax:0,items:[{barcode:'123',name:'Pen',price:2,quantity:1}],type:'sale',status:'completed',cashierUid:'private-user',buyerName:'Private Buyer',storeCode:'PRIVATE-STORE'});
const fakeDb=sale=>({doc:path=>{assert.equal(path,'sales/random-id');return {get:async()=>({data:()=>sale})};}});
test('server seal verifies and public output excludes buyer, cashier and store IDs',async()=>{
 const {seals}=signer();const sale=record();sale.receiptSeal=seals.issue(sale);const verified=await seals.check(sale.receiptSeal,fakeDb(sale));assert.equal(verified.valid,true);assert.equal(verified.totalFils,2000);assert.deepEqual(Object.keys(verified).sort(),['currency','date','merchant','receipt','totalFils','valid'].sort());const claims=JSON.stringify(seals.inspect(sale.receiptSeal));assert.ok(!claims.includes('Private Buyer')&&!claims.includes('private-user')&&!claims.includes('PRIVATE-STORE'));
});
test('editing amount in the signed token or forging a signature is rejected',()=>{
 const {seals}=signer();const token=seals.issue(record()),[data,signature]=token.split('.'),claims=JSON.parse(Buffer.from(data,'base64url'));claims.total=1;const edited=Buffer.from(JSON.stringify(claims)).toString('base64url')+'.'+signature;assert.equal(seals.inspect(edited),null);assert.equal(seals.inspect(data+'.'+Buffer.alloc(64).toString('base64url')),null);
});
test('changing any signed receipt line or total invalidates the seal',async()=>{
 const {seals}=signer();for(const edit of [sale=>sale.total=0.01,sale=>sale.items[0].quantity=2,sale=>sale.storeName='Other store',sale=>sale.createdAt=new Date('2026-11-28'),sale=>sale.buyerName='Different buyer',sale=>sale.cashierUid='different-cashier']){const sale=record();sale.receiptSeal=seals.issue(sale);edit(sale);assert.equal(await seals.check(sale.receiptSeal,fakeDb(sale)),null);}
});
test('a valid token from another issuer, missing record and unsigned record do not verify',async()=>{
 const a=signer(),b=signer();const sale=record(),token=a.seals.issue(sale);assert.equal(b.seals.inspect(token),null);assert.equal(await a.seals.check(token,fakeDb(undefined)),null);assert.equal(await a.seals.check(token,fakeDb(sale)),null);
});
test('key rotation retains verification of historical signatures with the old public key',()=>{
 const old=signer('old'),newKeys=generateKeyPairSync('ed25519');const current=createReceiptSeals({keyId:'new',privateKey:newKeys.privateKey.export({type:'pkcs8',format:'pem'}),publicKeys:{old:old.keys.publicKey.export({type:'spki',format:'pem'})}});assert.ok(current.inspect(old.seals.issue(record())));assert.equal(old.seals.inspect(current.issue(record())),null);
});
test('malformed, oversized and attacker-selected document paths are rejected before lookup',async()=>{
 const {seals}=signer();const db={doc:()=>{throw Error('must not access Firestore');}};for(const token of [null,'bad','A'.repeat(5000),Buffer.from('{"id":"../private"}').toString('base64url')+'.AAAA'])assert.equal(await seals.check(token,db),null);
});
