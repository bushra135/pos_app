'use strict';
const {test,after}=require('node:test');const assert=require('node:assert/strict');const http=require('node:http');
const {initializeApp,deleteApp}=require('firebase-admin/app');const {getAuth}=require('firebase-admin/auth');const {getFirestore}=require('firebase-admin/firestore');const {createCheckout}=require('../checkout.cjs');const {createHandler}=require('../index.cjs');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:9197');assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:9184');
const app=initializeApp({projectId:'demo-shoppad-security'},'authenticated-http'),auth=getAuth(app),db=getFirestore(app);
after(()=>deleteApp(app));
test('real Auth emulator token passes SDK verification; forged token cannot save',async()=>{
 const uid='http-cashier';await auth.createUser({uid,email:'http-cashier@example.invalid',emailVerified:true,password:'Strong!password123'}).catch(e=>{if(e.code!=='auth/uid-already-exists')throw e;});
 await db.doc('users/'+uid).set({storeCode:'HTTP',role:'cashier',status:'active',isActive:true});await db.doc('stores/HTTP').set({ownerUid:'http-owner',storeName:'HTTP store',vatRegistered:false});await db.doc('products/http-pen').set({storeCode:'HTTP',name:'Pen',barcode:'123',price:2,stock:5});
 const custom=await auth.createCustomToken(uid);const signIn=await fetch('http://127.0.0.1:9197/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:custom,returnSecureToken:true})});const tokens=await signIn.json();assert.ok(tokens.idToken);
 const server=http.createServer(createHandler({checkout:createCheckout(db),verifyToken:t=>auth.verifyIdToken(t,true),origins:['https://shop.example']}));await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{const url='http://127.0.0.1:'+server.address().port+'/checkout';const sale={id:'http-receipt',storeCode:'HTTP',cashierUid:uid,paymentMethod:'Cash',createdAt:new Date().toISOString(),items:[{productId:'http-pen',barcode:'123',name:'Pen',price:2,quantity:1}],total:2};
 const send=token=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(sale)});
 assert.equal((await send('forged')).status,401);assert.equal((await db.doc('sales/http-receipt').get()).exists,false);
 const response=await send(tokens.idToken);assert.equal(response.status,200,JSON.stringify(await response.clone().json()));assert.equal((await db.doc('products/http-pen').get()).data().stock,4);assert.equal((await send(tokens.idToken)).status,200);assert.equal((await db.doc('products/http-pen').get()).data().stock,4);
 await auth.updateUser(uid,{disabled:true});assert.equal((await send(tokens.idToken)).status,401);assert.equal((await db.doc('products/http-pen').get()).data().stock,4);
 }finally{await new Promise(r=>server.close(r));}
});
