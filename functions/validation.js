const crypto = require('node:crypto');
function codeHash(uid, email, code, secret) {
  return crypto.createHmac('sha256', secret).update(`${uid}:${email}:${code}`).digest('hex');
}
function matchesCode(expected, actual) {
  return typeof expected === 'string' && typeof actual === 'string' &&
    expected.length === actual.length && crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(actual));
}

function codeVerdict(data, uid, email, code, secret, now) {
  if (!data || !data.delivered || data.email !== email || now >= data.expiresAt) return 'expired';
  if (data.attempts >= 5) return 'locked';
  return matchesCode(data.hash, codeHash(uid, email, code, secret)) ? 'valid' : 'invalid';
}
module.exports = { codeHash, matchesCode, codeVerdict };


