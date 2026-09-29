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

## Format-agnostic semantic contract

An extraction job processes one trusted Supplier Source Package; the supplier,
layout and capture channel do not select a different itinerary schema. File
uploads today and future pasted-text, email, WhatsApp or connector adapters must
all converge on the shared Supplier Source boundary, semantic extraction,
trusted normalization and the same `KayraItineraryDraft` contract. Future
channel integrations are adapters, not separate extraction domains.

The detailed current/target channel matrix and Source Package invariants are in
[`SUPPLIER_SOURCE_UPLOAD_ENGINE.md`](SUPPLIER_SOURCE_UPLOAD_ENGINE.md). Direct
email and WhatsApp ingestion are future capabilities and must not be treated as
implemented by the current job pipeline.

## Partial-source normalization

Jobs may complete with a trustworthy but incomplete draft. The processor and
provider must preserve supported facts, omit unsupported values and create
review issues for important ambiguity. They must not invent dates, chronology,
hotel continuity, service classifications or relationships merely to satisfy a
complete itinerary shape.

Explicit source day/date/service relationships are preserved. Undated or
unassigned facts are not distributed across arbitrary days. Global facts keep
their declared package-wide scope and are not copied onto every service unless
the source explicitly makes that mapping.

The current persisted draft has no first-class collection for unassigned
services or package-level facts: services exist only within ordered days. When a
fact cannot be mapped safely, a review issue can identify the problem but cannot
fully preserve that structured fact. A future staging/import representation or
consultant-mapping workflow is required. Until then, normalization must not
fabricate a day or duplicate global content to work around the gap.

Commercial pricing, supplier costs, margins, payment information and commercial
terms remain outside the itinerary draft. An operational statement mixed with a
price must be separated semantically: preserve the non-commercial fact in an
appropriate supported domain, while excluding the monetary value. Flights and
visa remain outside the current day-service draft rather than being forced into
`other` services.

## Quality policy and validation

Extraction is optimized in this order: source fidelity, completeness, semantic
structure, uncertainty handling, provenance, presentation compactness, then
latency. A 20–30 second extraction is currently acceptable when it materially
improves quality. This policy does not itself change provider-call count or
runtime settings.

Maturity requires the multi-supplier validation corpus defined in
[`SUPPLIER_SOURCE_UPLOAD_ENGINE.md`](SUPPLIER_SOURCE_UPLOAD_ENGINE.md), including
structured and narrative PDFs, tables, plain text, screenshots, global facts,
incomplete chronology, mixed commercial content, multi-file packages and poor
quality scans. Validation must detect missing facts, inventions,
misclassification, chronology errors, uncertainty defects, provenance errors,
commercial leakage and unnecessary duplication.

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
`kayra_itinerary_extraction_v2_4` prompt limits the task to factual extraction
and captures each itinerary-relevant operational fact once. Its service-boundary
policy consolidates repeated mentions, keeps one supplier item as one service,
and excludes headings, narrative, and promotional boilerplate from service
creation. Controlled generation requests `application/json` with one stable,
sparse service object: unavailable optional properties and empty optional lists
are omitted, and the provider does not generate structural IDs or day numbers.
An explicit source day date must populate the structured date field, while
unsupported date inference remains forbidden. Short operational qualifiers are
retained once in the most specific existing field. Times remain attached only
to their explicitly associated event or service.

Hotel check-in and check-out dates require an explicit hotel date or
source-provided stay span; a dated itinerary day or an overnight-stay statement
alone does not establish them. The root title preserves an explicit supplier
title or uses only neutral, source-supported facts. Operational qualifiers stay
in one appropriate field rather than being repeated. These rules apply by
semantic meaning across supplier formats and destinations, without relying on a
particular source layout or benchmark wording.

Transfer operating basis is populated only when the source explicitly supports
it; a vehicle description or use of a travel pass does not imply private,
shared, or scheduled service. Traveller movement from an origin to a destination
by train belongs to one transfer service, while a rail pass product is not
itself a transfer. An activity's SIC/shared/private operating basis is preserved
once in the most appropriate existing field rather than stored as its activity
type or repeated across fields. Extraction
uncertainty belongs in `reviewIssues` and is not duplicated into day or service
notes; genuine supplier notes and availability conditions remain itinerary
facts.

An explicit continuous hotel span covers its intervening nights without noisy
warnings. When an overnight transition instead depends on assuming that an
unstated prior hotel continues, the provider creates a concise warning rather
than inventing accommodation. PDF services may carry a compact `Page N` source
label when the supporting page is identifiable; the label remains optional,
and trusted package/file identity continues to come only from the backend.

Parsed output remains untrusted. A dedicated v2 boundary validates it, assigns
deterministic day/service/review identities, restores the complete persisted
draft shape, and then passes that result through the existing strict domain
validator. Supplier Source package identity comes only from trusted job context.
For multi-file packages, a validated 1-based provider `fileIndex` maps through
the source reader's trusted file order; single-file packages are mapped
automatically. The persisted Firestore/Dart draft schema is unchanged. Prompts,
responses, provider/model metadata, and token usage are not persisted in domain
documents.

When a provider response ends because of `MAX_TOKENS`, logs include only safe
aggregate response size, brace-boundary booleans, and counts of fixed JSON object
keys. Candidate values and source content are never logged. The persisted
itinerary domain and its validation remain unchanged.

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
