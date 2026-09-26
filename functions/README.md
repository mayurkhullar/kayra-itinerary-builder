# Kayra Firebase Functions

TypeScript backend foundation for the existing `kayra-crm-v1` project.
Use Node.js 22, as declared in `package.json`.

From this directory:

```sh
npm ci
npm run build
```

`src/index.ts` currently exports nothing. No HTTP endpoints, callable functions,
triggers, or cleanup workflow are implemented. Future functions should use
explicit `firebase-functions/v2` imports and the Firebase Admin SDK.

This follows the Firebase CLI's TypeScript setup without optional lint tooling.
TypeScript strict checking is enabled. Dependencies and compiled output are
ignored by Git; commit the npm lockfile for reproducible installs.
