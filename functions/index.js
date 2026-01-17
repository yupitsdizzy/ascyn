/**
 * Ascyn Cloud Functions (Callable)
 * - recordTaskCompletion: idempotent XP event + per-minute rate limit
 * - undoEvent: reversal event + undo window
 *
 * Collections:
 * users/{uid}/characters/{characterId}/xp_events/{eventId}
 * rate_limits/{uid}/buckets/{minuteBucket}
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Allowed stat names (mirror of AscynStat enum)
const ALLOWED_STATS = new Set([
  "strength",
  "endurance",
  "discipline",
  "focus",
  "productivity",
  "intelligence",
  "creativity",
  "peace",
]);

// Thresholds
const MAX_EVENTS_PER_MINUTE = 20;
const MAX_XP_PER_EVENT = 10000;

const DEFAULT_PRIMARY_STAT = "discipline";
const DEFAULT_UNDO_WINDOW_MINUTES = 15;

/* ----------------------------- helpers ----------------------------- */

function requireAuth(context) {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Authentication required");
  }
  return context.auth.uid;
}

function toNonNegNumber(v, fallback = 0) {
  const n = Number(v ?? fallback);
  if (Number.isNaN(n) || n < 0) return null;
  return n;
}

function toValidDate(v, fallback = new Date()) {
  if (!v) return fallback;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return fallback;
  return d;
}

function dateKeyLocal(dt) {
  const d = new Date(dt);
  const y = String(d.getFullYear()).padStart(4, "0");
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function eventIdForTask(taskId, occurredAt) {
  return `task_${taskId}_${dateKeyLocal(occurredAt)}`;
}

function minuteBucketKey(dt) {
  return String(Math.floor(dt.getTime() / 60000));
}

function charRefFor(uid, characterId) {
  return db.collection("users").doc(uid).collection("characters").doc(characterId);
}

function rateBucketRefFor(uid, bucketKey) {
  return db.collection("rate_limits").doc(uid).collection("buckets").doc(bucketKey);
}

/* ----------------------- recordTaskCompletion ---------------------- */

exports.recordTaskCompletion = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);

  const characterId = data?.characterId;
  const taskId = data?.taskId;

  const overallXp = toNonNegNumber(data?.overallXp, 0);
  const primaryStatName = String(data?.primaryStatName || DEFAULT_PRIMARY_STAT);
  const occurredAt = toValidDate(data?.occurredAt, new Date());

  if (!characterId || !taskId) {
    throw new functions.https.HttpsError("invalid-argument", "characterId and taskId required");
  }
  if (overallXp === null) {
    throw new functions.https.HttpsError("invalid-argument", "overallXp must be a non-negative number");
  }
  if (overallXp > MAX_XP_PER_EVENT) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `overallXp exceeds maximum of ${MAX_XP_PER_EVENT}`
    );
  }
  if (!ALLOWED_STATS.has(primaryStatName)) {
    throw new functions.https.HttpsError("invalid-argument", "primaryStatName is not allowed");
  }

  const eventId = eventIdForTask(taskId, occurredAt);
  const charRef = charRefFor(uid, characterId);
  const eventRef = charRef.collection("xp_events").doc(eventId);

  return db.runTransaction(async (tx) => {
    // 1) Rate limit
    const bucketKey = minuteBucketKey(occurredAt);
    const rateRef = rateBucketRefFor(uid, bucketKey);
    const rateSnap = await tx.get(rateRef);
    const currentCount = rateSnap.exists ? Number(rateSnap.data()?.count || 0) : 0;

    if (currentCount >= MAX_EVENTS_PER_MINUTE) {
      throw new functions.https.HttpsError("resource-exhausted", "Rate limit exceeded");
    }

    // 2) Idempotency: same task + same local date creates same eventId
    const existing = await tx.get(eventRef);
    if (existing.exists) {
      return { eventId, created: false };
    }

    // 3) Read current totals
    const charSnap = await tx.get(charRef);
    const charData = charSnap.exists ? charSnap.data() : {};
    const overallPrev = Number(charData?.overallXpTotal || 0);
    const overallNew = overallPrev + overallXp;

    // 4) Stat split: all XP goes to primary stat (easy to extend later)
    const statXp = { [primaryStatName]: overallXp };

    const event = {
      id: eventId,
      uid,
      characterId,
      sourceType: "taskComplete",
      sourceId: String(taskId),
      occurredAt: admin.firestore.Timestamp.fromDate(occurredAt),
      overallXp,
      statXp,
      status: "active",
      note: "Task complete",
      createdAt: admin.firestore.Timestamp.now(),
    };

    // Write event
    tx.set(eventRef, event);

    // Increment rate bucket
    tx.set(
      rateRef,
      { count: currentCount + 1, updatedAt: admin.firestore.Timestamp.now() },
      { merge: true }
    );

    // Update character summary
    tx.set(
      charRef,
      {
        overallXpTotal: overallNew,
        lastEventAt: admin.firestore.Timestamp.fromDate(occurredAt),
        lastEventId: eventId,
        lastEventNote: event.note,
      },
      { merge: true }
    );

    return { eventId, created: true };
  });
});

/* ----------------------------- undoEvent ---------------------------- */

exports.undoEvent = functions.https.onCall(async (data, context) => {
  const uid = requireAuth(context);

  const characterId = data?.characterId;
  const eventIdToUndo = data?.eventIdToUndo;
  const undoWindowMinutes = toNonNegNumber(data?.undoWindowMinutes, DEFAULT_UNDO_WINDOW_MINUTES);

  if (!characterId || !eventIdToUndo) {
    throw new functions.https.HttpsError("invalid-argument", "characterId and eventIdToUndo required");
  }
  if (undoWindowMinutes === null) {
    throw new functions.https.HttpsError("invalid-argument", "undoWindowMinutes must be a non-negative number");
  }

  const charRef = charRefFor(uid, characterId);
  const eventsColl = charRef.collection("xp_events");
  const targetRef = eventsColl.doc(String(eventIdToUndo));

  return db.runTransaction(async (tx) => {
    const targetSnap = await tx.get(targetRef);
    if (!targetSnap.exists) throw new functions.https.HttpsError("not-found", "Event not found");

    const target = targetSnap.data();
    if (!target || target.status !== "active") {
      throw new functions.https.HttpsError("failed-precondition", "Event not undoable");
    }

    const occurred =
      target.occurredAt && typeof target.occurredAt.toDate === "function"
        ? target.occurredAt.toDate()
        : toValidDate(target.occurredAt, new Date(0));

    const ageMs = Date.now() - occurred.getTime();
    if (ageMs > undoWindowMinutes * 60 * 1000) {
      throw new functions.https.HttpsError("failed-precondition", "Undo window expired");
    }

    const targetOverallXp = Number(target.overallXp || 0);
    const reversalId = `undo_${String(eventIdToUndo)}_${Date.now()}`;

    // Negate stat XP
    const negStat = {};
    const statXpObj = target.statXp || {};
    for (const k of Object.keys(statXpObj)) {
      negStat[k] = -Number(statXpObj[k] || 0);
    }

    const reversal = {
      id: reversalId,
      uid,
      characterId,
      sourceType: "undoReversal",
      sourceId: String(eventIdToUndo),
      occurredAt: admin.firestore.Timestamp.now(),
      overallXp: -targetOverallXp,
      statXp: negStat,
      status: "active",
      note: `Undo of ${String(eventIdToUndo)}`,
      createdAt: admin.firestore.Timestamp.now(),
    };

    // Write reversal + mark target reversed
    tx.set(eventsColl.doc(reversalId), reversal);
    tx.set(
      targetRef,
      {
        status: "reversed",
        reversedBy: reversalId,
        undoNote: `Reversed by ${reversalId}`,
        reversedAt: admin.firestore.Timestamp.now(),
      },
      { merge: true }
    );

    // Adjust character totals (simple subtract)
    const charSnap = await tx.get(charRef);
    const charData = charSnap.exists ? charSnap.data() : {};
    const overallPrev = Number(charData?.overallXpTotal || 0);
    const overallNew = overallPrev - targetOverallXp;

    tx.set(charRef, { overallXpTotal: overallNew }, { merge: true });

    return { eventId: reversalId, created: true };
  });
});
