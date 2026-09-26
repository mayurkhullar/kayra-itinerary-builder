# Supplier Source upload engine

This layer is not wired to any screen. A future caller selects candidates with
`PlatformSupplierSourceFilePicker`, then passes a non-empty selection, an existing
Trip ID and the authenticated session UID to `SupplierSourceUploadService`.
Construct the service with `FirestoreSupplierSourceRepository`,
`FirebaseSupplierSourceStorageUploader` and `CallableSupplierSourceCleanupClient`.
The default adapters use the existing Firebase app; cleanup uses `asia-south2`.
Tests inject fakes and never initialize or call production Firebase.

The picker uses file_picker 13's multi-file `pickFiles` and `readAsBytes`, which
work with Web blobs and Android content URIs without shared `dart:io`. Picker
cancellation returns an empty selection. Known file sizes are checked before
reading bytes, and actual byte lengths are validated again. Candidates own an
immutable copy. The entire selection is held in memory, so aggregate selection
size remains a practical memory limit even though each file is capped at 25 MB.

The central extension/MIME mapping is in `SupplierSourceUploadCandidate` and is
tested against `SupplierSourceFile.supportedContentTypes`. Filename normalization
preserves the original name separately, trims whitespace, replaces separators,
control characters, unsafe filename punctuation and repeated dots with `_`, and
lowercases the supported extension. There is no content sniffing or parsing.
Storage IDs, not names, provide uniqueness.

Order is validate all candidates → create uploading package → for each file in
selection order allocate identity/create metadata then await Storage putData →
complete package with ordered fileIds. Each object carries contentType and exactly
`packageId`/`uploadedByUid` custom metadata. Storage paths stay private; no download
URL is requested or stored. Completion returns package identity and ordered IDs
without introducing an extra server read after a successful completion write.

Repository identity callbacks run before writes. This lets rollback address even
an ambiguously failed metadata write. Every allocated file attempt receives the
trusted cleanup callable's exact four-field input. Cleanup continues after errors;
failures carry unresolved file IDs and the original failure category, never raw
Firebase messages. Without file attempts, the engine reads the package and marks
it failed only if still uploading. Missing/already-failed packages need no update.

A completion error also triggers cleanup. If the completion actually committed
but its acknowledgement was lost, the backend rejects rollback of that uploaded
package. The engine reports rollback incomplete and preserves the evidence; it
never directly deletes Storage objects or reopens terminal packages. Interrupted
processes and persistent network failures cannot guarantee rollback: failed
cleanup remains an explicit unresolved result for future recovery tooling.

Progress reports validating/preparing/uploading/finalizing/rollingBack/completed/
failed, zero-based file index, total file count, original filename and per-file
byte counts. Observer exceptions do not interrupt persistence.

Uploads are sequential. User cancellation, automatic retries, durable crash
recovery and upload timeouts are deliberately not implemented. Do not expose a
Cancel Upload button. In-flight writes/uploads must settle before rollback; a
local timeout alone could allow late writes after cleanup. The future UI should
await the operation and handle `SupplierSourceUploadFailure` categories.
