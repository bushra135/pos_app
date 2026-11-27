'use strict';
const {createPrivateKey,createPublicKey,createHash,randomBytes,sign,verify}=require('node:crypto');
const stable=value=>JSON.stringify(value,(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
const fils=n=>Math.round(n*1000);
function sealSnapshot(sale){
 const date=sale.createdAt?.toDate?sale.createdAt.toDate():new Date(sale.createdAt);
 return {id:sale.id,ref:sale.receiptNumber,invoice:sale.invoiceNumber??'',merchant:sale.storeName,date:date.toISOString(),currency:'BHD',subtotal:fils(sale.subtotal),discount:fils(sale.discount),tax:fils(sale.tax),total:fils(sale.total),items:sale.items.map(i=>({barcode:i.barcode,name:i.name,price:fils(i.price),quantity:i.quantity,productId:i.productId??'',cost:i.cost??0})),storeCode:sale.storeCode??'',cashierUid:sale.cashierUid??'',cashierName:sale.cashierName??'',payment:sale.paymentMethod??'',buyerName:sale.buyerName??'',buyerAddress:sale.buyerAddress??'',buyerVat:sale.buyerVatNumber??'',storeVat:sale.storeVatNumber??'',address:sale.storeAddress??'',kind:sale.invoiceKind??'',offers:sale.offers??[],corrections:sale.stockCorrections??[]};
}
const digest=sale=>createHash('sha256').update(stable({receipt:sealSnapshot(sale),nonce:sale.receiptSealNonce})).digest('hex');
function createReceiptSeals({keyId,privateKey,publicKeys={}}){
 if(!/^[A-Za-z0-9_-]{1,50}$/.test(keyId??''))throw Error('A receipt signing key ID is required');
 const signingKey=createPrivateKey(privateKey);if(signingKey.asymmetricKeyType!=='ed25519')throw Error('Receipt signing requires an Ed25519 key');
 const keys=new Map(Object.entries(publicKeys).map(([id,pem])=>[id,createPublicKey(pem)]));keys.set(keyId,createPublicKey(signingKey));
 function issue(sale){
  // The nonce stays in the protected receipt, never in the public token.
  // It blinds the hash of private invoice fields against public dictionary guesses.
  sale.receiptSealNonce=randomBytes(32).toString('base64url');
  const snapshot=sealSnapshot(sale);
  const claims={v:1,kid:keyId,id:snapshot.id,ref:snapshot.ref,merchant:snapshot.merchant,date:snapshot.date,total:snapshot.total,currency:'BHD',hash:digest(sale)};
  const data=Buffer.from(stable(claims));return data.toString('base64url')+'.'+sign(null,data,signingKey).toString('base64url');
 }
 function inspect(token){
  try{
   if(typeof token!=='string'||token.length>4096||!/^[-A-Za-z0-9_]+\.[-A-Za-z0-9_]+$/.test(token))return null;
   const [body,signature]=token.split('.'),data=Buffer.from(body,'base64url'),claims=JSON.parse(data.toString('utf8')),key=keys.get(claims.kid);
   if(!key||key.asymmetricKeyType!=='ed25519'||!verify(null,data,key,Buffer.from(signature,'base64url'))||claims.v!==1||claims.currency!=='BHD'||typeof claims.id!=='string'||!/^[^/]{1,200}$/.test(claims.id)||['.','..'].includes(claims.id)||!Number.isSafeInteger(claims.total)||claims.total<0||typeof claims.merchant!=='string'||typeof claims.ref!=='string'||typeof claims.hash!=='string')return null;
   return claims;
  }catch(_){return null;}
 }
 async function check(token,db){
  const claims=inspect(token);if(!claims)return null;
  const doc=await db.doc('sales/'+claims.id).get(),sale=doc.data();
  if(!sale||sale.type!=='sale'||sale.status!=='completed'||sale.receiptSeal!==token||typeof sale.receiptSealNonce!=='string')return null;
  try{if(digest(sale)!==claims.hash)return null;}catch(_){return null;}
  // No account/store ID, cashier, buyer, product list or cost is returned publicly.
  return {valid:true,receipt:claims.ref,merchant:claims.merchant,date:claims.date,totalFils:claims.total,currency:claims.currency};
 }
 return {issue,inspect,check};
}
module.exports={createReceiptSeals};
