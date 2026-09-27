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
dedicated authenticated callable Function validates Trip access and the
uploaded source package before creating a queued job with the Admin SDK. Backend
processing owns all later transitions.

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
the job ID, status, and whether it was newly created. Source inspection, AI
processing, and draft creation remain outside the callable.

## Trusted source reader

Future processors must validate Supplier Source evidence through the internal
server-side source reader before processing it. Firestore metadata alone is not
sufficient: the reader cross-checks each private Storage object's canonical
path, content type, size, package identity, and uploader identity.

The reader preserves the Package's exact `fileIds` order and returns only trusted
provider-independent descriptors. Validation inspects object metadata without
bulk-loading file contents. Files remain private, and no AI provider is selected
or called by this layer.

## Trusted processor core

The internal, provider-independent processor transactionally claims only a
well-formed queued job. The claim changes `queued` to `processing`, so competing
workers and later invocations cannot run the same job again. It then validates
the Supplier Source package with the trusted source reader, invokes one injected
provider, and treats the provider's structured result as untrusted input to the
draft validator.

Source-reader errors map to the existing public failure vocabulary:
`SOURCE_UNAVAILABLE` and `INVALID_SOURCE_INTEGRITY` become
`source_unavailable`, while `UNSUPPORTED_SOURCE` becomes `unsupported_source`.
Provider execution failures become `extraction_failed`; invalid structure or
provenance becomes `invalid_extraction_result`; and atomic persistence failures
become `draft_persistence_failed`. Raw provider and infrastructure errors are
not stored on the job.

Successful finalization allocates a backend draft ID, creates the draft, and
changes the still-processing job to `completed` with the same draft ID in one
Firestore transaction. Ordinary failures transactionally change only a
processing job to `failed`. If recording that failure also encounters an
infrastructure error, the processor reports an internal operational failure and
the job may remain processing for later manual recovery.

The processor remains internal and is invoked only by the Firestore create
trigger described below. It is not exposed as a callable or HTTP endpoint.

## Vertex AI provider adapter

The first production provider adapter implements `ItineraryExtractionProvider`
with the Google Gen AI Node SDK and Vertex AI `gemini-3.5-flash` in the `global`
location. It uses Application Default Credentials and runtime Google Cloud
project discovery; it does not use an API key. The adapter remains internal and
is reached only through the trusted processor, never directly from a callable.

Each job makes exactly one model generation call. The versioned
`kayra_itinerary_extraction_v1` prompt limits the task to factual extraction,
and controlled generation requests `application/json` with a JSON schema that
contains only the fields accepted from a provider by the trusted draft
validator. Parsed output remains untrusted and receives full structural and
provenance validation before persistence. Prompts, responses, provider/model
metadata, and token usage are not persisted in domain documents.

PDF, JPEG, PNG, WebP, and UTF-8 plain text use their existing private Firebase
Storage objects through ordered `gs://` parts. CSV is read one file at a time,
bounded again by the 25 MB source limit, decoded as strict UTF-8, and included as
text. No public, signed, or download URL is created.

DOC, DOCX, XLS, and XLSX remain valid Supplier Source uploads but are not native
inputs for this adapter. Any package containing one of these formats is rejected
before the model call and becomes `unsupported_source`. Other Vertex/model
execution failures become `extraction_failed`; successfully parsed output that
does not satisfy Kayra's schema becomes `invalid_extraction_result`.

## Firestore processing trigger

The second-generation `processItineraryExtractionJob` Function listens only for
document creation at
`trips/{tripId}/itinerary_extraction_jobs/{jobId}`. It passes the trusted path
parameters to the existing processor, which reloads and validates the
authoritative job rather than trusting snapshot fields.

Firestore/Eventarc delivery may occur more than once. The processor's atomic
`queued -> processing` claim makes duplicate deliveries safe; an already
claimed or terminal job becomes a successful no-op. A business extraction
failure that the processor records as terminal `failed` is also treated as a
handled event. An unresolved infrastructure or failure-finalization error is
re-thrown so the event infrastructure can retry it.

The trigger runs in `asia-south2` with concurrency 1 and at most two instances,
keeping parallel model spend deliberately bounded. Live Gemini access remains
behind `ItineraryExtractionProvider` and uses the configured runtime service
account through Application Default Credentials.
