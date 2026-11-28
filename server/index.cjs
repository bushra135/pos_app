'use strict';
const http=require('node:http');
const fs=require('node:fs');
const {createReceiptSeals}=require('./receipt_seals.cjs');
const {initializeApp,applicationDefault}=require('firebase-admin/app');
const {getAuth}=require('firebase-admin/auth');
const {getFirestore}=require('firebase-admin/firestore');
const {createCheckout,CheckoutError}=require('./checkout.cjs');
function createHandler({checkout,verifyToken,origins=[],verifyReceipt}){
 return async(req,res)=>{
  const origin=req.headers.origin;
  const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
  if(origin){if(!origins.includes(origin)){res.writeHead(403,headers);res.end('{"error":"forbidden"}');return;}headers['Access-Control-Allow-Origin']=origin;headers.Vary='Origin';}
  const send=(status,body)=>{res.writeHead(status,headers);res.end(JSON.stringify(body));};
  const url=new URL(req.url,'http://localhost');
  if(url.pathname==='/verify'&&verifyReceipt){
   // JSON verification from Flutter Web requires a browser preflight first.
   // The exact-origin check above still applies; preflight never reads a receipt.
   if(req.method==='OPTIONS'){res.writeHead(204,{...headers,'Access-Control-Allow-Methods':'GET, POST, OPTIONS','Access-Control-Allow-Headers':'Content-Type'});return res.end();}
   try{
    let token;
    if(req.method==='GET')token=url.searchParams.get('token');
    else if(req.method==='POST'){
     let parts=[],size=0;for await(const part of req){size+=part.length;if(size>8192)return send(413,{error:'request-too-large'});parts.push(part);}
     try{token=JSON.parse(Buffer.concat(parts).toString('utf8')).token;}catch(_){return send(400,{valid:false});}
    }else return send(405,{error:'method-not-allowed'});
    const receipt=await verifyReceipt(token);
    if(req.method==='POST')return send(receipt?200:400,receipt??{valid:false});
    const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const details=receipt?`<h1>فاتورة أصلية · Authentic receipt</h1><p>${escape(receipt.merchant)}</p><p>${escape(receipt.receipt)}</p><p dir="ltr">BHD ${(receipt.totalFils/1000).toFixed(3)}</p><p dir="ltr">${escape(receipt.date)}</p><p>قارن المبلغ ورقم الفاتورة بالنسخة التي لديك. رمز QR يمكن نسخه.</p><p>Compare the amount and reference with your receipt. A QR code can be copied.</p>`:'<h1>تعذّر التحقق · Could not verify receipt</h1><p>هذا الرمز غير صالح أو الفاتورة غير متاحة. This code is invalid or the receipt is unavailable.</p>';
    res.writeHead(receipt?200:400,{...headers,'Content-Type':'text/html; charset=utf-8','Referrer-Policy':'no-referrer','X-Frame-Options':'DENY','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"});
    return res.end(`<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ShopPad · Receipt verification</title><style>body{font:18px system-ui;background:#f4f5f7;color:#142c4e;margin:0;padding:24px}main{max-width:560px;margin:48px auto;padding:28px;background:white;border-radius:20px;border-top:6px solid ${receipt?'#1f7a55':'#b4323f'}}h1{font-size:24px}p{overflow-wrap:anywhere;line-height:1.6}</style><main>${details}</main></html>`);
   }catch(_){return send(503,{valid:false,error:'unavailable'});}
  }
  if(url.pathname!=='/checkout'||url.search)return send(404,{error:'not-found'});
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
 const seals=createReceiptSeals({keyId:process.env.SHOPPAD_RECEIPT_KEY_ID,privateKey:fs.readFileSync(process.env.SHOPPAD_RECEIPT_KEY_FILE,'utf8'),publicKeys:JSON.parse(process.env.SHOPPAD_RECEIPT_PUBLIC_KEYS_JSON??'{}')});
 const checkout=createCheckout(getFirestore(),{seals}),origins=(process.env.SHOPPAD_ALLOWED_ORIGINS??'').split(',').map(s=>s.trim()).filter(Boolean);
 if(!origins.length)throw Error('Set SHOPPAD_ALLOWED_ORIGINS to the exact frontend origins');
 const server=http.createServer(createHandler({checkout,origins,verifyToken:token=>getAuth().verifyIdToken(token,true),verifyReceipt:token=>seals.check(token,getFirestore())}));
 server.requestTimeout=20000;server.headersTimeout=15000;server.listen(Number(process.env.PORT??8080),'0.0.0.0');
}
module.exports={createHandler};
