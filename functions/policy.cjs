'use strict';
const kinds = new Set(['expense','shopping','stock','recurring','settlement','budget']);
function recipientAllowed(uid, members, settings, kind) {
  return members.includes(uid) && kinds.has(kind) && settings?.enabled === true && settings?.remote === true && settings?.kinds?.[kind] === true;
}
function pushPayload(uid, groupId, kind, eventId) {
  if (!kinds.has(kind)) throw new Error('Unknown notification kind');
  // Data-only messages are verified by the client before displaying. No receipt, payer, amount or merchant data.
  return {data: {uid, groupId, kind, eventId}, android: {priority:'normal'}, apns: {headers: {'apns-push-type':'background','apns-priority':'5'}, payload: {aps: {contentAvailable:true}}}};
}
module.exports={recipientAllowed,pushPayload};
