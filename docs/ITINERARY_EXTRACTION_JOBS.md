# Itinerary extraction jobs

An itinerary extraction job is the durable, provider-independent record for
turning one completed Supplier Source Package into one structured itinerary
draft. Jobs are stored at
`trips/{tripId}/itinerary_extraction_jobs/{jobId}`.

The state machine is `queued -> processing -> completed` or
`queued -> processing -> failed`. Completed and failed jobs are immutable
terminal records. A future retry creates a new job rather than reopening one.
A completed job records its resulting draft ID; a failed job records only a
stable machine-readable failure code.

Review warnings and blockers belong to the resulting Itinerary Draft, not the
job status. A job may therefore be completed while its draft still needs human
review.

Flutter clients can read jobs only for Trips available to the current active
Agent or Admin. Direct client creation, updates, and deletion are denied. A
future authenticated callable Function will validate Trip access and the
uploaded source package before creating a queued job with the Admin SDK. Backend
processing will own all later transitions.

This contract stores no prompts, responses, source text, provider request IDs,
or other provider details. No AI provider is selected by this model.

## Request callable

`requestItineraryExtraction` is a second-generation callable in `asia-south2`.
It accepts exactly `tripId` and `sourcePackageId`. The authenticated caller must
have a company email, an active Agent/Admin profile, and access as the current
Trip owner or Admin. Only an uploaded, same-Trip Supplier Source Package with at
least one file qualifies.

The Function creates only queued jobs. When a queued or processing job already
exists for the package, it returns that active job instead of creating another.
Completed and failed jobs allow a new queued attempt. The response contains only
the job ID, status, and whether it was newly created. Actual source inspection,
AI processing, and draft creation remain unimplemented.

## Trusted source reader

Future processors must validate Supplier Source evidence through the internal
server-side source reader before processing it. Firestore metadata alone is not
sufficient: the reader cross-checks each private Storage object's canonical
path, content type, size, package identity, and uploader identity.

The reader preserves the Package's exact `fileIds` order and returns only trusted
provider-independent descriptors. Validation inspects object metadata without
bulk-loading file contents. Files remain private, and no AI provider is selected
or called by this layer.

A future processor will pass structured provider output through the trusted
itinerary draft validator/writer before marking a job completed. The boundary
attaches backend-owned identity, provenance, creator, and audit fields and
creates a draft only after the full Dart-compatible structure validates.
