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

## V3 staging-result job-contract migration

The sections above describe the deployed V2.4 draft-producing contract. The V3
pipeline changes the machine result into an immutable Supplier Extraction
Snapshot that must be reviewed and resolved before a canonical itinerary draft
is finalized. The extraction job still represents machine execution only. Its
successful completion does not mean that consultant review or itinerary
finalization is complete.

The Supplier Extraction Snapshot, resolution and finalization boundaries are
defined in
[`SUPPLIER_EXTRACTION_STAGING_MODEL.md`](SUPPLIER_EXTRACTION_STAGING_MODEL.md).
This section defines the additive job-document migration needed to link that
model without rewriting historical V2.4 records.

### Result discriminator and identifiers

Add a server-owned `resultType` discriminator with exactly these values:

- `itinerary_draft`: the machine job directly produced a canonical
  `KayraItineraryDraft` under the deployed V2.4 contract.
- `supplier_extraction`: the machine job produced a complete immutable Supplier
  Extraction Snapshot for consultant review.

Keep separate nullable result fields:

- `resultingDraftId`
- `resultingExtractionId`

Separate fields make the result union explicit and keep a snapshot ID from being
mistaken for a draft ID. A generic `resultId` would require every reader and
write path to interpret the discriminator before it could even choose a
collection, and would make accidental cross-type writes easier.

Every newly created job stores both result fields. Queued and processing jobs
store both as null. A failed job also stores both as null. A completed job stores
exactly the identifier selected by `resultType` and keeps the other null. The
backend must reject mixed or partial combinations, including both IDs, the wrong
ID for the discriminator, an outcome on an unfinished job, a missing successful
ID, or a successful ID on a failed job.

Historical documents do not gain synthetic fields in Firestore. A strict reader
recognizes two complete schemas rather than accepting arbitrary optional keys:

1. A legacy field set has no `resultType`, `resultingExtractionId` or
   `extractionContractVersion`. It is interpreted as `itinerary_draft` under the
   effective legacy contract described below. Its existing status,
   `resultingDraftId` and `failureCode` invariants continue to apply.
2. A versioned field set contains all three new fields and must satisfy the new
   discriminated-result invariants. A document containing only some of the new
   fields is malformed.

This inference is safe because no historical job can represent a Supplier
Extraction Snapshot. It preserves completed V2.4 draft links without a
destructive data migration.

### Machine status and consultant review

Keep the existing job states unchanged:

```text
queued -> processing -> completed
queued -> processing -> failed
```

For either result type, `completed` means only that the machine job successfully
persisted its declared result. It does not mean that a supplier extraction was
reviewed, resolved or converted to canonical itinerary content.

Consultant workflow belongs to the separate resolution aggregate described in
the staging model. That aggregate owns states such as unresolved, in review,
ready to finalize, finalized or superseded when those states are implemented.
Finalization creates or updates canonical itinerary content and seals the
resolution. It does not reopen or advance the terminal extraction job.

### Server-owned extraction contract

Add `extractionContractVersion` as server-owned product metadata. Recommended
stable values are:

- `itinerary_draft_v1` for the effective historical V2.4 job contract; legacy
  documents infer this value in memory and are not rewritten.
- `supplier_extraction_v1` for the first V3 staging-result job contract.

The contract version selects the trusted processor/result pathway and is part
of active-job deduplication. It is distinct from both of these values:

- The Gemini prompt/provider version, such as
  `kayra_itinerary_extraction_v3_staging`, records operational extraction
  behavior. It belongs in trusted snapshot metadata and may change without
  changing the job contract when the result semantics remain compatible.
- The Supplier Extraction Snapshot schema version, currently
  `supplier_extraction_snapshot_v1`, describes the persisted snapshot shape and
  its reader/validator. It does not select a provider or determine job
  deduplication by itself.

A prompt revision does not require a new job contract merely because wording or
model behavior changed. A result-shape or lifecycle change that makes active
jobs incompatible requires a new `extractionContractVersion`.

### Request cutover and deduplication

The callable request remains exactly `tripId` plus `sourcePackageId`. The client
must never send `resultType`, a provider name, prompt version or contract
version. The callable assigns `resultType` and `extractionContractVersion` from
one server-owned current-contract constant.

Use this cutover sequence:

1. Keep ordinary production requests on V2.4 while backward-compatible job
   readers and a contract-aware processor are introduced.
2. The processor interprets a legacy job as `itinerary_draft_v1` and routes it
   only to the existing V2.4 draft path. It routes an explicit
   `supplier_extraction_v1` job only to the V3 snapshot path.
3. After V3 persistence, consultant resolution, deterministic finalization and
   the review entry point can preserve every staged fact category, change the
   callable's single server-owned current contract so all new requests create
   `supplier_extraction` jobs.
4. Keep the legacy reader and V2.4 processing route for historical active jobs
   and records. They are compatibility paths, not user-selectable alternatives.

An active-job deduplication identity is:

```text
sourcePackageId + extractionContractVersion
```

The result type must also be validated as the one required by that contract,
but need not duplicate the dedup key. Prompt version is not part of the key.
Only queued or processing jobs with the same effective contract qualify for
deduplication. Completed and failed jobs permit a new attempt. Consequently, a
historical V2.4 job does not prevent a V3 request after cutover, and a queued or
processing legacy job is never returned as though it were a V3 job.

The current source-package query can remain the authorization snapshot and the
backend can filter its returned jobs by effective contract, avoiding a
client-supplied selector. If a future query filters both fields in Firestore,
its required index must be introduced deliberately.

### V3 persistence and job-completion atomicity

A Supplier Extraction Snapshot can exceed one Firestore batch, so all children
and the job cannot be created in one transaction. Preserve the existing
`writing`/`complete` visibility boundary and move final promotion into the job
finalization boundary:

1. Claim the matching V3 queued job as processing and reload the trusted source
   package.
2. Make exactly one V3 provider call, validate the DTO and trusted-normalize the
   complete snapshot in memory.
3. Use one backend-determined extraction ID for the job. Deriving it
   deterministically from the job ID is the smallest way to make partial-write
   recovery address the same root without putting a result ID on an unfinished
   job.
4. Create the snapshot root as `writing`, then create all immutable children in
   bounded batches. A partial root remains unreadable to trusted readers and
   Firestore clients.
5. After every required child write succeeds, run one Firestore transaction
   that revalidates the still-processing job, its contract/result type and the
   writing root. In that transaction, promote the root to `complete` and update
   the job to `completed` with `resultingExtractionId`; keep
   `resultingDraftId` and `failureCode` null.

The last transaction makes a complete readable snapshot and its completed job
link visible together. It prevents both a completed V3 job pointing at a
writing snapshot and an unlinked complete snapshot. A failure before that
transaction leaves only an invisible `writing` root. If the final transaction's
acknowledgement is ambiguous, the processor must reload the job and root: an
already-completed job linked to the same complete extraction is success, while
failure finalization may update only a job that is still processing. It must
never overwrite a committed completion.

The current snapshot repository promotes its root independently. V3 production
composition must therefore split snapshot writing from final promotion rather
than calling that standalone promotion and then updating the job. Cleanup or
recovery for abandoned `writing` roots is an operational follow-up; such roots
remain inaccessible and must not be treated as successful results.

This two-phase visibility protocol preserves all normalized source facts before
review. Later canonical finalization follows the staging model's disposition
invariant and is independent of extraction-job completion.

### Failure-code compatibility

Keep all historical failure codes readable. The existing
`draft_persistence_failed` remains valid for `itinerary_draft` jobs and is not
renamed in stored history.

Add `supplier_extraction_persistence_failed` for a V3 job whose validated
snapshot cannot be fully persisted and atomically linked. The existing
`source_unavailable`, `unsupported_source`, `extraction_failed` and
`invalid_extraction_result` codes remain meaningful for both contracts. A V3
job must not record `draft_persistence_failed`, because extraction no longer
creates a draft, and a draft-producing job must not record the new snapshot
failure code.

Raw provider or persistence errors remain absent from job documents.

### Flutter compatibility boundary

The later Flutter migration needs a strict result union, not a new consultant
workflow in the job model. It must:

- read the exact legacy field set and infer `itinerary_draft_v1` plus
  `itinerary_draft`;
- read the exact versioned field set, including `resultType`,
  `extractionContractVersion` and `resultingExtractionId`;
- reject invalid status/result/failure combinations;
- render a completed draft result as **Draft ready** and retain its canonical
  draft destination; and
- render a completed supplier-extraction result as **Extraction ready for
  review** and route it to the future Supplier Import review entry point.

Queued and processing copy may stay machine-oriented. The UI must not infer a
draft from `completed` alone. The callable request payload remains unchanged,
and Flutter never selects a provider or contract version.

### Firestore Rules impact

No extraction-job Rules schema change is required for these metadata fields.
Current Rules grant owner/Admin reads through the parent Trip and deny all
client creates, updates and deletes, so the Admin SDK remains the only writer.
The existing Supplier Extraction rules already expose only `complete` roots and
their machine-owned children under the same owner/Admin boundary. Any future
resolution-write rules remain a separate, deliberate change.

### Backward-compatibility matrix

| Record | Effective interpretation | Required outcome |
|---|---|---|
| Historical V2.4 `queued` | Missing new fields implies `itinerary_draft_v1` / `itinerary_draft`. | `resultingDraftId` and `failureCode` are null. |
| Historical V2.4 `processing` | Same legacy inference; eligible only for the legacy processor route. | `resultingDraftId` and `failureCode` are null. |
| Historical V2.4 `failed` | Same legacy inference and terminal machine failure. | `resultingDraftId` is null and the historical failure code is valid. |
| Historical V2.4 `completed` | Same legacy inference and canonical draft result. | Valid `resultingDraftId`; `failureCode` is null. |
| New V3 `queued` | Explicit `supplier_extraction_v1` / `supplier_extraction`. | Both result IDs and `failureCode` are null. |
| New V3 `processing` | Same explicit V3 contract; only the V3 processor route may claim it. | Both result IDs and `failureCode` are null. |
| New V3 `failed` | Terminal machine failure; consultant review never starts. | Both result IDs are null and the failure code is valid for V3. |
| New V3 `completed` | Complete immutable snapshot ready for review. | Valid `resultingExtractionId`; `resultingDraftId` and `failureCode` are null; referenced root is `complete`. |

Reject every other combination. This includes partial presence of new fields,
unknown result or contract values, a contract/result mismatch, either result ID
on queued/processing/failed jobs, no matching result ID on completed jobs, both
IDs, a failure code on completed jobs, or legacy documents whose existing
status/outcome invariants do not hold.

### Stale active jobs

Contract-aware deduplication prevents an old active V2.4 job from being returned
as the result of a V3 request. It does not solve a queued or processing job that
is stale within the same contract; that job would still deduplicate forever.

Stale-job recovery remains a separate required follow-up. It should use a
server-owned lease/age policy and an auditable terminalization or recovery path,
never a client-controlled bypass. Deterministic extraction identity and the
`writing` visibility state keep a future V3 recovery from creating multiple
visible snapshots, but they do not by themselves authorize reclaiming a
processing job or making another model call.

### Recommended implementation checkpoints

1. Extend TypeScript and Dart job readers with the strict legacy/versioned
   union, result invariants, `extractionContractVersion`, the new result ID and
   V3 persistence failure code. Keep production job creation on V2.4.
2. Extend backend job-store tests for both schemas, contract-aware claims,
   result-specific completion methods and rejection of every mixed state.
3. Refactor Supplier Extraction persistence into `writing`, child-write and
   final-promotion phases. Add failure, ambiguous-commit and abandoned-writing
   tests without wiring the production trigger.
4. Add a V3 processor composition that uses the existing trusted source reader,
   standalone V3 provider and trusted normalizer, then atomically promotes the
   snapshot and completes the job. Keep the V2.4 route unchanged.
5. Deploy the dual-contract processor/trigger while the callable still creates
   legacy V2.4 jobs. Verify historical queued, processing, failed and completed
   records remain readable and route correctly.
6. Update the Flutter reader/controller/status presentation so legacy draft
   results and V3 review results are distinguished truthfully. The full review
   workspace remains a later feature.
7. Implement consultant resolution, deterministic finalization and its review
   entry point under the staging model. Verify every staged fact receives a
   valid disposition before canonical output can be created.
8. Change the callable's single server-owned current contract to V3 and make
   active deduplication contract-aware. Do not add a client version selector.
9. Add stale active-job recovery as its own audited backend task.
