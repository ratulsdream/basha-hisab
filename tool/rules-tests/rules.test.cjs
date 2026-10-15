const { readFileSync } = require('node:fs');
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, collection, writeBatch, arrayUnion, serverTimestamp, Timestamp } = require('firebase/firestore');
let env;
const code = '0123456789abcdef0123456789abcdef';
const db = uid => env.authenticatedContext(uid).firestore();
const profile = (database, uid) => doc(database, 'users', uid);
const house = database => doc(database, 'households', 'home');
async function createHome(uid = 'alice') {
  const database = db(uid);
  const batch = writeBatch(database);
  batch.set(house(database), {memberIds: [uid], memberNames: {[uid]: 'Alice'}, currency: 'BDT', inviteCode: code, createdAt: serverTimestamp()});
  batch.set(profile(database, uid), {householdId: 'home', name: 'Alice', inviteCode: code});
  batch.set(doc(database, 'invites', code), {householdId: 'home', ownerId: uid, createdAt: serverTimestamp()});
  return batch.commit();
}
async function join(uid, name = uid) {
  const database = db(uid), batch = writeBatch(database);
  batch.update(house(database), {memberIds: arrayUnion(uid), [`memberNames.${uid}`]: name});
  batch.set(profile(database, uid), {householdId: 'home', name, inviteCode: code});
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
test('membership cannot be removed, renamed, or moved to another household', async () => {
  await createHome(); await join('bob');
  await assertFails(setDoc(profile(db('bob'), 'bob'), {householdId: 'other', name: 'Bob'}));
  const database = db('bob');
  const batch = writeBatch(database);
  batch.update(house(database), {memberIds: ['bob']});
  await assertFails(batch.commit());
  await assertFails(createHome('bob'));
});
test('a profile or household cannot be created alone', async () => {
  await assertFails(setDoc(profile(db('alice'), 'alice'), {householdId: 'home', name: 'Alice', inviteCode: code}));
  await assertFails(setDoc(house(db('alice')), {memberIds: ['alice'], memberNames: {alice: 'Alice'}, currency: 'BDT', inviteCode: code, createdAt: serverTimestamp()}));
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
  const database = db('mallory'), batch = writeBatch(database);
  batch.update(house(database), {memberIds: arrayUnion('mallory'), 'memberNames.mallory': 'Mallory'});
  batch.set(profile(database, 'mallory'), {householdId: 'home', name: 'Mallory', inviteCode: 'ffffffffffffffffffffffffffffffff'});
  await assertFails(batch.commit());
});
