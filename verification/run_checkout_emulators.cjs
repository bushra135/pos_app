'use strict';
// Explicit demo-only launcher. No production credentials, keys or data are used.
const assert=require('node:assert/strict');
const http=require('node:http');
const {spawn}=require('node:child_process');
const {generateKeyPairSync}=require('node:crypto');
const {initializeApp,deleteApp}=require('../server/node_modules/firebase-admin/app');
const {getAuth}=require('../server/node_modules/firebase-admin/auth');
const {getFirestore}=require('../server/node_modules/firebase-admin/firestore');
const {createCheckout}=require('../server/checkout.cjs');
const {createHandler}=require('../server/index.cjs');
const {createReceiptSeals}=require('../server/receipt_seals.cjs');
async function main(){
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:9184');
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9197');
 assert.equal(process.env.GCLOUD_PROJECT,'demo-shoppad-security');
 const app=initializeApp({projectId:'demo-shoppad-security'},'flutter-emulator-bridge');
 const auth=getAuth(app),db=getFirestore(app);
 let server;
 try{
  const clear=await fetch('http://127.0.0.1:9184/emulator/v1/projects/demo-shoppad-security/databases/(default)/documents',{method:'DELETE'});
  assert.ok(clear.ok);
  const tokens={};
  for(const role of ['cashier','owner']){
   const uid='bridge-'+role;
   await auth.createUser({uid,email:uid+'@example.invalid',emailVerified:true,password:'DemoOnly!password123'});
   const custom=await auth.createCustomToken(uid);
   const response=await fetch('http://127.0.0.1:9197/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:custom,returnSecureToken:true})});
   const body=await response.json();assert.ok(body.idToken);tokens[role]=body.idToken;
   await db.doc('users/'+uid).set({role,storeCode:'BRIDGE',fullName:role,isActive:true,status:'active'});
  }
  await db.doc('stores/BRIDGE').set({ownerUid:'bridge-owner',storeName:'متجر التجربة',vatRegistered:false});
  await db.doc('products/bridge-pen').set({storeCode:'BRIDGE',name:'قلم Pen',barcode:'12345678',price:2,stock:10,quantity:10});
  const keys=generateKeyPairSync('ed25519');
  const seals=createReceiptSeals({keyId:'demo-only',privateKey:keys.privateKey.export({type:'pkcs8',format:'pem'})});
  server=http.createServer(createHandler({checkout:createCheckout(db,{seals}),verifyToken:t=>auth.verifyIdToken(t,true),verifyReceipt:t=>seals.check(t,db),origins:['http://localhost']}));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const endpoint='http://127.0.0.1:'+server.address().port+'/checkout';
  const flutter=process.env.SHOPPAD_FLUTTER_COMMAND||'flutter';
  const result=await new Promise((resolve,reject)=>{
   const child=spawn(flutter,['test','verification/checkout_emulator_test.dart'],{stdio:'inherit',shell:process.platform==='win32',env:{...process.env,SHOPPAD_BRIDGE_ENDPOINT:endpoint,SHOPPAD_BRIDGE_CASHIER_TOKEN:tokens.cashier,SHOPPAD_BRIDGE_OWNER_TOKEN:tokens.owner}});
   child.on('error',reject);child.on('exit',code=>resolve(code));
  });
  assert.equal(result,0,'Flutter-to-server acceptance failed');
  assert.equal((await db.doc('products/bridge-pen').get()).data().stock,7);
  assert.equal((await db.collection('sales').get()).size,3);
  console.log('Verified: 3 signed receipts, stock 7, no duplicate or unauthorized sales.');
 }finally{
  if(server)await new Promise(resolve=>server.close(resolve));
  await deleteApp(app);
 }
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
