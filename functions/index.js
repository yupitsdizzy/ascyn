const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

function dateKeyLocal(dt) {
  const d = new Date(dt);
  const y = d.getFullYear().toString().padStart(4, '0');
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function eventIdForTask(taskId, occurredAt) {
  const key = dateKeyLocal(occurredAt);
  return `task_${taskId}_${key}`;
}

exports.recordTaskCompletion = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  const uid = context.auth.uid;
  const characterId = data.characterId;
  const taskId = data.taskId;
  const overallXp = Number(data.overallXp || 0);
  const primaryStatName = data.primaryStatName || 'discipline';
  const occurredAt = data.occurredAt ? new Date(data.occurredAt) : new Date();

  if (!characterId || !taskId) {
    throw new functions.https.HttpsError('invalid-argument', 'characterId and taskId required');
  }

  const eventId = eventIdForTask(taskId, occurredAt);
  const charRef = db.collection('users').doc(uid).collection('characters').doc(characterId);
  const eventsRef = charRef.collection('xp_events').doc(eventId);

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(eventsRef);
    if (existing.exists) {
      return { eventId, created: false };
    }

    const charSnap = await tx.get(charRef);
    const charData = charSnap.exists ? charSnap.data() : {};
    const overallXpTotal = Number((charData && charData.overallXpTotal) || 0);

    // simple stat split: primary gets all (server can be extended)
    const statXp = {};
    statXp[primaryStatName] = overallXp;

    const newOverall = overallXpTotal + overallXp;

    const event = {
      id: eventId,
      uid,
      characterId,
      sourceType: 'taskComplete',
      sourceId: taskId,
      occurredAt: admin.firestore.Timestamp.fromDate(occurredAt),
      overallXp: overallXp,
      statXp: statXp,
      status: 'active',
      note: 'Task complete',
    };

    tx.set(eventsRef, event);

    tx.set(charRef, {
      overallXpTotal: newOverall,
      lastEventAt: admin.firestore.Timestamp.fromDate(occurredAt),
      lastEventId: eventId,
      lastEventNote: event.note,
    }, { merge: true });

    return { eventId, created: true };
  });
});

exports.undoEvent = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
  const uid = context.auth.uid;
  const characterId = data.characterId;
  const eventIdToUndo = data.eventIdToUndo;
  const undoWindowMinutes = Number(data.undoWindowMinutes || 15);

  if (!characterId || !eventIdToUndo) {
    throw new functions.https.HttpsError('invalid-argument', 'characterId and eventIdToUndo required');
  }

  const charRef = db.collection('users').doc(uid).collection('characters').doc(characterId);
  const eventsColl = charRef.collection('xp_events');
  const targetRef = eventsColl.doc(eventIdToUndo);

  return db.runTransaction(async (tx) => {
    const targetSnap = await tx.get(targetRef);
    if (!targetSnap.exists) throw new functions.https.HttpsError('not-found', 'Event not found');
    const target = targetSnap.data();
    if (!target || target.status !== 'active') throw new functions.https.HttpsError('failed-precondition', 'Event not undoable');

    const occurred = target.occurredAt.toDate ? target.occurredAt.toDate() : new Date(target.occurredAt);
    const ageMs = Date.now() - occurred.getTime();
    if (ageMs > undoWindowMinutes * 60 * 1000) throw new functions.https.HttpsError('failed-precondition', 'Undo window expired');

    const reversalId = `undo_${eventIdToUndo}_${Date.now()}`;

    const negStat = {};
    for (const k in (target.statXp || {})) {
      negStat[k] = -Number(target.statXp[k] || 0);
    }

    const reversal = {
      id: reversalId,
      uid,
      characterId,
      sourceType: 'undoReversal',
      sourceId: eventIdToUndo,
      occurredAt: admin.firestore.Timestamp.now(),
      overallXp: -Number(target.overallXp || 0),
      statXp: negStat,
      status: 'active',
      note: `Undo of ${eventIdToUndo}`,
    };

    tx.set(eventsColl.doc(reversalId), reversal);
    tx.set(targetRef, { status: 'reversed', reversedBy: reversalId, undoNote: `Reversed by ${reversalId}` }, { merge: true });

    // adjust character totals (simple approach: recompute or subtract)
    const charSnap = await tx.get(charRef);
    const charData = charSnap.exists ? charSnap.data() : {};
    const overallPrev = Number((charData && charData.overallXpTotal) || 0);
    const newOverall = overallPrev - Number(target.overallXp || 0);

    tx.set(charRef, { overallXpTotal: newOverall }, { merge: true });

    return { eventId: reversalId, created: true };
  });
});
