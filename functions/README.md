# Kayra Firebase Functions

TypeScript backend foundation for the existing `kayra-crm-v1` project.
Use Node.js 22, as declared in `package.json`.

From this directory:

```sh
npm ci
npm run build
npm test
```

`src/index.ts` exports one v2 callable, `cleanupSupplierSourceUpload`, in
`asia-south2`. No deployment is performed by the build or tests. The Admin SDK
uses the runtime's default Firebase configuration and Storage bucket (the current
project's generated bucket is `kayra-crm-v1.firebasestorage.app`); no credentials
or bucket name are hard-coded into function code.

## Supplier source rollback

Input is exactly `{tripId, packageId, sourceFileId, fileName}`. The server derives
`trips/{tripId}/supplier_sources/{sourceFileId}/{fileName}`. All identifiers must
be non-empty path segments; filenames also reject `..`. No sanitization occurs.
The future Flutter caller must select the same Functions region.

Every future uploaded object must carry custom metadata `packageId` and
`uploadedByUid`. The package ID must match the requested package, and the uploader
must match the package and any existing source-file record. Admins and reassigned
Trip owners may act for the original uploader but cannot bypass these checks.

Cleanup requires a signed-in company account, an active Agent/Admin profile,
an existing Trip owned by the Agent (or any existing Trip for Admin), and an
existing matching `uploading`/`failed` package. Source-file metadata may be absent.
Existing metadata must match the Trip, package, canonical path, and uploader.

After validating all available identities, a Firestore transaction rechecks
authorization/identity and changes `uploading` to terminal `failed` with a server
`updatedAt`. This is necessary to prevent a concurrent upload completion between
the state check and Storage deletion. A package already `uploaded` is rejected.
The existing monotonic Firestore rules must be in force before deployment; any
future privileged backend writers must preserve the same terminal-state rule.
Cleanup keeps the package as a historical failed record and does not change its
file list, uploader, Supplier linkage, or creation audit fields.

Storage deletion uses generation and metageneration preconditions. Only after
successful deletion (or an already-missing object) does another transaction
revalidate and delete matching file metadata. Missing objects/metadata are safe
to retry; failed deletes leave metadata intact. A partial service failure can
leave a failed package with remaining cleanup work; repeat the same request.
These two services do not provide a shared atomic transaction.

The response is `{cleaned: true, storageDeleted, metadataDeleted}`. It contains
no document contents or download URLs. Logs contain only opaque identifiers,
operation stages, sanitized error codes, and deletion outcomes.

Node's built-in tests use in-memory SDK doubles and do not contact Firebase.

This follows the Firebase CLI's TypeScript setup without optional lint tooling.
TypeScript strict checking is enabled. Dependencies and compiled output are
ignored by Git; commit the npm lockfile for reproducible installs.
