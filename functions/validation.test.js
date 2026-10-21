const {test}=require('node:test');
const assert=require('node:assert/strict');
const {codeHash,matchesCode}=require('./validation');
test('OTP is bound to account and email, never stored in plaintext',()=>{
  const hash=codeHash('a','a@example.com','012345','secret');
  assert.notEqual(hash,'012345');
  assert.ok(matchesCode(hash,codeHash('a','a@example.com','012345','secret')));
  assert.equal(matchesCode(hash,codeHash('b','a@example.com','012345','secret')),false);
  assert.equal(matchesCode(hash,codeHash('a','b@example.com','012345','secret')),false);
  assert.equal(matchesCode(hash,codeHash('a','a@example.com','012346','secret')),false);
});

test('Expired, undelivered and exhausted OTPs cannot verify an account',()=>{
  const {codeVerdict}=require('./validation');
  const data={email:'a@example.com',delivered:true,expiresAt:2000,attempts:0,hash:codeHash('a','a@example.com','012345','secret')};
  const verify=(d,now=1000)=>codeVerdict(d,'a','a@example.com','012345','secret',now);
  assert.equal(verify(data),'valid');
  assert.equal(verify(data,2000),'expired');
  assert.equal(verify({...data,attempts:5}),'locked');
  assert.equal(verify({...data,delivered:false}),'expired');
  assert.equal(verify({...data,email:'other@example.com'}),'expired');
  assert.equal(verify({...data,hash:codeHash('a','a@example.com','111111','secret')}),'invalid');
});

