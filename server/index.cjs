'use strict';
const http=require('node:http');
const {initializeApp,applicationDefault}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {getFirestore}=require('firebase-admin/firestore');
const {createCheckout,CheckoutError}=require('./checkout.cjs');
function createHandler({checkout,verifyToken,origins=[]}){
 return async(req,res)=>{
  const origin=req.headers.origin;
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
  if(origin){if(!origins.includes(origin)){res.writeHead(403,headers);res.end('{"error":"forbidden"}');return;}headers['Access-Control-Allow-Origin']=origin;headers.Vary='Origin';}
  const send=(status,body)=>{res.writeHead(status,headers);res.end(JSON.stringify(body));};
  if(req.url!=='/checkout')return send(404,{error:'not-found'});
  if(req.method==='OPTIONS'){res.writeHead(204,{...headers,'Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'Authorization, Content-Type'});return res.end();}
  if(req.method!=='POST')return send(405,{error:'method-not-allowed'});
  if(!/^application\/json(?:;|$)/i.test(req.headers['content-type']??''))return send(415,{error:'unsupported-media-type'});
  const bearer=/^Bearer (\S+)$/.exec(req.headers.authorization??'');if(!bearer)return send(401,{error:'unauthorized'});
  let identity;try{identity=await verifyToken(bearer[1]);}catch(_){return send(401,{error:'unauthorized'});}
  let size=0,parts=[];
  try{
   for await(const part of req){size+=part.length;if(size>512*1024)return send(413,{error:'request-too-large'});parts.push(part);}
   let body;try{body=JSON.parse(Buffer.concat(parts).toString('utf8'));}catch(_){return send(400,{error:'invalid-json'});}
   const result=await checkout(body,identity);return send(200,result);
  }catch(error){
   if(error instanceof CheckoutError){const status={unauthorized:401,forbidden:403,conflict:409}[error.code]??400;return send(status,{error:error.code,message:error.message});}
   // Never return SDK internals, credentials, or document data to the caller.
   return send(503,{error:'unavailable'});
  }
 };
}
if(require.main===module){
 if(process.env.NODE_ENV==='production'&&!process.env.GCLOUD_PROJECT)throw Error('Set GCLOUD_PROJECT explicitly');
 if((process.env.FIRESTORE_EMULATOR_HOST||process.env.FIREBASE_AUTH_EMULATOR_HOST)&&process.env.NODE_ENV==='production')throw Error('Emulators must not be configured in production');
 initializeApp({credential:applicationDefault(),projectId:process.env.GCLOUD_PROJECT});
 const checkout=createCheckout(getFirestore()),origins=(process.env.SHOPPAD_ALLOWED_ORIGINS??'').split(',').map(s=>s.trim()).filter(Boolean);
 if(!origins.length)throw Error('Set SHOPPAD_ALLOWED_ORIGINS to the exact frontend origins');
 const server=http.createServer(createHandler({checkout,origins,verifyToken:token=>getAuth().verifyIdToken(token,true)}));
 server.requestTimeout=20000;server.headersTimeout=15000;server.listen(Number(process.env.PORT??8080),'0.0.0.0');
}
module.exports={createHandler};
