'use strict';
// OPTIONAL. Not deployed by repository workflows. Requires owner billing/APNs review.
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {getMessaging}=require('firebase-admin/messaging');
const {onDocumentCreated,onDocumentUpdated,onDocumentWritten}=require('firebase-functions/v2/firestore');
const {createHash}=require('node:crypto');
const {recipientAllowed,pushPayload}=require('./policy.cjs');
initializeApp();
const db=getFirestore();
async function send(groupId,kind,eventId,actor) {
  if(process.env.BASHAHISAB_NOTIFICATIONS_ENABLED !== 'true') return;
  const home=db.doc(`households/${groupId}`);
  const initial=await home.get();
  for(const uid of initial.data()?.memberIds ?? []) {
    if(uid===actor && kind!=='stock') continue;
    const user=db.doc(`users/${uid}`);
    const settings=await user.collection('preferences').doc('notifications').get();
    const devices=await user.collection('devices').where('enabled','==',true).get();
    for(const device of devices.docs) {
      const key=createHash('sha256').update(`${uid}/${device.id}/${eventId}`).digest('hex');
      const log=db.doc(`notificationDeliveries/${key}`);
      const claimed=await db.runTransaction(async tx=> {
        const [current,preferences,delivery,endpoint]=await Promise.all([tx.get(home),tx.get(settings.ref),tx.get(log),tx.get(device.ref)]);
        if(!recipientAllowed(uid,current.data()?.memberIds ?? [],preferences.data(),kind) || endpoint.data()?.enabled!==true || delivery.exists) return false;
        tx.create(log,{uid,groupId,eventId,claimedAt:FieldValue.serverTimestamp()}); return true;
      });
      if(!claimed) continue;
      try {
        await getMessaging().send({...pushPayload(uid,groupId,kind,eventId),token:device.data().token});
        await log.update({sentAt:FieldValue.serverTimestamp()});
      } catch(error) {
        // At most one attempt avoids repeated pushes after uncertain acknowledgement. The app remains authoritative.
        await log.update({failedAt:FieldValue.serverTimestamp(),code:String(error.code ?? 'unknown').slice(0,100)});
        if(['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(error.code)) await device.ref.update({enabled:false,updatedAt:FieldValue.serverTimestamp()});
      }
    }
  }
}
exports.newExpense=onDocumentCreated('households/{group}/expenses/{expense}',e=> {
  const d=e.data.data();
  if(d.scope==='personal') return;
  return send(e.params.group,'expense',`${e.params.group}/expenses/${e.params.expense}/0`,d.createdBy);
});
exports.shoppingChange=onDocumentWritten('households/{group}/shopping/{item}',e=> {
  if(!e.data.after.exists) return;
  const d=e.data.after.data();
  return send(e.params.group,'shopping',`${e.params.group}/shopping/${e.params.item}/${d.revision}`,d.updatedBy);
});
exports.lowStock=onDocumentUpdated('households/{group}/stock/{stock}',e=> {
  const before=e.data.before.data(),after=e.data.after.data();
  if(before.quantityMilli<=before.lowStockMilli || after.quantityMilli>after.lowStockMilli) return;
  return send(e.params.group,'stock',`${e.params.group}/stock/${e.params.stock}/${after.revision}`,after.updatedBy);
});
