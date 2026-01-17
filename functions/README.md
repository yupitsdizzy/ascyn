This folder contains Firebase Cloud Functions for Ascyn.

Functions:
- `recordTaskCompletion` (callable): records a task completion as an xp_event and updates character aggregates transactionally.
- `undoEvent` (callable): creates a reversal event and marks the original event reversed; updates aggregates.

Local testing / deploy:
1. Install dependencies: `cd functions && npm install`
2. Use Firebase emulator or deploy: `firebase emulators:start --only functions,firestore` or `firebase deploy --only functions`

Notes:
- These functions expect the client to call them as authenticated users (callable functions use `context.auth.uid`).
- You should review and expand validation for production (stat name validation, XP caps, rate-limiting, auditing).