const { expect } = require('chai');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

// Ensure tests target the emulator when running locally/CI
process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || 'localhost:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-project';

if (!admin.apps.length) {
  admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
}

const db = admin.firestore();

const fnModule = require('..');
const recordTask = fnModule.recordTaskCompletion;

describe('recordTaskCompletion validation and rate limits', function () {
  this.timeout(10000);
  const uid = 'test-user-1';
  const characterId = 'char-1';

  const context = { auth: { uid } };

  beforeEach(async () => {
    // cleanup user data
    await db.collection('users').doc(uid).delete().catch(() => {});
    // delete rate limit buckets
    const buckets = await db.collection('rate_limits').doc(uid).collection('buckets').listDocuments().catch(() => []);
    if (buckets && buckets.length) {
      const deletes = buckets.map((d) => d.delete());
      await Promise.all(deletes);
    }
    // ensure character doc exists
    await db.collection('users').doc(uid).collection('characters').doc(characterId).set({ overallXpTotal: 0 });
  });

  afterEach(async () => {
    await db.collection('users').doc(uid).delete().catch(() => {});
    const buckets = await db.collection('rate_limits').doc(uid).collection('buckets').listDocuments().catch(() => []);
    if (buckets && buckets.length) {
      const deletes = buckets.map((d) => d.delete());
      await Promise.all(deletes);
    }
  });

  it('rejects invalid primaryStatName', async () => {
    const data = { characterId, taskId: 't1', overallXp: 10, primaryStatName: 'not_a_stat' };
    try {
      await recordTask(data, context);
      throw new Error('expected to throw');
    } catch (err) {
      expect(err).to.exist;
      expect(err).to.have.property('code', 'invalid-argument');
    }
  });

  it('rejects overallXp exceeding cap', async () => {
    const big = 10001; // must match MAX_XP_PER_EVENT in functions/index.js (10000)
    const data = { characterId, taskId: 't2', overallXp: big, primaryStatName: 'discipline' };
    try {
      await recordTask(data, context);
      throw new Error('expected to throw');
    } catch (err) {
      expect(err).to.exist;
      expect(err).to.have.property('code', 'invalid-argument');
    }
  });

  it('enforces per-minute rate limit', async () => {
    // MAX_EVENTS_PER_MINUTE is 20 in functions/index.js
    const MAX = 20;
    // call MAX times with distinct taskIds
    for (let i = 0; i < MAX; i++) {
      const data = { characterId, taskId: `r${i}`, overallXp: 1, primaryStatName: 'discipline' };
      const res = await recordTask(data, context);
      expect(res).to.have.property('created');
    }

    // next call should fail with resource-exhausted
    try {
      const data = { characterId, taskId: `r-final`, overallXp: 1, primaryStatName: 'discipline' };
      await recordTask(data, context);
      throw new Error('expected rate-limit to throw');
    } catch (err) {
      expect(err).to.exist;
      expect(err).to.have.property('code', 'resource-exhausted');
    }
  });
});
