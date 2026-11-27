'use strict';
const {createHash}=require('node:crypto');
const {Timestamp,FieldValue}=require('firebase-admin/firestore');
class CheckoutError extends Error { constructor(code,message){super(message);this.code=code;} }
const reject=(message='The sale details are invalid.')=>{throw new CheckoutError('conflict',message);};
const id=value=>typeof value==='string' && value.length>0 && value.length<=200 && !value.includes('/') && value!=='.' && value!=='..';
const fils=value=>{if(typeof value!=='number'||!Number.isFinite(value)||value<0||value>1e9)reject();return Math.round(value*1000);};
const money=value=>value/1000;
const text=(value,max=200)=>{if(typeof value!=='string'||value.length>max)reject();return value;};
const stable=value=>JSON.stringify(value,(_,v)=>v && !Array.isArray(v) && typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
function intent(raw,uid){
 if(!raw||typeof raw!=='object'||Array.isArray(raw)||!id(raw.id)||!id(raw.storeCode)||raw.cashierUid!==uid||!['Cash','BenefitPay'].includes(raw.paymentMethod))reject();
 if(!Array.isArray(raw.items)||raw.items.length===0||raw.items.length>100)reject();
 const createdAt=new Date(raw.createdAt);if(!Number.isFinite(createdAt.getTime()))reject();
 const items=raw.items.map(line=>{
  if(!line||!id(line.productId)||!Number.isSafeInteger(line.quantity)||line.quantity<=0||line.quantity>1000000)reject();
  return {productId:line.productId,barcode:text(line.barcode),name:text(line.name),price:money(fils(line.price)),quantity:line.quantity};
 });
 const discount=fils(raw.discountAmount??0),offer=fils(raw.offerDiscount??0);
 const vatRate=raw.vatRate??0;if(typeof vatRate!=='number'||!Number.isFinite(vatRate)||vatRate<0||vatRate>100)reject();
 if(raw.correctStockShortages!==undefined && typeof raw.correctStockShortages!=='boolean')reject();
 return {id:raw.id,storeCode:raw.storeCode,cashierUid:uid,paymentMethod:raw.paymentMethod,createdAt:createdAt.toISOString(),items,
 total:money(fils(raw.total)),discountAmount:money(discount),offerDiscount:money(offer),vatRate,correctStockShortages:raw.correctStockShortages===true,
 invoiceNumber:text(raw.invoiceNumber??'',100),invoiceKind:text(raw.invoiceKind??'',40),buyerName:text(raw.buyerName??''),buyerAddress:text(raw.buyerAddress??'',500),buyerVatNumber:text(raw.buyerVatNumber??'',30)};
}
function createCheckout(db){
 return async function checkout(raw,identity){
  if(!identity?.uid||identity.email_verified!==true)throw new CheckoutError('unauthorized','Sign in with a verified account.');
  const sale=intent(raw,identity.uid),digest=createHash('sha256').update(stable(sale)).digest('hex');
  const saleRef=db.collection('sales').doc(sale.id),profileRef=db.collection('users').doc(identity.uid),storeRef=db.collection('stores').doc(sale.storeCode);
  await db.runTransaction(async tx=>{
   const [profileDoc,storeDoc,existing]=await tx.getAll(profileRef,storeRef,saleRef);
   const profile=profileDoc.data(),store=storeDoc.data();
   if(!profile||!store||profile.storeCode!==sale.storeCode||!['owner','cashier'].includes(profile.role)||profile.isActive===false||['disabled','pending','invited'].includes(profile.status)||
    (profile.role==='cashier'&&profile.isActive!==true)||(profile.role==='owner'&&store.ownerUid!==identity.uid))throw new CheckoutError('forbidden','Your account is not authorized to sell for this store.');
   if(existing.exists){
    const previous=existing.data();
    if(previous.requestDigest===digest)return;
    // Keep retries of pre-migration pending receipts idempotent without rewriting them.
    if(!previous.requestDigest && previous.cashierUid===identity.uid && previous.type==='sale'){
     try {const legacy=intent({...previous,createdAt:previous.createdAt.toDate().toISOString()},identity.uid);
      if(stable(legacy)===stable(sale))return;
     }catch(_){}
    }
    reject('This receipt ID already belongs to a different sale.');
   }
   const when=new Date(sale.createdAt),now=Date.now();
   if(when.getTime()>now+600000||when.getTime()<now-30*86400000)reject('The sale date needs review.');
   // Match StoreVat.rate, including existing stores without the registration field.
   const vat=!Object.hasOwn(store,'vatRegistered')||store.vatRegistered===true?10:0;
   if(sale.vatRate!==vat)reject('VAT settings changed. Review this sale.');
   const unknown=sale.items.filter(line=>line.productId.startsWith('unknown_'));
   const remaining=new Map(),corrections=[],products=new Map(),quantities=new Map();
   let items=[],subtotal=0,expectedOffer=0;const offerNames=[];
   if(unknown.length){
    if(sale.items.length!==1||sale.discountAmount!==0||sale.offerDiscount!==0)reject('Sell an unknown product separately without a discount.');
    const line=unknown[0];
    if(!/^(?:[0-9]{8}|[0-9]{12,14})$/.test(line.barcode)||line.productId!==`unknown_${sale.storeCode}_${line.barcode}`)reject();
    const shared=(await tx.get(db.collection('catalog').doc(line.barcode))).data();
    if(store.sharedPriceSales!==true||!shared||shared.contributedBy!=='store'||typeof shared.price!=='number'||shared.price<=0||
      typeof store.sharedPriceMax!=='number'||!Number.isFinite(store.sharedPriceMax)||shared.price>store.sharedPriceMax||fils(line.price)!==fils(shared.price))reject('The owner has not authorized this reference price.');
    items=[{...line,name:String(shared.name??line.name),price:money(fils(shared.price)),subtotal:money(fils(shared.price)*line.quantity)}];
    subtotal=fils(shared.price)*line.quantity;
   }else{
    const ids=[...new Set(sale.items.map(line=>line.productId))];
    const docs=await tx.getAll(...ids.map(key=>db.collection('products').doc(key)));
    const ownerCosts=new Map();
    if(profile.role==='owner'){for(const doc of await tx.getAll(...ids.map(key=>db.collection('productCosts').doc(key)))){const cost=doc.data();if(cost?.storeCode===sale.storeCode&&typeof cost.cost==='number'&&Number.isFinite(cost.cost)&&cost.cost>0)ownerCosts.set(doc.id,cost.cost);}}
    for(const doc of docs){const product=doc.data();if(!product||product.storeCode!==sale.storeCode)reject('A product was removed or belongs to another store.');products.set(doc.id,product);}
    for(const line of sale.items){
     const product=products.get(line.productId),stock=product.stock??product.quantity;
     if(String(product.barcode??'')!==line.barcode||!Number.isSafeInteger(stock)||stock<0||fils(line.price)!==fils(product.price))reject('A product price or stock changed. Review this sale.');
     const price=fils(product.price),part=price*line.quantity;if(!Number.isSafeInteger(part))reject();
     subtotal+=part;quantities.set(line.productId,(quantities.get(line.productId)??0)+line.quantity);
     items.push({...line,name:String(product.name??line.name),price:money(price),subtotal:money(part),...(ownerCosts.has(line.productId)?{cost:ownerCosts.get(line.productId)}:{})});
    }
    for(const [key,quantity] of quantities){
     const product=products.get(key),stock=product.stock??product.quantity,shortage=Math.max(0,quantity-stock);
     if(shortage&&!sale.correctStockShortages)reject(`${product.name}: stock changed. Review this sale.`);
     remaining.set(key,stock+shortage-quantity);
     if(shortage)corrections.push({productId:key,name:String(product.name??''),barcode:String(product.barcode??''),stockBefore:stock,addedQuantity:shortage,quantitySold:quantity,stockAfter:0,reason:'physical_items_sold_exceed_recorded_stock',cashierUid:identity.uid});
     const percent=Math.round(product.offerPercent??0),anchor=product.offerWithId;
     if(product.offerActive===true&&anchor!==key&&typeof anchor==='string'&&percent>=5&&percent<=50){
      const pairs=Math.min(quantity,quantities.get(anchor)??0);
      const amount=Math.round(pairs*fils(product.price)*percent/100);expectedOffer+=amount;
      if(amount>0)offerNames.push(`${products.get(anchor)?.name??product.offerWithName??''} + ${product.name??''} ${percent}%`);
     }
    }
   }
   const discount=fils(sale.discountAmount),offer=fils(sale.offerDiscount);
   // Existing manual discounts remain supported; unit prices are authoritative.
   if(!Number.isSafeInteger(subtotal)||discount>subtotal||offer>discount||offer>expectedOffer)reject('The discount or offer changed. Review this sale.');
   const total=subtotal-discount,tax=vat?Math.round(total*vat/(100+vat)):0;
   if(raw.total!==undefined&&fils(raw.total)!==total)reject('The sale total does not match its items.');
   const saved={...sale,items,createdAt:Timestamp.fromDate(when),syncedAt:FieldValue.serverTimestamp(),storeName:String(store.storeName??''),cashierName:String(profile.fullName??''),
    receiptNumber:`RCPT-${sale.id}`,productIds:[...new Set(items.map(line=>line.productId))],subtotal:money(subtotal),discount:money(discount),total:money(total),tax:money(tax),refund:0,status:'completed',type:'sale',requestDigest:digest};
   const taxInvoice=store.vatRegistered===true&&/^[0-9]{15}$/.test(String(store.vatNumber??''));
   const buyer=sale.buyerName!==''||sale.buyerAddress!==''||sale.buyerVatNumber!=='';
   if(buyer&&(!sale.buyerName||!sale.buyerAddress||!/^[0-9]{15}$/.test(sale.buyerVatNumber)))reject('Buyer invoice details need review.');
   saved.invoiceKind=taxInvoice?(buyer?'full':'simplified'):'receipt';
   saved.storeVatNumber=taxInvoice?String(store.vatNumber):'';saved.storeAddress=String(store.storeAddress??'');
   if(offer>0&&offerNames.length)saved.offers=offerNames;
   if(unknown.length){saved.unknownBarcode=unknown[0].barcode;saved.pricingPolicy='owner_authorized_shared_reference';}
   if(corrections.length){saved.stockCorrections=corrections;saved.stockCorrectionUnits=corrections.reduce((n,row)=>n+row.addedQuantity,0);}
   tx.create(saleRef,saved);
   for(const [key,stock] of remaining){const product=products.get(key);tx.update(db.collection('products').doc(key),{stock,lastSaleId:sale.id,...(product.quantity!==undefined?{quantity:stock}:{}),
    ...(corrections.some(row=>row.productId===key)?{lastStockCorrection:{...corrections.find(row=>row.productId===key),saleId:sale.id,recordedAt:FieldValue.serverTimestamp()}}:{})});}
  });
  return {id:sale.id,status:'completed'};
 };
}
module.exports={createCheckout,CheckoutError};
