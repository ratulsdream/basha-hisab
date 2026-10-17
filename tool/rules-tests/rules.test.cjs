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
