const {test}=require('node:test');
const assert=require('node:assert/strict');
const {recipientAllowed,pushPayload}=require('./policy.cjs');
test('current membership and both preferences are mandatory',()=> {
 const settings={enabled:true,remote:true,kinds:{expense:true}};
 assert.equal(recipientAllowed('a',['a'],settings,'expense'),true);
 assert.equal(recipientAllowed('a',['b'],settings,'expense'),false);
 assert.equal(recipientAllowed('a',['a'],{...settings,remote:false},'expense'),false);
 assert.equal(recipientAllowed('a',['a'],{...settings,enabled:false},'expense'),false);
 assert.equal(recipientAllowed('a',['a'],settings,'shopping'),false);
 assert.equal(recipientAllowed('a',['a'],settings,'unknown'),false);
});
test('data-only push has no financial text and stable client dedup ID',()=> {
 const p=pushPayload('a','home','expense','home/expenses/one/0');
 assert.equal(p.notification,undefined);assert.equal(p.data.eventId,'home/expenses/one/0');
 assert.deepEqual(Object.keys(p.data).sort(),['eventId','groupId','kind','uid']);
});
