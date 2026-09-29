# Supplier extraction staging model

## 1. Problem statement

Supplier evidence arrives as chronological PDFs, narrative documents, tables,
email bodies, copied messages, screenshots, scans, text and CSV. Future email,
WhatsApp and other connectors will add capture convenience, but must not create
separate itinerary domains.

The existing extraction path works well when the source already resembles an
ordered itinerary. A supplier source can also contain genuine itinerary facts
without dates, day assignments or service relationships. It may declare one
hotel globally, list package inclusions separately, mix flight or visa facts
with land services, or include commercial values next to operational facts.

Kayra needs a trusted intermediate representation that preserves what the
supplier actually said before a consultant resolves it into the canonical
itinerary. The intermediate representation must accept incomplete structure
without inventing chronology, duplicating global facts or discarding facts that
do not fit the current day-centric draft.

## 2. Why the current day-centric draft is insufficient

`KayraItineraryDraft` contains a title, ordered days, root source-package IDs and
review issues. Services exist only inside a day. Each day requires a positive
day number and a title. The root has no collection for unassigned services,
package accommodations, package inclusions, package exclusions or operating
conditions.

That model is appropriate for reviewed client itinerary content. It is not a
lossless import boundary for sources such as:

- four tours with no stated order or dates;
- one hotel named for a package without a check-in/check-out span;
- multiple hotels with no safe night allocation;
- a coach, guide, meal plan or private basis stated once for the whole package;
- a package inclusion or exclusion with no owning service;
- a flight block or visa fact that belongs outside normal day services; or
- conflicting dates or ambiguous service classification.

Putting these facts into an arbitrary day would assert chronology the supplier
did not provide. Repeating them across days would change their scope. Keeping
them only in notes would lose semantic structure. Omitting them would lose
source-supported information. A review issue can signal the problem, but cannot
preserve the fact itself.

## 3. Architectural position

The target pipeline is:

```text
Trusted Supplier Source Package
        -> one semantic extraction call
        -> backend validation and trusted normalization
        -> immutable Supplier Extraction Snapshot
        -> consultant resolution and mapping
        -> deterministic backend finalization
        -> canonical Kayra Itinerary Draft and other supported domains
```

The recommended staging model is **Supplier Extraction Snapshot**. The
user-facing workflow may be called **Supplier Import**, but the persisted
machine result is not an itinerary draft and must not be named `staging_draft`.

The architecture has these firm decisions:

1. One extraction job makes exactly one model generation call.
2. The generation response can contain assigned days, unassigned services,
   package facts, ancillary flight/visa facts and review issues together.
3. The backend treats the response as untrusted, validates it, assigns IDs and
   resolves provenance from the trusted package.
4. The normalized machine snapshot is immutable.
5. Consultant decisions live in a separate mutable resolution workspace with
   an audit trail.
6. Finalization is deterministic application logic. It makes no model call.
7. No staging fact disappears during finalization without a recorded
   disposition.
8. Existing canonical drafts remain the reviewed itinerary representation; the
   staging model does not replace them.

## 4. Terminology

| Term | Meaning |
|---|---|
| Supplier Source Package | Trusted same-supplier evidence for one Trip, with ordered private source items. Today those items are files. |
| Provider DTO | Sparse, untrusted JSON returned by the single extraction call. It contains no trusted IDs. |
| Supplier Extraction Snapshot | Immutable backend-normalized statement of the itinerary-relevant facts extracted from one package by one job. |
| Staged day | Explicit source chronology such as a day heading, day number or date. |
| Staged service | A source-supported hotel, transfer, activity, sightseeing, meal, free-time or other service, whether assigned or unassigned. |
| Package fact | A source fact whose stated scope is the package or a group of services rather than one day. |
| Ancillary fact | A flight or visa fact retained for a separate current/future domain rather than normal itinerary-day persistence. |
| Review issue | Structured uncertainty that requires or recommends consultant attention. |
| Resolution | Consultant-authored mapping, correction, routing or exclusion decisions against one immutable extraction snapshot. |
| Disposition | The recorded outcome for a staged fact: mapped, routed, intentionally excluded or unresolved. |
| Canonical draft | The reviewed `KayraItineraryDraft` used by the itinerary product. It contains no unresolved staging-only structures. |

## 5. Proposed staging entity structure

### 5.1 Logical aggregate

A `SupplierExtractionSnapshot` logically contains:

```text
SupplierExtractionSnapshot
  trusted identity and audit metadata
  suggested title
  staged days
  staged services
  package facts
    accommodations
    inclusions
    exclusions
    operating conditions
  ancillary facts
    flights
    visa
  review issues
  commercial-content indicator
  backend-derived counts
```

The logical aggregate is independent of its eventual Firestore layout. The
conceptual hierarchy in section 17 stores days and facts as subcollection
documents to avoid one large Firestore document and to support per-item
resolution.

### 5.2 Trusted snapshot metadata

The backend supplies and validates:

- `extractionId`
- `schemaVersion`
- `tripId`
- `sourcePackageId`
- `jobId`
- `requestedByUid`
- `createdAt`
- backend-generated item IDs and ordering
- trusted package/file provenance
- optional provider/prompt version for operational traceability

The provider cannot set or override any of these values.

### 5.3 Suggested title

The staged title is a proposed fact, not a trusted identity. It contains:

- concise text;
- basis: explicit supplier title or neutral title from supported facts; and
- one or more source locators supporting the title or its component facts.

A consultant may accept or edit it. The resolution records whether the final
title was source-preserved or consultant-authored.

### 5.4 Staged service

Assigned and unassigned services use the same `StagedService` concept. Day
assignment is scope, not a different service type.

A staged service contains:

- backend ID and source order;
- scope: one staged day or `unassigned`;
- optional proposed canonical type: hotel, transfer, activity, sightseeing,
  meal, free time or other;
- concise title or other identifying structured details;
- optional description, start/end time, location and city;
- service-specific inclusions, exclusions and conditions;
- optional hotel, transfer or activity details; and
- trusted provenance.

The staging DTO is related to, but distinct from, the canonical service model.
It reuses the successful V2.4 names and semantics where they are safe, while
allowing incomplete source-supported details:

- classification may be absent when genuinely ambiguous;
- transfer pickup and drop-off may be independently absent rather than forcing
  a fabricated endpoint;
- a hotel fact may carry a night count or name without invented dates;
- typed details are present only when supported; and
- final canonical validation is applied only after consultant resolution.

At least one identifying fact must exist. A completely empty service object is
invalid. Missing optional information alone does not require a review issue;
ambiguity that affects safe mapping does.

### 5.5 Staged statements and conditions

Package and service inclusions/exclusions are structured statements rather than
plain strings. A staged statement contains:

- kind: inclusion or exclusion;
- controlled category such as accommodation, meal, guide, water, entrance,
  transport, visa or other;
- concise semantic text;
- optional supported quantity and frequency;
- stated applicability, such as package-wide or named service categories; and
- trusted provenance.

An operating condition contains a controlled kind such as operating basis,
vehicle, class, ticket scope, availability, payment basis or other, plus its
supported value and provenance. It is separate from review uncertainty: “SIC
basis” and “subject to availability” are supplier facts, while “basis unclear”
is a review issue.

### 5.6 Fact union for persistence

The logical lists normalize into one immutable `facts` collection with a
discriminator:

- `service`
- `package_accommodation`
- `package_inclusion`
- `package_exclusion`
- `package_condition`
- `flight`
- `visa`
- `commercial_presence`

Each fact also has a scope:

- `day`, with a trusted staged-day ID;
- `unassigned`;
- `package`; or
- `ancillary`.

The union keeps persistence and resolution mechanics small while retaining
typed payload validation for each fact kind. Arbitrary unvalidated maps are not
allowed.

## 6. Day-assigned services

A staged day represents chronology explicitly present in the source. It may
contain:

- source-provided day number or label;
- explicit date;
- heading;
- unique day summary or notes;
- trusted provenance; and
- ordered assigned services.

The provider supplies the semantic fields and array order. The backend assigns
the staged-day ID and stable order. A source day number is a fact and must not be
replaced by the array index; this preserves gaps, repeated sections and unusual
labels for review. Canonical day numbers are assigned only during finalization.

V2.4 date, title, hotel-date, service-boundary, time-association, qualifier and
no-invention rules remain unchanged. A detailed day-by-day source should produce
the same semantic days and services it produces today, now stored first in the
snapshot. The resolution workspace can pre-propose a one-to-one mapping so the
consultant is not burdened by empty staging sections.

Day provenance belongs on the day itself. Service provenance remains on each
service because one day may combine facts from different pages or files.

## 7. Unassigned services

A genuine service with no source-supported day is stored as a `StagedService`
with `unassigned` scope. It retains the same structured service fields and
provenance as an assigned service.

For example, four tours listed without chronology remain four separate
unassigned services in source order. They are not distributed across four days,
combined into one note, or dropped. If the service type itself is unclear, the
proposed type remains absent and a review issue points to that service.

The consultant can later:

- assign the service to an existing explicit day;
- create a consultant-authored day and assign it there;
- merge it with another fact only when they represent the same service;
- route it to another supported domain; or
- intentionally exclude it with a reason.

The resolution stores the decision. It does not modify the extraction snapshot.

## 8. Global and package-level facts

Package facts preserve the supplier's stated scope once. They are not copied to
every day or service.

### 8.1 Package accommodations

Store globally declared accommodation separately from day services when the
source does not map it safely. The fact may contain hotel name, “or similar,”
city, explicit dates, night count, room type, meal plan, room count and supplier
rating. Every field remains optional except that the fact must contain at least
one supported accommodation attribute.

### 8.2 Package inclusions and exclusions

Store each semantically distinct inclusion or exclusion once with category,
quantity/frequency where explicit, scope and provenance. “Five lunches and
three dinners” is best represented as two meal inclusion statements because the
quantities differ. Do not turn either statement into five or three day services.

### 8.3 Package operating conditions

Use package conditions for facts such as all tours/transfers using a coach, all
tours operating privately, an English-speaking guide for the package, or a rail
class that applies to a stated group of journeys. `appliesTo` may identify
supported service categories, but must not name individual staging IDs supplied
by the provider.

During resolution, the consultant may confirm that a condition remains global,
map it to specific services, or narrow its applicability. The machine snapshot
always retains the original global scope.

## 9. Accommodation representation

Accommodation uses these rules:

| Source case | Staging representation | Resolution/finalization |
|---|---|---|
| Hotel explicitly assigned to a day | Day-scoped hotel service. | Map to a canonical hotel service on that day. |
| Explicit check-in/check-out span | Hotel service or package accommodation carrying the explicit span; day scope only if the source supplies it. | Consultant confirms the canonical anchor day; preserve the span without creating nightly duplicates. |
| Hotel explicitly stated for the whole package | Package accommodation with package scope. | Map once to reviewed package content or to one canonical hotel service with a supported/consultant-confirmed span. |
| Global hotel with unclear nights | Package accommodation plus a hotel-span review issue. | Must be resolved before it can become a dated hotel service. |
| Multiple hotels without day mapping | Separate package accommodations in source order. | Consultant maps each hotel independently; the system does not infer sequence or nights. |
| “Hotel X or similar” | Preserve the hotel name and explicit `orSimilar` qualifier. | The qualifier survives in the reviewed destination without being duplicated. |

Dates must originate from an explicit hotel date/span or a consultant decision.
A dated itinerary heading, trip start date, night count or later transfer does
not independently establish check-in/check-out dates.

Consultant-entered dates are marked as consultant-authored in the resolution so
they are not presented as extracted supplier facts. The immutable snapshot keeps
the original fields null.

## 10. Package inclusions, exclusions and conditions

The staging model distinguishes five concepts:

1. **Package inclusion/exclusion:** applies to the package and is stored once.
2. **Service inclusion/exclusion:** belongs to one staged service and is stored
   on that service as a provenance-bearing statement.
3. **Operational condition:** a supported qualifier such as ticket only,
   Standard Class, SIC/private/shared basis, direct payment or subject to
   availability.
4. **Commercial information:** an amount or commercial term excluded from this
   semantic payload under section 12.
5. **Review uncertainty:** an ambiguity about classification, applicability or
   mapping, stored as a review issue rather than a factual condition.

A condition should use a specific typed service field when one exists. For
example, explicit private/shared basis can populate transfer type, and a vehicle
can populate vehicle type. Otherwise it remains one condition at its stated
scope. The same qualifier must not be repeated in title, description, condition
and notes.

The current canonical draft has no root package-content collection. Until a
reviewed package-content destination exists, an important package inclusion,
exclusion or condition cannot be silently dropped during finalization. It must
be mapped to a supported service, routed to a supported downstream package
content domain, or remain a finalization blocker.

## 11. Flight and visa boundary

### 11.1 Flights

Flights remain outside normal itinerary day services. The staging snapshot
retains source-supported flight facts so they are not lost. A minimal flight
fact supports:

- airline;
- flight number;
- origin and destination/sector;
- departure date/time;
- arrival date/time;
- cabin or booking class where explicit;
- ordered segment relationship where explicit; and
- trusted provenance.

All fields are optional except that at least one identifying flight/sector fact
must be present. This is evidence staging, not a full flight module. Fare,
ticketing deadlines, PNR and commercial amounts are not introduced here unless
a future flight-domain design explicitly owns them.

Resolution routes a flight fact to the future/manual flight workflow or records
an explicit “handled separately” disposition. It never becomes an `other` day
service merely to satisfy the itinerary draft.

### 11.2 Visa

A visa fact supports:

- disposition: included, excluded, requirement/mentioned or unclear;
- concise non-commercial requirement/operational text; and
- trusted provenance.

Visa cost is excluded. Resolution routes the fact to the visa workflow/content
domain or records that it is handled separately. A source-supported visa
inclusion/exclusion must not disappear merely because the itinerary draft lacks
a visa service type.

## 12. Commercial-data boundary

The safest minimal choice is **presence-only commercial isolation**. The
itinerary extraction call must not return supplier amounts, currencies,
supplements, totals, margins, payment schedules or raw commercial text in the
staging snapshot.

The provider may return only a controlled `commercialContent` indicator:

- whether commercial content was observed;
- controlled categories such as package price, per-person price, supplement or
  payment term; and
- safe provenance locators.

The backend resolves the locators and stores a `commercial_presence` fact. It
stores no values. The original private Supplier Source remains authoritative for
future dedicated commercial extraction or manual pricing work.

This boundary prevents the staging model from becoming a pricing engine while
allowing the consultant to see that pricing information exists elsewhere. A
future commercial-extraction domain may use its own security, schema and
workflow. It must not overload this itinerary staging payload.

## 13. Provenance

Every persisted fact has trusted provenance. This includes:

- staged titles and days;
- assigned and unassigned services;
- package accommodations;
- each inclusion, exclusion and condition;
- flight and visa facts;
- commercial-presence indicators; and
- review issues when a source location supports the ambiguity.

The provider may supply only:

- a 1-based file index into the ordered trusted package; and
- a concise page or section label.

The backend:

- obtains `tripId` and `sourcePackageId` from the claimed job;
- validates the file index against trusted package order;
- maps it to the trusted `sourceFileId`;
- generates extraction, day, fact and issue IDs;
- assigns timestamps and requesting user; and
- rejects provider-supplied trusted IDs, paths or URLs.

A normalized source reference contains package ID, optional file ID and optional
label. It never stores Storage paths, public/signed URLs, file bytes, credentials
or arbitrary source excerpts.

For future non-file source items, the ingestion layer must first create an
ordered trusted package item. The staging model can then resolve a provider
index to that item using the same principle. This does not authorize changing
the current file-backed source persistence in this task.

Finalization retains lineage outside the canonical field when its current
`sourceReference` shape cannot express every contributing statement. Resolution
decisions record which staging fact IDs produced each final draft path. The
immutable snapshot therefore remains the detailed provenance record.

## 14. Review issues

Review issues are first-class staging entities. Each contains:

- backend-generated ID;
- controlled code, such as chronology unknown, accommodation span unknown,
  classification ambiguous, conflicting dates, global mapping required, source
  conflict or other;
- warning or blocker severity;
- concise consultant-facing message;
- a backend-resolved target day/fact/path where possible;
- optional trusted provenance; and
- whether explicit consultant resolution is required.

The provider may reference its own response arrays using validated structural
paths. The backend converts those paths to trusted staged IDs. The provider may
not invent Firestore IDs.

Missing optional detail is not automatically an issue. A source that simply
does not state an activity duration can remain complete. An issue is appropriate
when the missing or conflicting information affects safe classification,
chronology, scope, mapping or downstream use.

Supplier conditions are not review issues merely because they require client
attention. “Subject to availability” is a fact. “It is unclear which ticket is
subject to availability” is an uncertainty.

## 15. Consultant resolution workflow

The simplest consultant workflow is one review workspace with four content
groups:

1. **Timeline:** source-assigned days and services in order.
2. **Unassigned:** services that need day mapping or an explicit disposition.
3. **Package facts:** accommodations, inclusions, exclusions and conditions
   stated globally.
4. **Flights and visa:** facts routed outside normal itinerary days.

A compact Needs Review summary shows blockers first and warnings second. Fully
structured sources emphasize the Timeline and keep empty groups out of the way.
Sparse sources emphasize Unassigned and Package facts. The interface should use
Kayra Deep Navy `#061742`, crisp white surfaces, restrained borders and clear
status labels, without turning every fact into a heavy nested card.

Consultant actions are deliberately small:

- accept a proposed mapping;
- assign an unassigned service to an existing or consultant-created day;
- resolve a service type or relationship;
- map a package accommodation or condition;
- edit a value, recording it as consultant-authored;
- route a flight/visa fact to its separate workflow;
- merge proven duplicates while retaining both source references; or
- intentionally exclude a fact with a controlled reason and optional note.

The workspace shows the unresolved fact count and why finalization is blocked.
It does not require the consultant to review empty optional fields or confirm
every correct scalar value individually.

Finalization produces or updates the canonical draft only after the backend
validates the complete resolution. The UI cannot directly assemble trusted
finalization payloads.

## 16. Lifecycle and immutability decision

Use an **immutable extraction snapshot plus separate mutable resolution state**.

### 16.1 Extraction snapshot

- Created only by the backend from one completed provider response.
- Never edited by clients or consultants.
- A rerun creates a new job and a new snapshot.
- Old snapshots remain available for comparison and audit.
- Provider output is never silently overwritten by consultant changes.

### 16.2 Resolution workspace

- References exactly one base extraction snapshot.
- Stores consultant mappings, corrections, routing and exclusions.
- Uses optimistic revision/version checks to avoid lost updates.
- Emits append-only audit events for material decisions.
- Can be marked superseded when a consultant starts from a newer extraction.
- Becomes sealed when finalization succeeds; later work creates a new resolution
  revision or normal canonical draft history rather than rewriting the sealed
  outcome.

### 16.3 Reruns and revisions

A rerun never mutates the earlier snapshot or resolution. The UI may compare
new and previous facts by semantic content and provenance, but automatic carry
forward is limited to decisions that still match unambiguously. Ambiguous
carry-forward becomes a review issue.

This pattern preserves audit history, supports comparison and keeps consultant
edits distinct from machine claims. It also lets reusable itineraries retain
canonical provenance without exposing private Supplier Sources to other Agents.

## 17. Conceptual Firestore hierarchy

Recommended terminology and paths:

```text
trips/{tripId}/supplier_extractions/{extractionId}
trips/{tripId}/supplier_extractions/{extractionId}/days/{dayId}
trips/{tripId}/supplier_extractions/{extractionId}/facts/{factId}
trips/{tripId}/supplier_extractions/{extractionId}/review_issues/{issueId}
trips/{tripId}/supplier_extractions/{extractionId}/resolutions/{resolutionId}
trips/{tripId}/supplier_extractions/{extractionId}/resolutions/{resolutionId}/decisions/{decisionId}
trips/{tripId}/supplier_extractions/{extractionId}/resolutions/{resolutionId}/events/{eventId}
```

`supplier_extractions` clearly denotes a machine-derived source interpretation
and cannot be confused with existing `itinerary_drafts`. The root extraction
document holds trusted metadata, schema version, title proposal and backend
counts. Immutable day, fact and issue documents avoid the Firestore document
size pressure of one large embedded snapshot. Fact documents use the controlled
discriminated union from section 5.6.

The extraction job remains at its existing path and should eventually record a
server-created `resultingExtractionId` for the staging-capable flow. Existing
legacy jobs with `resultingDraftId` remain valid historical records.

Snapshot persistence uses an internal root `persistenceState` of `writing` or
`complete`. The backend creates the root as `writing`, creates immutable child
documents in bounded batches, and promotes the root to `complete` only after
all required children succeed. Trusted readers and client rules expose only
`complete` snapshots. Each child document ID equals its backend-owned entity ID
and stores a one-based `snapshotOrder` beside the entity value so reconstruction
is deterministic without imposing a single-batch entity limit.

The resolution header stores base extraction ID, status, revision, responsible
consultant, timestamps and final draft ID after completion. Decisions point to
trusted fact/issue IDs and final canonical field paths. Events are append-only.

This is a conceptual hierarchy. No collection, index or rule is created by this
document.

## 18. Security boundary

Preserve the existing access invariants:

- authenticated `@kholidaymaps.com` user;
- active user profile;
- current Trip owner or Admin;
- existing uploaded, same-Trip Supplier Source Package;
- private source objects with no public or signed URLs; and
- trusted package/file provenance.

Machine extraction documents, days, facts and machine review issues are
server-created and immutable to clients. The provider cannot write Firestore.
Only the trusted processor may create a complete snapshot and link it to the
claimed job.

Consultant resolution documents may eventually allow owner/Admin client writes,
but rules must restrict those writes to resolution fields and valid state
transitions. Clients cannot change the base extraction, source references,
machine facts, IDs, creator metadata or audit timestamps. Append-only audit
events and finalization should be written by trusted backend code.

Finalization is a callable or internal backend transaction that reloads the
authoritative snapshot and resolution, verifies Trip access and revision, then
creates/updates the canonical draft and seals the resolution atomically. UI
visibility is never the authorization boundary.

## 19. Finalization invariants

The strong invariant is:

> A Supplier Extraction Snapshot cannot be finalized while an
> itinerary-relevant fact lacks a recorded, valid disposition that would cause
> it to be silently discarded.

Every fact must end in exactly one state:

- mapped to one or more supported canonical fields;
- routed to a named supported domain/workflow;
- intentionally excluded with an auditable reason; or
- unresolved.

### 19.1 Block finalization

Block when any of the following remains:

- an unassigned itinerary service has no disposition;
- a global hotel/accommodation fact has not been safely mapped or routed;
- an important package inclusion, exclusion or condition has no supported
  destination;
- a blocker review issue is unresolved;
- conflicting dates or service relationships remain unresolved;
- a service still lacks classification required by canonical validation;
- a flight/visa fact has neither a supported route nor an explicit handled-
  separately disposition; or
- a consultant edit would produce an invalid canonical draft.

Trusted provenance failure is not a review item; it invalidates the extraction
and must fail before a snapshot is created.

### 19.2 Warn but allow

Warnings may remain when they concern:

- optional details absent from the source;
- non-critical source wording ambiguity that does not alter mapping;
- a missing page/section label while package/file provenance is trusted;
- an informational supplier condition already preserved; or
- a consultant-acknowledged uncertainty that does not cause fact loss.

The backend records outstanding warnings on the resulting draft where its
review model supports them.

### 19.3 Intentional exclusion

Explicit exclusion is allowed for duplicates, supplier marketing prose,
out-of-scope information or facts intentionally handled elsewhere. Excluding an
itinerary-relevant fact requires a controlled reason and consultant identity.
“The current model has nowhere to store it” is not sufficient for an important
package fact; that condition remains a blocker until a supported destination is
available.

Before writing, the finalizer deterministically walks every staged fact and
review issue, verifies dispositions, builds the canonical payload, validates it
with the existing domain validator and records fact-to-field lineage. No AI call
occurs during finalization.

## 20. Migration from current V2.4

The future provider contract should be a new version, conceptually
`kayra_itinerary_extraction_v3_staging`. It should be structurally additive but
versioned separately because its output destination and job completion semantics
change materially.

The V3 provider DTO should keep V2.4's successful sparse fields and rules for:

- day date/title/summary;
- service types and common fields;
- hotel, transfer and activity details;
- service boundaries and qualifier ownership;
- one-generation-call behavior;
- file index and page/section source hints;
- no invented dates, times, hotel spans or transfer basis; and
- review severity.

It adds:

- provenance-bearing day source locators;
- `unassignedServices`;
- package accommodations, inclusions, exclusions and conditions;
- minimal flight and visa facts;
- presence-only commercial categories; and
- staging-aware review targets.

Do not add these fields silently to V2.4 while continuing to call the current
draft writer: its strict boundary would reject them or a partial implementation
could discard them. Introduce a dedicated staging normalizer that assigns IDs,
resolves provenance and persists the immutable snapshot. The processor's
successful transaction then creates the snapshot and records
`resultingExtractionId`, rather than immediately creating an itinerary draft.

Migration should proceed in phases:

1. Define and test the V3 DTO and backend normalizer against synthetic fixtures.
2. Add staging persistence, security rules and immutable snapshot tests.
3. Add consultant resolution and deterministic finalization tests.
4. Verify detailed chronological fixtures produce semantic output equivalent
   to the accepted V2.4 path.
5. Enable the V3 path only when the review/finalization workflow can preserve
   every new fact category.
6. Keep existing V2.4 jobs and drafts unchanged as legacy records.

Production jobs still make one generation call. There is no V2.4-plus-V3 shadow
call. Comparisons use stored/synthetic fixtures or separate deliberate test
runs, not two provider calls inside one job.

For detailed day-by-day sources, all services can arrive day-assigned and the
resolution can be pre-populated as a one-to-one proposal. The consultant sees
the same useful structured result with staging provenance and no regression in
day semantics.

## 21. Supplier-format validation examples

Use synthetic, privacy-safe fixtures. Each must verify source coverage,
invention, structure, uncertainty, provenance, commercial isolation and
finalization behavior.

| Archetype | Expected staging behavior |
|---|---|
| Detailed day-by-day PDF | All explicit days/dates/services remain assigned; V2.4 semantics and page provenance survive. |
| Narrative PDF | Explicit days remain assigned; global hotel/package statements stay global; narrative boilerplate is excluded. |
| Table-heavy email | Day/date rows become staged days; separate hotel and inclusion tables retain their actual scope; prices become presence indicators only. |
| Plain-text package without chronology | Tours remain separate unassigned services; package hotel, meals and conditions remain global; chronology review blockers are created. |
| Screenshot/image source | Same semantic model as text/PDF, with page/section labels only when determinable. |
| Global hotel facts | Hotel name, “or similar,” duration and meal facts remain one package accommodation without invented dates. |
| Incomplete chronology | No arbitrary day distribution; every unassigned itinerary service requires resolution before finalization. |
| Pricing mixed with itinerary content | Operational inclusions/exclusions survive; amounts and commercial wording do not enter staging facts. |
| Multi-file same-supplier package | Provider file indexes resolve through trusted file order; each fact maps to the correct file. |
| Poor scanned document | Supported facts survive, unclear relationships become issues, and illegible content is not guessed. |

Additional cross-cutting tests must cover multiple unmapped hotels, conflicting
dates, service-specific versus package-wide qualifiers, explicit flight/visa
routing, merging true duplicates without provenance loss and rejection of
provider-supplied IDs or invalid source indexes.

## 22. Explicit non-goals

This architecture does not:

- implement any Dart or Functions model;
- change current Firestore paths or rules;
- change Supplier Source upload persistence;
- add pasted-text, email or WhatsApp ingestion;
- add a second model call;
- implement a full flight, visa, quotation or pricing domain;
- store supplier prices or commercial values in itinerary staging;
- make confidence scores part of the domain;
- persist raw model prompts, responses or arbitrary source excerpts;
- create public or signed Supplier Source URLs;
- replace `KayraItineraryDraft` as the reviewed canonical itinerary;
- define visual mockups; or
- deploy or migrate existing data.

## 23. Genuine open questions

Two decisions remain outside the current product contracts and must be resolved
before full sparse-source finalization is implemented:

1. **Reviewed package-content destination:** package-wide accommodations,
   inclusions, exclusions and conditions need a supported final home. The
   recommended shape mirrors the staging package-fact groups and should become
   reviewed canonical package content associated with the itinerary. Whether it
   is added to a future version of `KayraItineraryDraft` or stored as an adjacent
   canonical itinerary-content entity requires a persistence/versioning decision.
   Until then, important unmapped package facts block finalization.
2. **Trusted pasted-text source item:** current Supplier Source persistence is
   file-backed. A future ingestion design must decide whether pasted text is
   stored as a private text object plus file-style metadata or as another
   immutable package-item type. Either choice must preserve ordered trusted
   provenance and feed the same extraction snapshot model.

These questions do not change the staging entity, one-call provider boundary,
immutable snapshot lifecycle or consultant resolution design.
