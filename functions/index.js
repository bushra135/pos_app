const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret, defineString} = require('firebase-functions/params');

const {initializeApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore} = require('firebase-admin/firestore');
const crypto = require('node:crypto');
const {codeHash, codeVerdict} = require('./validation');
initializeApp();
const db = getFirestore();
const mailKey = defineSecret('RESEND_API_KEY');
const otpKey = defineSecret('OTP_HASH_KEY');

const mailFrom = defineString('SHOPPAD_EMAIL_FROM');

const options = {region: 'europe-west1'};
function user(request, verified = false) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to continue.');
  if (verified && !request.auth.token.email_verified) throw new HttpsError('permission-denied', 'Verify your email first.');
  return request.auth.uid;
}
async function jsonFetch(url, options) {
  const response = await fetch(url, {...options, signal: AbortSignal.timeout(20000)});
  if (!response.ok) throw new HttpsError('unavailable', 'The service is unavailable. Please try again.');
  return response.json();
}
exports.requestEmailCode = onCall({...options, secrets:[mailKey, otpKey]}, async request => {
  const uid = user(request);
  const account = await getAuth().getUser(uid);
  if (account.emailVerified) return {verified:true};
  if (!account.email) throw new HttpsError('failed-precondition', 'This account has no email.');
  const code = crypto.randomInt(0,1000000).toString().padStart(6,'0');
  const ref = db.collection('_emailCodes').doc(uid);
  const now = Date.now();
  await db.runTransaction(async tx => {
    const old = (await tx.get(ref)).data();
    if (old && now - old.sentAt < 60000) throw new HttpsError('resource-exhausted', 'Wait one minute before requesting another code.');
    if (old && now - old.windowStart < 3600000 && old.sentCount >= 6) throw new HttpsError('resource-exhausted', 'Too many emails requested. Try again later.');
    const sameWindow = old && now - old.windowStart < 3600000;
    tx.set(ref,{email:account.email, hash:codeHash(uid,account.email,code,otpKey.value()), sentAt:now, expiresAt:now+600000, attempts:0,
      windowStart:sameWindow?old.windowStart:now, sentCount:sameWindow?old.sentCount+1:1, delivered:false});
  });
  try {
    await jsonFetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${mailKey.value()}`,'Content-Type':'application/json'},
      body:JSON.stringify({from:`ShopPad <${mailFrom.value()}>`,to:[account.email],subject:'ShopPad — رمز التحقق من البريد',
        text:`ShopPad\nرمز التحقق الخاص بك: ${code}\nصالح لمدة 10 دقائق. لا تشاركه مع أحد.`,
        html:`<div dir="rtl" style="font-family:Arial;background:#f5f7fb;padding:32px"><div style="max-width:480px;margin:auto;background:white;padding:32px;border-radius:20px"><h1 style="color:#175b80">ShopPad</h1><h2>تأكيد بريدك الإلكتروني</h2><p>أدخل الرمز التالي داخل تطبيق ShopPad:</p><div dir="ltr" style="font-size:36px;letter-spacing:10px;font-weight:bold">${code}</div><p>الرمز صالح لمدة 10 دقائق. لا تشاركه مع أي شخص.</p><p>إذا لم تطلب هذا الرمز، تجاهل الرسالة.</p></div></div>`})});
    await db.runTransaction(async tx => {const current=(await tx.get(ref)).data(); if(current?.sentAt===now) tx.update(ref,{delivered:true});});
  } catch(error) {
    // Keep the request rate limit, but never accept a code that failed delivery.
    throw error;
  }
  return {expiresIn:600,retryAfter:60};
});
exports.verifyEmailCode = onCall({...options,secrets:[otpKey]},async request => {
  const uid=user(request);
  const code=String(request.data?.code ?? '');
  if (!/^\d{6}$/.test(code)) throw new HttpsError('invalid-argument','Enter the six-digit code.');
  const account=await getAuth().getUser(uid);
  if(account.emailVerified) return {verified:true};
  const ref=db.collection('_emailCodes').doc(uid);
  const result=await db.runTransaction(async tx=>{
    const data=(await tx.get(ref)).data();
    const verdict=codeVerdict(data,uid,account.email,code,otpKey.value(),Date.now());
    if(verdict==='invalid') tx.update(ref,{attempts:data.attempts+1});
    // Preserve the valid hash until Auth succeeds, so transient failure is retryable.
    return verdict;
  });
  if(result!=='valid') throw new HttpsError(result==='locked'?'resource-exhausted':'invalid-argument',
    result==='expired'?'Code expired. Request a new code.':result==='locked'?'Too many attempts. Request a new code.':'Incorrect verification code.');
  await getAuth().updateUser(uid,{emailVerified:true});
  await ref.delete();
  return {verified:true};
});

