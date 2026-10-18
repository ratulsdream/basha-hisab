const { readFileSync } = require('node:fs');
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, collection, writeBatch, arrayUnion, arrayRemove, serverTimestamp, Timestamp } = require('firebase/firestore');
let env;
const code = '0123456789abcdef0123456789abcdef';
const db = uid => env.authenticatedContext(uid, {email: `${uid}@example.com`}).firestore();
const profile = (database, uid) => doc(database, 'users', uid);
const house = database => doc(database, 'households', 'home');
function person(uid) {
  return {uid, email: `${uid}@example.com`, displayName: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp()};
}
function record(uid, id = 'home', inviteCode = code) {
  return {uid, groupId: id, displayName: uid, inviteCode, joinedAt: serverTimestamp()};
}
function pair(batch, database, uid, id = 'home', inviteCode = code) {
  const data = record(uid, id, inviteCode);
  batch.set(doc(database, `users/${uid}/memberships/${id}`), data);
  batch.set(doc(database, `households/${id}/members/${uid}`), data);
}
async function createHome(uid = 'alice', id = 'home', inviteCode = code) {
  const database = db(uid);
  if (!(await getDoc(profile(database, uid))).exists()) await setDoc(profile(database, uid), person(uid));
  const batch = writeBatch(database);
  batch.set(doc(database, 'households', id), {title: 'Our home', maxMembers: 2, memberIds: [uid], memberNames: {[uid]: uid}, currency: 'EUR', inviteCode, createdAt: serverTimestamp()});
  pair(batch, database, uid, id, inviteCode);
  batch.set(doc(database, 'invites', inviteCode), {householdId: id, ownerId: uid, createdAt: serverTimestamp()});
  return batch.commit();
}
async function join(uid, id = 'home', inviteCode = code) {
  const database = db(uid), batch = writeBatch(database);
  batch.update(doc(database, 'households', id), {memberIds: arrayUnion(uid), [`memberNames.${uid}`]: uid});
  pair(batch, database, uid, id, inviteCode);
  return batch.commit();
}
async function leave(uid) {
  const database = db(uid), batch = writeBatch(database);
  const data = (await getDoc(house(database))).data();
  batch.update(house(database), {memberIds: arrayRemove(uid), legacyMemberIds: data.legacyMemberIds ?? data.memberIds});
  batch.delete(doc(database, `users/${uid}/memberships/home`));
  batch.delete(doc(database, `households/home/members/${uid}`));
  return batch.commit();
}
function expense(overrides = {}) {
  return {merchant: 'Market', payer: 'alice', date: Timestamp.fromDate(new Date('2026-10-15T00:00:00Z')), month: '2026-10', itemCount: 0, total: 250, createdBy: 'alice', createdAt: serverTimestamp(), ...overrides};
}
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-bashahisab', firestore: {rules: readFileSync('../../firestore.rules', 'utf8')}});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { if (env) await env.cleanup(); });
test('atomic household creation and one roommate joining succeed', async () => {
  await assertSucceeds(createHome());
  await assertSucceeds(getDoc(doc(db('bob'), 'invites', code)));
  await assertSucceeds(join('bob'));
  const home = await assertSucceeds(getDoc(house(db('bob'))));
  assert.deepEqual(home.data().memberIds, ['alice', 'bob']);
});
test('third roommate is denied; simultaneous joins accept exactly one', async () => {
  await createHome();
  const results = await Promise.allSettled([join('bob'), join('charlie')]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal((await getDoc(house(db('alice')))).data().memberIds.length, 2);
});
test('outsiders and unauthenticated users cannot read expenses or household', async () => {
  await createHome();
  await assertFails(getDoc(house(db('outsider'))));
  await assertFails(getDocs(collection(db('outsider'), 'households/home/expenses')));
  await assertFails(getDoc(house(env.unauthenticatedContext().firestore())));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'invites', code)));
  await assertFails(getDocs(collection(db('outsider'), 'invites')));
});
test('both members see expenses and can record either household payer', async () => {
  await createHome(); await join('bob');
  await assertSucceeds(setDoc(doc(db('alice'), 'households/home/expenses/e1'), expense({payer: 'bob'})));
  await assertSucceeds(setDoc(doc(db('bob'), 'households/home/expenses/e2'), expense({createdBy: 'bob'})));
  const snapshot = await assertSucceeds(getDocs(collection(db('bob'), 'households/home/expenses')));
  assert.equal(snapshot.size, 2);
});
test('forged creator, payer, amount, month, and image fields are denied', async () => {
  await createHome();
  const changes = [{createdBy: 'bob'}, {payer: 'outsider'}, {total: -1}, {total: 1.5}, {month: '2026-09'}, {receiptImage: 'not-allowed'}, {items: [{name: 'Milk', amount: -2}]}, {itemCount: 101}];
  for (let i = 0; i < changes.length; i++) {
    await assertFails(setDoc(doc(db('alice'), `households/home/expenses/bad${i}`), expense(changes[i])));
  }
});
test('personal profile exists independently and supports safe recovery and updates', async () => {
  const database = db('alice');
  await assertSucceeds(setDoc(profile(database, 'alice'), person('alice')));
  await assertSucceeds(setDoc(profile(database, 'alice'), {displayName: 'Alice Smith', updatedAt: serverTimestamp()}, {merge: true}));
  await assertFails(setDoc(profile(db('bob'), 'alice'), person('bob')));
  await assertFails(setDoc(profile(database, 'alice'), {householdId: 'forged'}, {merge: true}));
  await assertFails(setDoc(profile(database, 'alice'), {createdAt: Timestamp.fromMillis(1), updatedAt: serverTimestamp()}, {merge: true}));
});
test('a user can belong to multiple homes, and membership does not grant other users access', async () => {
  await createHome();
  await createHome('alice', 'second', 'a'.repeat(32));
  const snapshot = await assertSucceeds(getDocs(collection(db('alice'), 'users/alice/memberships')));
  assert.equal(snapshot.size, 2);
  await assertFails(getDocs(collection(db('bob'), 'users/alice/memberships')));
  await assertFails(getDoc(doc(db('bob'), 'households/second')));
});
test('leave revokes access, preserves expenses and profile, and allows invited rejoin', async () => {
  await createHome(); await join('bob');
  await setDoc(doc(db('alice'), 'households/home/expenses/old'), expense());
  await assertSucceeds(leave('alice'));
  await assertFails(getDoc(house(db('alice'))));
  await assertFails(getDocs(collection(db('alice'), 'households/home/expenses')));
  assert.equal((await getDocs(collection(db('bob'), 'households/home/expenses'))).size, 1);
  await assertSucceeds(getDoc(profile(db('alice'), 'alice')));
  await assertSucceeds(join('alice'));
});
test('forged memberships, unpaired records, and removal of other members fail', async () => {
  await createHome();
  await assertFails(setDoc(doc(db('bob'), 'users/bob/memberships/home'), record('bob')));
  const database = db('bob'), batch = writeBatch(database);
  pair(batch, database, 'bob');
  await assertFails(batch.commit());
  await assertFails(setDoc(doc(db('bob'), 'households/home/members/alice'), record('alice')));
  await join('bob');
  await assertFails(setDoc(house(db('bob')), {memberIds: ['bob']}, {merge: true}));
  await assertFails(setDoc(doc(db('alice'), 'households/home/members/alice'), {displayName: 'Other'}, {merge: true}));
  await assertFails(setDoc(house(db('alice')), {maxMembers: 100}, {merge: true}));
});
test('legacy account migrates paired memberships without touching expenses', async () => {
  await env.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await setDoc(profile(database, 'alice'), {householdId: 'home', name: 'alice', inviteCode: code});
    await setDoc(house(database), {memberIds: ['alice','bob'], memberNames: {alice: 'alice',bob:'bob'}, currency: 'EUR', inviteCode: code, createdAt: Timestamp.now()});
    await setDoc(doc(database, 'households/home/expenses/legacy'), {...expense(), createdAt: Timestamp.now()});
  });
  const database = db('alice');
  // Legacy access remains available before either roommate has upgraded.
  await assertSucceeds(getDoc(doc(db('alice'), 'households/home/expenses/legacy')));
  await assertSucceeds(getDoc(doc(db('bob'), 'households/home/expenses/legacy')));
  await assertSucceeds(setDoc(profile(database,'alice'), person('alice'), {merge:true}));
  const batch = writeBatch(database); pair(batch, database, 'alice');
  batch.update(profile(database,'alice'), {legacyMembershipMigrated: true, updatedAt: serverTimestamp()});
  await assertSucceeds(batch.commit());
  assert.equal((await getDoc(doc(database, 'households/home/expenses/legacy'))).data().total, 250);
  // Outsiders cannot forge a legacy hint in their profile.
  await assertFails(setDoc(profile(db('mallory'),'mallory'), {...person('mallory'), householdId:'home'}));
  await assertFails(join('mallory'));
});
test('last member may leave without deleting the home or expenses', async () => {
  await createHome();
  await assertSucceeds(leave('alice'));
  await assertFails(getDoc(house(db('alice'))));
  await assertSucceeds(join('bob'));
});

test('100 items are validated atomically without exceeding rule budgets', async () => {
  await createHome();
  const database = db('alice'), batch = writeBatch(database);
  const parent = doc(database, 'households/home/expenses/full');
  batch.set(parent, expense({itemCount: 100, total: 25000}));
  for (let i = 0; i < 100; i++) batch.set(doc(parent, 'items', String(i)), {name: 'Milk', amount: 250, index: i});
  await assertSucceeds(batch.commit());
  await join('bob');
  const items = await assertSucceeds(getDocs(collection(db('bob'), 'households/home/expenses/full/items')));
  assert.equal(items.size, 100);
  await assertFails(getDocs(collection(db('outsider'), 'households/home/expenses/full/items')));
});
test('item writes require an atomic new parent and valid types and index', async () => {
  await createHome();
  const database = db('alice');
  for (const [i, overrides] of [{amount: -1}, {amount: 1.5}, {name: ''}, {index: 2}, {image: 'denied'}].entries()) {
    const batch = writeBatch(database), parent = doc(database, `households/home/expenses/bad-item-${i}`);
    batch.set(parent, expense({itemCount: 1}));
    batch.set(doc(parent, 'items', '0'), {name: 'Milk', amount: 250, index: 0, ...overrides});
    await assertFails(batch.commit());
  }
  await assertFails(setDoc(doc(database, 'households/home/expenses/no-parent/items/0'), {name: 'Milk', amount: 250, index: 0}));
});
test('knowing a household ID without the invitation code is insufficient', async () => {
  await createHome();
  await assertFails(join('mallory', 'home', 'f'.repeat(32)));
});
test('new expense split participants must be exactly the active members', async () => {
  await createHome(); await join('bob');
  await assertSucceeds(setDoc(doc(db('alice'),'households/home/expenses/v2'),expense({splitBetween:['alice','bob']})));
  for (const [i, splitBetween] of [['alice','mallory'],['alice','alice'],['alice']].entries()) {
    await assertFails(setDoc(doc(db('alice'),`households/home/expenses/forged-split-${i}`),expense({splitBetween})));
  }
});
test('leaving cannot rewrite the frozen legacy participant pair', async () => {
  await createHome(); await join('bob');
  await leave('alice'); await join('charlie');
  const database = db('bob'), batch = writeBatch(database);
  batch.update(house(database),{memberIds:['charlie'],legacyMemberIds:['bob','charlie']});
  batch.delete(doc(database,'users/bob/memberships/home'));
  batch.delete(doc(database,'households/home/members/bob'));
  await assertFails(batch.commit());
});
test('unimplemented receipt/invoice/settlement modules default to deny, even for members', async () => {
  await createHome();
  for (const path of ['households/home/receipts/r','households/home/invoices/i','households/home/settlements/s','receipts/public']) {
    await assertFails(setDoc(doc(db('alice'),path),{text:'private derived data'}));
    await assertFails(getDoc(doc(db('outsider'),path)));
  }
});
test('former membership cannot authorize a new expense after leaving', async () => {
  await createHome(); await join('bob'); await leave('alice');
  await assertFails(setDoc(doc(db('alice'),'households/home/expenses/stale'),expense()));
});
const catalogId = 'a'.repeat(64);
const catalogRow = () => ({name:'Milk',category:'food',mergedInto:'',revision:0,updatedBy:'alice',updatedAt:serverTimestamp()});
async function phase1Purchase() {
  await createHome();
  const database=db('alice'), source=writeBatch(database);
  source.set(doc(database,'households/home/expenses/receipt'),expense({itemCount:1}));
  source.set(doc(database,'households/home/expenses/receipt/items/0'),{name:'Milk',amount:250,index:0,quantityMilli:1000,unit:'each'});
  await source.commit();
  const batch=writeBatch(database);
  batch.set(doc(database,`households/home/catalog/${catalogId}`),catalogRow());
  batch.set(doc(database,`households/home/itemAliases/${'b'.repeat(64)}`),{itemId:catalogId,alias:'milk',active:true,revision:0,updatedBy:'alice',updatedAt:serverTimestamp()});
  batch.set(doc(database,'households/home/purchases/receipt_0'),{expenseId:'receipt',itemIndex:0,itemId:catalogId,name:'Milk',amount:250,merchant:'Market',date:Timestamp.fromDate(new Date('2026-10-15T00:00:00Z')),quantityMilli:1000,unit:'each',quantityVerified:true,active:true,createdBy:'alice',updatedAt:serverTimestamp()});
  await batch.commit();
}
test('phase1 deterministic source-backed purchases and library are member-only',async()=>{
  await assertSucceeds(phase1Purchase()); await join('bob');
  for(const name of ['catalog','itemAliases','purchases','shopping','stock','stockEvents','receiptSignatures','catalogChanges','shoppingEvents','aliasChanges','purchaseCorrections','purchaseChanges']){
    await assertSucceeds(getDocs(collection(db('bob'),`households/home/${name}`)));
    await assertFails(getDocs(collection(db('mallory'),`households/home/${name}`)));
    await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(),`households/home/${name}`)));
  }
  const purchase=(await getDoc(doc(db('alice'),'households/home/purchases/receipt_0'))).data();
  await assertFails(setDoc(doc(db('alice'),'households/home/purchases/forged'),{...purchase,amount:999,updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db('alice'),'households/home/purchases/receipt_0'),{...purchase,active:false,updatedAt:serverTimestamp()}));
});
test('catalog corrections require an immutable matching audit, with no cross-group merge',async()=>{
  await phase1Purchase();
  const database=db('alice'), ref=doc(database,`households/home/catalog/${catalogId}`);
  await assertFails(setDoc(ref,{...catalogRow(),name:'Changed',revision:1}));
  const batch=writeBatch(database);
  batch.update(ref,{name:'Fresh milk',revision:1,updatedAt:serverTimestamp()});
  batch.set(doc(database,`households/home/catalogChanges/${catalogId}_1`),{itemId:catalogId,revision:1,before:{name:'Milk',category:'food',mergedInto:''},after:{name:'Fresh milk',category:'food',mergedInto:''},actor:'alice',at:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(ref,{...catalogRow(),revision:2,mergedInto:'outside-group'}));
});
test('shopping quantities require paired immutable add events, valid assignments and revisions',async()=>{
  await phase1Purchase();const database=db('alice'),batch=writeBatch(database);
  const data={itemId:catalogId,name:'Milk',lastAdd:'op1',quantityMilli:1000,unit:'each',checked:false,assignedTo:'alice',notes:'Greek brand',revision:0,updatedBy:'alice',updatedAt:serverTimestamp()};
  batch.set(doc(database,'households/home/shopping/milk'),data);
  batch.set(doc(database,'households/home/shoppingEvents/op1'),{listId:'milk',deltaMilli:1000,actor:'alice',at:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(database,'households/home/shopping/milk'),{...data,quantityMilli:2000,revision:1}));
  await assertFails(setDoc(doc(database,'households/home/shopping/milk'),{...data,assignedTo:'outsider',revision:1}));
  await assertSucceeds(setDoc(doc(database,'households/home/shopping/milk'),{...data,checked:true,revision:1}));
  assert.equal((await getDocs(collection(database,'households/home/expenses'))).size,1);
});
test('reviewed restock and manual consumption enforce nonnegative stock and prevent event replay',async()=>{
  await phase1Purchase();const database=db('alice'),batch=writeBatch(database);
  const lot=doc(database,'households/home/stock/receipt_receipt_0');
  batch.set(lot,{itemId:catalogId,name:'Milk',unit:'each',quantityMilli:2000,lowStockMilli:1000,expiry:null,lastEvent:'receipt_receipt_0',revision:0,updatedBy:'alice',updatedAt:serverTimestamp()});
  batch.set(doc(database,'households/home/stockEvents/receipt_receipt_0'),{lotId:'receipt_receipt_0',purchaseId:'receipt_0',deltaMilli:2000,actor:'alice',at:serverTimestamp(),kind:'restock'});
  await assertSucceeds(batch.commit());
  const consume=writeBatch(database);
  consume.update(lot,{quantityMilli:1500,lastEvent:'consume1',revision:1,updatedAt:serverTimestamp()});
  consume.set(doc(database,'households/home/stockEvents/consume1'),{lotId:'receipt_receipt_0',purchaseId:'',deltaMilli:-500,actor:'alice',at:serverTimestamp(),kind:'consume'});
  await assertSucceeds(consume.commit());
  await assertFails(setDoc(lot,{quantityMilli:1000,lastEvent:'consume1',revision:2,updatedBy:'alice',updatedAt:serverTimestamp()},{merge:true}));
  const negative=writeBatch(database);
  negative.update(lot,{quantityMilli:-1,lastEvent:'consume2',revision:2,updatedAt:serverTimestamp()});
  negative.set(doc(database,'households/home/stockEvents/consume2'),{lotId:'receipt_receipt_0',purchaseId:'',deltaMilli:-1501,actor:'alice',at:serverTimestamp(),kind:'consume'});
  await assertFails(negative.commit());
});
test('purchase quantity corrections require paired audits; archive/restore never mutates source expenses',async()=>{
 await phase1Purchase();const database=db('alice'), ref=doc(database,'households/home/purchaseCorrections/receipt_0');
 const after={itemId:catalogId,quantityMilli:2000,unit:'each',quantityVerified:true,active:false};
 await assertFails(setDoc(ref,{...after,revision:0,updatedBy:'alice',updatedAt:serverTimestamp()}));
 const batch=writeBatch(database);
 batch.set(ref,{...after,revision:0,updatedBy:'alice',updatedAt:serverTimestamp()});
 batch.set(doc(database,'households/home/purchaseChanges/receipt_0_0'),{purchaseId:'receipt_0',revision:0,before:{itemId:catalogId,quantityMilli:1000,unit:'each',quantityVerified:true,active:true},after,actor:'alice',at:serverTimestamp()});
 await assertSucceeds(batch.commit());
 assert.equal((await getDoc(doc(database,'households/home/expenses/receipt/items/0'))).data().quantityMilli,1000);
 await assertFails(getDoc(doc(db('outsider'),'households/home/purchaseCorrections/receipt_0')));
 await assertFails(setDoc(ref,{...after,revision:2,updatedBy:'alice',updatedAt:serverTimestamp()}));
});
test('merged catalogs cannot form cycles, including in a single malicious batch',async()=>{
 await phase1Purchase();const database=db('alice'), other='c'.repeat(64);
 await setDoc(doc(database,`households/home/catalog/${other}`),catalogRow());
 const batch=writeBatch(database);
 for(const [source,target] of [[catalogId,other],[other,catalogId]]){
  batch.update(doc(database,`households/home/catalog/${source}`),{mergedInto:target,revision:1,updatedAt:serverTimestamp()});
  batch.set(doc(database,`households/home/catalogChanges/${source}_1`),{itemId:source,revision:1,before:{name:'Milk',category:'food',mergedInto:''},after:{name:'Milk',category:'food',mergedInto:target},actor:'alice',at:serverTimestamp()});
 }
 await assertFails(batch.commit());
});
test('alias corrections require history; disabling never erases source purchases',async()=>{
 await phase1Purchase();const database=db('alice'),alias='b'.repeat(64),ref=doc(database,`households/home/itemAliases/${alias}`);
 await assertFails(setDoc(ref,{active:false,revision:1,updatedAt:serverTimestamp()},{merge:true}));
 const batch=writeBatch(database);batch.update(ref,{active:false,revision:1,updatedAt:serverTimestamp()});
 batch.set(doc(database,`households/home/aliasChanges/${alias}_1`),{aliasId:alias,revision:1,before:{itemId:catalogId,active:true},after:{itemId:catalogId,active:false},actor:'alice',at:serverTimestamp()});
 await assertSucceeds(batch.commit());assert.equal((await getDocs(collection(database,'households/home/purchases'))).size,1);
 await assertFails(getDocs(collection(db('outsider'),'households/home/aliasChanges')));
});
test('personal expense/items are owner-only, including against the roommate',async()=>{
 await createHome();await join('bob');const database=db('alice'),batch=writeBatch(database);
 batch.set(doc(database,'users/alice/personalExpenses/private'),expense({scope:'personal',kind:'expense',category:'food',groupId:'home',itemCount:1}));
 batch.set(doc(database,'users/alice/personalExpenses/private/items/0'),{name:'Private medicine',amount:250,index:0});
 await assertSucceeds(batch.commit());
 await assertSucceeds(getDoc(doc(database,'users/alice/personalExpenses/private')));
 await assertFails(getDoc(doc(db('bob'),'users/alice/personalExpenses/private')));
 await assertFails(getDocs(collection(db('bob'),'users/alice/personalExpenses/private/items')));
 await assertFails(setDoc(doc(database,'households/home/expenses/private-leak'),expense({scope:'personal',kind:'expense',category:'food'})));
 await assertFails(setDoc(doc(database,'users/alice/personalExpenses/wrong-payer'),expense({scope:'personal',kind:'expense',category:'food',groupId:'home',payer:'bob'})));
});
test('custom shares require exact integer cents and current group participants',async()=>{
 await createHome();await join('bob');const ref=id=>doc(db('alice'),`households/home/expenses/${id}`);
 await assertSucceeds(setDoc(ref('custom'),expense({splitCents:{alice:150,bob:100},scope:'shared',category:'food',kind:'expense'})));
 for(const [i,splitCents] of [{alice:150,bob:99},{alice:-1,bob:251},{alice:250,mallory:0},{alice:150.5,bob:99.5}].entries())await assertFails(setDoc(ref(`bad-split-${i}`),expense({splitCents})));
 await assertSucceeds(setDoc(ref('refund'),expense({kind:'refund',category:'food'})));
});
test('repayments are immutable and only exact one-time reversals are permitted',async()=>{
 await createHome();await join('bob');const database=db('alice'),date=Timestamp.fromDate(new Date('2026-10-15T00:00:00Z'));
 const data={from:'bob',to:'alice',amount:100,date,month:'2026-10',reference:'Cash receipt',reversalOf:'',createdBy:'alice',createdAt:serverTimestamp()};
 await assertSucceeds(setDoc(doc(database,'households/home/payments/p1'),data));
 await assertFails(setDoc(doc(database,'households/home/payments/p1'),{...data,amount:200}));
 await assertFails(setDoc(doc(database,'households/home/payments/reverse_p1'),{...data,amount:200,reversalOf:'p1'}));
 await assertSucceeds(setDoc(doc(database,'households/home/payments/reverse_p1'),{...data,reversalOf:'p1',reference:'Recorded in error'}));
 await assertFails(setDoc(doc(database,'households/home/payments/reverse_p1'),{...data,reversalOf:'p1'}));
 await assertFails(getDocs(collection(db('outsider'),'households/home/payments')));
});
test('category and void corrections require matching audit; only creator can change void state',async()=>{
 await createHome();await join('bob');const database=db('alice'),ref=doc(database,'households/home/expenses/e');await setDoc(ref,expense());
 await assertFails(setDoc(ref,{category:'food',voided:true,revision:0,updatedBy:'alice',updatedAt:serverTimestamp()},{merge:true}));
 const batch=writeBatch(database);batch.update(ref,{category:'food',voided:true,revision:0,updatedBy:'alice',updatedAt:serverTimestamp()});batch.set(doc(database,'households/home/expenseChanges/e_0'),{expenseId:'e',revision:0,before:{category:'uncategorized',voided:false},after:{category:'food',voided:true},actor:'alice',at:serverTimestamp()});await assertSucceeds(batch.commit());
 assert.equal((await getDoc(ref)).data().total,250);
 const bob=db('bob'),other=writeBatch(bob);other.update(doc(bob,'households/home/expenses/e'),{category:'food',voided:false,revision:1,updatedBy:'bob',updatedAt:serverTimestamp()});other.set(doc(bob,'households/home/expenseChanges/e_1'),{expenseId:'e',revision:1,before:{category:'food',voided:true},after:{category:'food',voided:false},actor:'bob',at:serverTimestamp()});await assertFails(other.commit());
});
test('budgets, recurring templates and deterministic confirmed occurrences are scoped and validated',async()=>{
 await createHome();const database=db('alice');
 await assertSucceeds(setDoc(doc(database,'households/home/budgets/2026-10'),{total:10000,categories:{food:5000},revision:0,updatedBy:'alice',updatedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(database,'households/home/budgets/2026-11'),{total:-1,categories:{food:5000},revision:0,updatedBy:'alice',updatedAt:serverTimestamp()}));
 await assertSucceeds(setDoc(doc(database,'households/home/recurring/rent'),{merchant:'Rent',amount:10000,payer:'alice',category:'utilities',day:1,enabled:true,revision:0,updatedBy:'alice',updatedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(database,'households/home/expenses/random-duplicate'),expense({merchant:'Rent',total:10000,recurringId:'rent',recurringMonth:'2026-10'})));
 await assertSucceeds(setDoc(doc(database,'households/home/expenses/recurring_rent_2026-10'),expense({merchant:'Rent',total:10000,recurringId:'rent',recurringMonth:'2026-10'})));
 await assertFails(getDocs(collection(db('outsider'),'households/home/recurring')));
});

test('notification preferences and device tokens are owner-only and schema constrained', async () => {
  const alice=db('alice'), bob=db('bob');
  const settings={enabled:true,remote:false,zone:'Europe/Nicosia',kinds:{expense:true,shopping:false,stock:false,recurring:false,settlement:false,budget:false},updatedAt:serverTimestamp()};
  const target=doc(alice,'users/alice/preferences/notifications');
  await assertSucceeds(setDoc(target,settings));
  await assertFails(getDoc(doc(bob,'users/alice/preferences/notifications')));
  await assertFails(setDoc(doc(bob,'users/alice/preferences/notifications'),settings));
  await assertFails(setDoc(target,{...settings,allowAnyGroup:true}));
  await assertFails(setDoc(target,{...settings,kinds:{expense:true}}));
  const device='a'.repeat(64), token={token:'test-device-token',platform:'android',enabled:true,updatedAt:serverTimestamp()};
  await assertSucceeds(setDoc(doc(alice,`users/alice/devices/${device}`),token));
  await assertFails(getDoc(doc(bob,`users/alice/devices/${device}`)));
  await assertFails(setDoc(doc(bob,`users/alice/devices/${device}`),token));
  await assertFails(setDoc(doc(alice,`users/alice/devices/${device}`),{...token,groupId:'foreign'}));
  await assertFails(setDoc(doc(alice,'notificationDeliveries/forged'),{uid:'alice'}));
});

test('all v3 group collections reject cross-group reads, queries and writes', async () => {
  await createHome('alice');
  await createHome('bob','other','fedcba9876543210fedcba9876543210');
  const paths=['catalog','catalogChanges','itemAliases','aliasChanges','purchases','purchaseCorrections','purchaseChanges','shopping','shoppingEvents','stock','stockEvents','receiptSignatures','budgets','payments','recurring','expenseChanges','expenses'];
  await env.withSecurityRulesDisabled(async context=> {
    for(const path of paths) await setDoc(doc(context.firestore(),`households/home/${path}/existing`),{auditFixture:true});
    await setDoc(doc(context.firestore(),'households/home/expenses/existing/items/0'),{name:'ΓΑΛΑ',amount:250,index:0});
  });
  const alice=db('alice'), bob=db('bob');
  for(const path of paths) {
    await assertSucceeds(getDoc(doc(alice,`households/home/${path}/existing`)));
    await assertFails(getDoc(doc(bob,`households/home/${path}/existing`)));
    await assertFails(getDocs(collection(bob,`households/home/${path}`)));
    await assertFails(setDoc(doc(bob,`households/home/${path}/forged`),{createdBy:'bob'}));
  }
  await assertFails(getDoc(doc(bob,'households/home/expenses/existing/items/0')));
  for(const unknown of ['receipts','invoices','settlements']) {
    await assertFails(getDoc(doc(alice,`households/home/${unknown}/unknown`)));
    await assertFails(setDoc(doc(alice,`households/home/${unknown}/forged`),{createdBy:'alice'}));
  }
});

test('membership revocation removes access to every v3 collection without deleting historical data',async()=> {
  await createHome('alice'); await join('bob');
  const paths=['catalog','purchases','shopping','stock','receiptSignatures','budgets','payments','recurring','expenses'];
  await env.withSecurityRulesDisabled(async context=> {
    for(const path of paths) await setDoc(doc(context.firestore(),`households/home/${path}/history`),{preserved:true});
  });
  const bob=db('bob'), batch=writeBatch(bob);
  batch.update(house(bob),{memberIds:arrayRemove('bob'),legacyMemberIds:['alice','bob']});
  batch.delete(doc(bob,'users/bob/memberships/home'));batch.delete(doc(bob,'households/home/members/bob'));
  await assertSucceeds(batch.commit());
  const alice=db('alice');
  for(const path of paths) {
    await assertFails(getDoc(doc(bob,`households/home/${path}/history`)));
    const original=await assertSucceeds(getDoc(doc(alice,`households/home/${path}/history`)));
    assert.equal(original.data().preserved,true);
  }
});
