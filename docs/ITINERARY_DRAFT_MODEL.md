# Structured itinerary draft model

Sections before **Canonical v2 architecture** describe the implemented legacy
model. The v2 pure TypeScript model/validator and deterministic Supplier Import
assembly policy are implemented. Its writer, persistent finalizer, Flutter model,
migration, Rules and production extraction cutover remain future work.

The pure entry point is `supplierImportV2Assembly.ts`. It consumes a trusted
complete Snapshot, Resolution aggregate and explicit context (`draftId`, `tripId`,
`actorUid`, `finalizationId`, `createdAt`, `updatedAt`, `policyVersion`). It returns
either an immutable validated V2 candidate with accounting, or deterministic
blockers with no candidate. The compatibility assessment delegates to this same
policy, using a discarded validation-only metadata envelope when no explicit
context is supplied. Safe untouched days, assigned services and package facts
carry automatically; explicit decisions and sparse set/clear overrides win.
Package arrays compact surviving source order; day/service order collisions
block. Manual content has consultant-origin accounting and no supplier locator.
Package lineage and the separate accounting retain trusted sources, staged
identities and correction links. Count capacity is enforced; exact Firestore
byte size and rechecking authorization/revision remain future writer duties.
Nothing in this pure policy persists a draft or seals a Resolution.

`KayraItineraryDraft` is the editable, provider-neutral itinerary structure used
after supplier material has been organized. It contains client-facing travel
content and review markers, without quotation or pricing data.

The draft references a Trip by `tripId`. The Trip remains authoritative for the
client, travel dates, traveller counts, trip type, and hotel category; those
fields are not copied into the draft.

A draft contains ordered days, and each day contains ordered services. Supported
service types are hotel, transfer, activity, meal, sightseeing, free time, and
other. Hotel, transfer, and activity services can carry small typed detail
objects while common fields stay on the service itself.

`sourcePackageIds` records the Supplier Source packages used for the draft. An
individual service may also hold a `KayraItinerarySourceReference` pointing to a
package and optional source file. Provenance never stores Storage paths, download
URLs, raw extracted text, supplier contact data, or supplier costs.

`KayraItineraryReviewIssue` identifies a structured `fieldPath` that needs
consultant review. Its stable severities are `warning` and `blocker`. The model
stores these issues but does not enforce workflow transitions.

All models use strict, deterministic `toMap`/`fromMap` serialization with
explicit persisted enum values. Domain timestamps are UTC `DateTime` values; a
future data layer is responsible for converting Firestore timestamps.

Drafts persist at `trips/{tripId}/itinerary_drafts/{draftId}`. Active Agents can
read and write drafts only for Trips they currently own; active Admins can read
and write drafts under any existing Trip. Deletion is denied for everyone in
v1. The repository accepts only existing, uploaded Supplier Source packages from
the same Trip. Security Rules intentionally enforce the top-level shape and do
not perform arbitrary document lookups for every `sourcePackageId` in a list.

This model deliberately excludes pricing, margins, payments, flights, visa,
AI-provider payloads, extraction confidence scores, and master-record matching.

## Trusted backend draft boundary

The Functions backend mirrors this Dart schema with strict runtime validation.
The `kayra_itinerary_extraction_v2` provider contract is a separate sparse DTO:
it contains extracted facts and their ordering, while unavailable optional
properties and empty optional lists are omitted. Provider output is untrusted
and cannot control the Trip ID, creator UID, draft ID, audit timestamps, day
numbers, service IDs, review issue IDs, or Supplier Source package ID.

Before persistence, the backend strictly validates the sparse DTO, assigns
positive sequential day numbers and deterministic ordering-based service and
review issue IDs, restores every nullable/list/detail field required by this
persisted schema, and applies the existing full domain validator. This expanded
shape alone reaches the writer, so the Firestore and Dart draft contract remains
unchanged.

Package provenance always comes from the trusted job context. A single-file
package is mapped to its sole validated file automatically. For multi-file
packages, the provider may return a compact 1-based `fileIndex`; the backend
checks it against the trusted package file order and maps it to the validated
file ID. Provider-supplied package IDs and raw file IDs are rejected.

When the extraction processor creates a draft, draft creation and the matching
job's `processing` to `completed` transition occur in one Firestore transaction.
This prevents a completed draft from becoming orphaned behind an unfinished job.

## Canonical v2 architecture

The pure backend entry point is `itineraryDraftV2Validation.ts`:
`validateItineraryDraftV2(id, map)` / `itineraryDraftV2FromMap`,
`itineraryDraftV2ToMap` and `serializeItineraryDraftV2`. The document ID is
external to the map. Transport maps use UTC ISO timestamps and date-only
timeline strings; validated timeline/metadata dates retain the existing `Date`
semantics with defensive copies. Package dates remain date-only strings.
Validation freezes detached nested values, rejects malformed ordering instead
of sorting it, and enforces the 256 package-record limit. Exact Firestore byte
capacity and authoritative source membership remain future trusted-boundary
checks; this API performs neither persistence nor Snapshot/Resolution assembly.

Choose **one versioned canonical draft root with embedded first-class package
content** at the existing `trips/{tripId}/itinerary_drafts/{draftId}` path.
The exact new persisted discriminator is `schemaVersion: itinerary_draft_v2`.
The four package sections belong to this draft, not to an independently mutable
adjacent canonical entity. A private finalization receipt is audit evidence,
not a second source of rendered package content.

Why this choice:

- Timeline and package facts have one identity/version and one consistent read.
- Screen, PDF and proposal projections consume the same semantic aggregate.
- Reuse sanitizes one aggregate; it cannot accidentally join a new timeline to
  an old package-content document.
- The bounded root, Resolution lock and audit linkage commit together.
- Package facts preserve their scope; no synthetic day or service is necessary.
- Explicit size limits below keep the root within Firestore capacity.

An adjacent canonical package entity reduces root pressure but adds reads,
missing/stale joins, independent version handling, authorization/projection
surfaces and multi-document consistency to every consumer. Its scale advantage
does not justify that complexity for the bounded first rollout. There is no
automatic overflow fallback to an adjacent entity. A future larger aggregate
would require an explicit new persistence version.

### Version compatibility and rollout

The historical effective contract is `itinerary_draft_v1`. Actual existing draft
documents have **no `schemaVersion` field**. Future readers must recognize their
exact legacy shape and infer v1 in memory; they must not rewrite those documents
or treat missing `packageContent` as a malformed v2 object. Explicit unknown
versions, partial v2 fields and mixed legacy/v2 records are rejected.

The new root retains the legacy fields `tripId`, `title`, `days`,
`sourcePackageIds`, `reviewIssues`, `createdByUid`, `createdAt` and `updatedAt`,
with their existing semantics. `id` remains the document ID. It adds exactly:

| Field | Required shape and purpose | Ownership / ordering |
|---|---|---|
| `schemaVersion` | Literal `itinerary_draft_v2`. | Backend-owned, immutable. |
| `packageContent` | Exact object with required `accommodations`, `inclusions`, `exclusions`, `conditions` arrays; empty arrays allowed. | Canonical reviewed content, never raw Snapshot data. |
| `importResult` | Required import link for this Supplier Import-produced v2 contract: `extractionId`, `resolutionId`, `evaluatedRevision`, `sourcePackageId`, `finalizationId`, `policyVersion`. | Backend-owned and immutable; revision is the active revision used to assemble output. `policyVersion` is `supplier_import_exception_review_v1`. |

This initial v2 contract is for Supplier Import finalization. A reusable library
copy is a separate sanitized projection, not a forged Supplier Import result
with null/fake lineage. A later manual-origin or reuse-to-editable-draft creator
must get an explicit origin-aware contract; it cannot populate `importResult`
with another Trip's private identity.

Keep V2.4 extraction and its exact writer/validator unchanged. The V3 machine
job still produces `supplier_extraction_snapshot_v1`; only the later trusted
finalizer produces `itinerary_draft_v2`. Neither the job contract
`supplier_extraction_v1` nor the current sparse Resolution decision shapes need
to be reinterpreted as canonical v2. Finalization policy is separately versioned.
Existing finalized results and their historical policies never change.

Deploying future v2 support requires version-aware Flutter/backend readers,
strict validators, a trusted writer/finalizer and deliberate Rules/index work
before enabling writes. Old v1 clients cannot read/write v2 through their strict
parser; keep the writer gated until compatible clients are available. Do not
make old clients silently discard new fields on save. No destructive migration
of old drafts or quotations is part of this rollout.

### Package content schema

The following is a schema description, not production code. All listed object
keys are required, including keys whose values may be null; unknown keys are
rejected. Optional semantic values are represented by null, lists by arrays. Every
content string is non-commercial travel content. There is no arbitrary payload,
pricing, supplier-contact or commercial-notes field.

```text
packageContent
  accommodations: PackageAccommodation[]
  inclusions: PackageStatement[]
  exclusions: PackageStatement[]
  conditions: PackageCondition[]

PackageAccommodation
  id, order
  selection: single | alternatives
  options: AccommodationOption[]

AccommodationOption
  id, order
  details: PackageHotelDetails
  provenance: SupplierFactProvenance

PackageStatement
  id, order, category, text
  quantity: positive integer | null
  frequency: text | null
  appliesTo: ServiceType[]
  provenance: SupplierFactProvenance

PackageCondition
  id, order, kind, value
  appliesTo: ServiceType[]
  provenance: SupplierFactProvenance
```

| Common field | Meaning / requirement | Correction and ordering |
|---|---|---|
| `id` | Required deterministic backend ID unique within the draft; never provider-supplied. | Not editable. Derived from trusted extraction/fact identity and destination, not mutable prose. |
| `order` | Required positive contiguous display position within the containing array. | Derived from Snapshot `order` (stable ID breaks ties); not a date or chronology assertion. No package reorder command is introduced. |
| `provenance` | Required nonempty trusted source lineage described below. | Immutable supplier evidence; correction authorship is recorded separately within it. |
| `appliesTo` | Required unique list using `hotel`, `transfer`, `activity`, `meal`, `sightseeing`, `free_time`, `other`. Empty means no narrower service-category restriction stated. | Existing package override supports set/clear; clear becomes `[]`. Never expands into individual service IDs or infers quantities. |

The root arrays define package scope. They are never combined with service
inclusions/exclusions, service notes or day notes. Source order is retained
within each category; filtering/mapping/exclusion closes display-order gaps
without changing surviving relative order. Ordinary finalization does not
deduplicate separate facts based on matching text. Conflicting duplicates are
exceptions; proven intentional exclusions remain auditable.

### Package accommodation

Package accommodation is a **permanent first-class canonical destination**.
Missing day placement, dates or a hotel name is not by itself invalid here.
Each option must preserve at least one meaningful accommodation attribute.
An option with every attribute cleared is invalid; exclude the fact explicitly
instead of emitting an empty placeholder.

`PackageHotelDetails` has exactly these nullable semantic fields:

| Field | Type and purpose | Consultant correction |
|---|---|---|
| `hotelName` | Text; exact supplier-supported hotel/name alternative wording. | Set/clear. |
| `city` | Text; accommodation location, independently supplied. | Set/clear. |
| `orSimilar` | Boolean; null is unstated, false is explicit, true preserves the qualifier. | Set/clear. |
| `checkInDate` | Calendar `YYYY-MM-DD` string or null. | Set/clear; never taken from Trip/day dates. |
| `checkOutDate` | Calendar `YYYY-MM-DD` string or null. | Set/clear; when both dates exist, strictly after check-in. |
| `nightCount` | Positive safe integer or null; explicit duration fact. | Set/clear; never calculated from dates. |
| `roomType` | Text or null. | Set/clear. |
| `mealPlan` | Text or null. | Set/clear; not derived from package meals. |
| `numberOfRooms` | Positive safe integer or null. | Set/clear; not derived from travellers. |
| `supplierStarRating` | Text or null; rating stated for this itinerary. | Set/clear; no master-rating substitution. |

New package date fields use date-only strings; legacy timeline dates keep their
existing date/Timestamp representation. Version-aware adapters must handle that
deliberately, without timezone conversions or migrating existing data.

One ordinary package accommodation fact becomes one `selection: single` entry
with exactly one option. It is an accommodation statement, not a claim of a
confirmed booking, one hotel for every night, or a hidden anchor day. Explicit
spans remain exactly as supplied, including partial spans; null remains unknown.
Contradictory dates or a conflicting explicit night count create an exception;
validation may detect a conflict but must not rewrite either fact.

The required `selection` and nonempty `options` fields describe the relationship
between accommodation options. The backend owns this envelope; its lineage is
the union of its options' provenance. Individual attributes remain correctable
through the existing accommodation overrides. Changing an option relationship
requires the typed grouping decision below, not an arbitrary envelope patch.

`selection: alternatives` requires at least two independently identified
options, their individual details/provenance and an explicit alternative
relationship. It means **one of these**, never multiple guaranteed stays. The
current Snapshot/Resolution have no cross-fact hotel-alternative relationship.
Consequently the initial adapter must not manufacture one: explicit combined
hotel wording and `orSimilar` can survive in a single option; genuinely separate
alternative options require a later narrowly typed consultant grouping command
before this branch can be emitted. That future command must reference the exact
package fact IDs, record consultant authorship of the relationship and consume
each fact once. It must not infer order, nights or shared fields across options.
This is a defined extension point, not permission to add controls in this task.

Several independent global accommodations remain several entries. If the source
does not distinguish alternatives from multiple stays, that is a real structural
exception. Merely retaining all rows as booked hotels is not a safe default.
An explicit multi-hotel relationship that cannot currently be represented in
the Resolution remains blocked, with evidence intact, until the typed grouping
workflow exists or the consultant supplies a valid supported disposition.

### Package inclusions and exclusions

These are **separate arrays of structured statements**, not a generic string
list. Both use the same exact fields:

| Field | Requirement / meaning | Consultant correction |
|---|---|---|
| `category` | Required: `accommodation`, `meal`, `guide`, `water`, `entrance`, `transport`, `visa`, `other`. | Existing set-only category override. |
| `text` | Required nonempty semantic statement; no marketing, amount or supplier identity. | Existing set-only text override. |
| `quantity` | Nullable positive safe integer; only an explicit quantity. | Set/clear. |
| `frequency` | Nullable text, such as “per stay”; separate from quantity. | Set/clear. |
| `appliesTo` | Required category restriction array as above. | Set/clear. |
| `id`, `order`, `provenance` | Required common metadata. | Backend-owned. |

An inclusion cannot be changed into an exclusion by moving it between arrays or
changing its category. The source fact kind controls the array; an incompatible
reclassification requires a deliberately supported workflow. “Five lunches”
and “three dinners” remain distinct with their own quantity and provenance.
No expansion into day services, repetition on every day or quantity inference.

The `visa` category remains readable because it exists in the Snapshot
vocabulary, but visa/flight semantic content is not enabled for default land
package finalization by this design. Misclassified ancillary content is a
classification exception, not a route into `other` or package notes. See the
ancillary boundary in the staging model.

### Conditions and important notes

`PackageCondition.kind` is required and retains the Snapshot vocabulary:
`operating_basis`, `vehicle`, `class`, `ticket_scope`, `availability`,
`payment_basis`, `guide`, `other`. `value` is required nonempty non-commercial
text. Both have existing set-only overrides. `appliesTo`, identity, ordering and
provenance follow the tables above. A genuine miscellaneous supplier operating
note uses `kind: other`; there is no untyped extra notes array.

Conditions describe supported operation, not extraction uncertainty. For
example, “subject to availability” belongs here; “unclear which hotel applies”
belongs to review issues. `payment_basis` can preserve an operational qualifier
such as “direct payment” only where it contains no payment amount, commercial
terms or pricing value. It is not a commercial escape hatch. Kayra's locked
standard proposal terms remain separate from supplier package conditions.

### Trusted fact provenance

Each package statement, condition and accommodation option has this exact
Supplier-derived lineage object:

| Field | Requirement / purpose | Ownership |
|---|---|---|
| `origin` | Required literal `supplier`. Corrections do not fabricate a new supplier fact. | Backend. |
| `extractionId`, `sourcePackageId` | Required trusted identities matching `importResult`. | Backend, immutable. |
| `contributors` | Required nonempty ordered array of `{stagedFactId, sources}`. Each source is `{supplierSourceFileId, sourceLabel}` with nullable file/label. | IDs checked against the complete Snapshot and trusted package membership. |
| `resolutionId`, `evaluatedRevision` | Required linkage to the sealed decision set used to assemble this value. | Backend. |
| `decisionIds` | Required array, empty for default carry-through; otherwise exact contributing decisions. | Backend, never inferred from display text. |
| `fieldChanges` | Required ordered array of `{field, operation}` where operation is `set` or `clear`; field is a closed typed name from that entity's override contract. Empty means extracted fields untouched. | Derived from decisions; actor/time remain in sealed decision/audit records. |

One fact is one contributor in the initial adapter. The shape can express
several validated contributors without replacing their evidence with one guessed
source; it does not authorize a new merge operation. Preserve source-reference
order and distinct locators. An omitted file in an already-valid multi-file
Snapshot means trusted **package-level** provenance, not guessed file identity;
single-file normalization should retain that trusted sole file. Missing optional
page labels do not require a confirmation click. Invalid file/package links
block as integrity failures, not consultant-overridable warnings.

The private receipt records each fact's output identity/field targets, including
defaults, mapping, exclusions, clear operations and ancillary handling. It
supplies lineage for timeline fields whose legacy `sourceReference` cannot
express all contributors. Excluded/cleared values remain only in immutable
Snapshot/decision history, not copied into public package content.

Future manual package content must use an explicit `origin: consultant` branch
with actor/audit linkage and no fabricated Supplier references. That branch and
manual package creation are not enabled by this initial Supplier Import contract.

### Size, reads and rendering boundary

The bounded root and private audit receipt limits, four-document atomic commit,
and overflow behavior are specified in staging-model section 25.7. The private
itinerary editor reads one versioned root for timeline and package content;
source inspection can separately load authorized Snapshot/audit evidence.

Client web/PDF/proposal renderers read an allowlisted projection of this same
root: accommodation summary from `accommodations`, what is included from
`inclusions`, what is excluded from `exclusions`, and important notes from
`conditions`. Display quantity, frequency, alternatives and applicability
without converting them to implied services or guarantees. Empty sections are
omitted. A package-only valid draft can have `days: []`; do not invent a day to
enable rendering. Proposal pricing and Quote Prepared gates remain separate.

Never expose the private root directly through a public sharing link. Strip
`sourcePackageIds`, `importResult`, provenance, internal issue/audit details and
restricted operational content server-side. Free text also needs content-aware
privacy validation: field allowlisting alone does not remove embedded supplier
names, contacts, client details or confirmation identifiers. Unsafe text must
be corrected or excluded from the publication/reuse projection with a visible
exception, not silently changed into a different itinerary claim.

Reuse produces an independent sanitized library projection with new public
content IDs/order and useful travel facts only. It removes Supplier identity,
documents/URLs, all extraction/package/file/fact/decision IDs and labels,
client identity/contact data, commercial content and internal operations. Any
restricted copy lineage remains in a separate server-only audit record; it is
not delivered to the copying Agent. Hotel property names may remain useful
travel content; supplying vendor identity may not. No later edit propagates
back to the source itinerary.
