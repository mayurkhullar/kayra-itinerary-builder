# Supplier extraction staging model

**Review UI implementation status:** Supplier Import review now exposes one
persistent, one-click `Finalize itinerary` action through the existing controller.
The flow is exception-driven: server blockers are shown only after an explicit
attempt, optional warnings require no acknowledgement, and there is no separate
readiness call. Ambiguous retries reuse the pending command; validated finalized
content is read-only. Missing package/ancillary exception resolution controls and
canonical editor/navigation remain separate future work. Production extraction
requests remain V2.4; this UI change does not deploy or change routing.

**Architecture decision, 2026-10-06:** section 25 resolves the canonical package
destination and future exception-driven finalization policy. It supersedes the
earlier destination-neutral discussion. The canonical v2 pure TypeScript domain
and shared deterministic assembly/assessment policy are now implemented. Safe
untouched package facts and `retain_package_level` no longer trigger the old
pure-assessment destination gate. Internal Admin atomic finalization persistence
and its authenticated callable are implemented. The callable is not deployed;
strict read-only Flutter V2 parsing and repository support are implemented.
Finalize UI and rollout remain pending.
Ordinary production extraction remains on V2.4.

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
7. No staging fact disappears during finalization without a recorded effective
   outcome. A safe default outcome is recorded by the backend at finalization;
   it does not require a consultant acceptance document for each fact.
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
| Disposition | Effective outcome for a staged fact: default-included, explicitly retained/corrected/mapped, routed, intentionally excluded or unresolved. Backend-derived defaults are distinct from consultant decisions. |
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
| Explicit check-in/check-out span | Hotel service or package accommodation carrying the explicit span; day scope only if the source supplies it. | Keep the existing scope and explicit span by default. Package accommodation needs no anchor day; mapping to a day is exceptional. |
| Hotel explicitly stated for the whole package | Package accommodation with package scope. | Map once to reviewed package content or to one canonical hotel service with a supported/consultant-confirmed span. |
| Global hotel with absent nights | Package accommodation with missing fields left null. A genuine ambiguous/conflicting span also has a review issue. | Preserve undated package accommodation without inventing nights. A flagged ambiguity remains an exception; absence alone does not require a dated service. |
| Multiple hotels without day mapping | Separate package accommodations in source order. | Keep distinct package entries when that meaning is unambiguous. Unknown alternatives-versus-multiple-stays relationships require action, not inferred sequence or nights. |
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

The implemented canonical v1 draft has no root package-content collection, so
its assessment still blocks unsupported package content. The chosen future
destination is `itinerary_draft_v2.packageContent`, defined in section 25 and
[`ITINERARY_DRAFT_MODEL.md`](ITINERARY_DRAFT_MODEL.md). Safe package facts will
stay there by default; mapping is not required merely to preserve them.

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

- inspect the automatically assembled proposal without writing acceptance;
- assign an unassigned service to an existing or consultant-created day;
- resolve a service type or relationship;
- deliberately narrow a package accommodation or condition to a supported
  day/service destination when needed;
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
- Remains attached to its own snapshot when a newer extraction is created.
- Becomes sealed when finalization succeeds; later work creates a new resolution
  revision or normal canonical draft history rather than rewriting the sealed
  outcome.

### 16.3 Reruns and revisions

A rerun never mutates the earlier snapshot or resolution. The UI may compare
new and previous facts by semantic content and provenance, but no decision is
carried forward automatically. A future assisted migration must be an explicit,
audited workflow and is outside this contract.

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

Consultant resolution mutations use trusted callable backend commands. Future
Rules may permit owner/Admin reads, but direct client creates, updates and
deletes remain denied. Clients cannot change the base extraction, source
references, machine facts, IDs, creator metadata or audit timestamps.
Append-only audit events and finalization are written only by trusted backend
code.

Finalization is a callable or internal backend transaction that reloads the
authoritative snapshot and resolution, verifies Trip access and revision, then
creates/updates the canonical draft and seals the resolution atomically. UI
visibility is never the authorization boundary.

## 19. Finalization invariants

The strong invariant is:

> A Supplier Extraction Snapshot cannot be finalized while an
> itinerary-relevant fact lacks a valid, recorded effective outcome. Safe
> default inclusion counts as an outcome; unexplained omission does not.

Every fact must end in exactly one state:

- included at its supported source scope by the versioned default policy;
- mapped to one or more supported canonical fields;
- routed to a named supported domain/workflow;
- intentionally excluded with an auditable reason; or
- unresolved.

### 19.1 Block finalization

Block when any of the following remains:

- an unassigned itinerary service has no disposition;
- a global hotel/accommodation fact has neither a safe canonical package
  representation nor a valid explicit mapping/exclusion;
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
with the validator for the selected canonical version and records fact-to-field
lineage. No AI call occurs during finalization. Section 25 defines the future
v2 default policy; this does not loosen the deployed v1 validator.

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
preview uses deterministic one-to-one defaults without pre-writing acceptance
decisions. The consultant sees the same useful structured result with staging
provenance and no regression in
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

## 23. Boundaries outside this decision

The canonical package destination, lineage layout, size limits and finalization
atomicity are decided in section 25. They are no longer open alternatives.
Trusted pasted-text ingestion and concrete flight/visa workflow identities
remain separate architecture tasks. Neither is needed to retain safe file-backed
package accommodation, inclusions, exclusions or operating conditions.

## 24. Supplier Import Resolution contract

This section fixes the durable contract between one complete immutable Supplier
Extraction Snapshot and later canonical finalization. Where earlier sections
describe optional approaches, this section is authoritative for resolution
identity, lifecycle, concurrency, writes and rerun isolation. It defines an
architecture; documentation alone does not implement it. Resolution domain,
trusted mutations and selected Flutter review slices now exist. Section 25 is
authoritative for the future canonical-v2 destination and assessment policy.

### 24.1 Aggregate identity and Firestore hierarchy

There is exactly one resolution aggregate for one extraction. Its logical
`resolutionId` is the immutable `extractionId`, and its document ID is the same
value. The path is therefore deterministic:

```text
trips/{tripId}/supplier_extractions/{extractionId}
  resolutions/{extractionId}
    decisions/{decisionId}
    manual_items/{manualItemId}
    events/{eventId}
```

The repeated ID is intentional. It prevents a second current resolution from
being allocated beneath the same snapshot and makes a cross-snapshot reference
detectable without a query. `decisions` stores sparse typed decisions against
Snapshot entities. `manual_items` stores the small amount of genuinely
consultant-authored day or service content that has no Snapshot entity.
`events` is the append-only audit log.

Decision IDs are deterministic within the aggregate:

- `title` for the title decision;
- the exact `staged-day-N`, `staged-service-N`, `package-fact-N`,
  `ancillary-flight-N`, `ancillary-visa-N` or `review-N` target ID for an
  entity decision.

Snapshot IDs are unique across their entity prefixes. A decision document must
also store its controlled `decisionKind` and target ID, and the backend verifies
that both agree with the document ID and the authoritative Snapshot entity.
Manual IDs use separate server-owned prefixes such as `consultant-day-...` and
`consultant-service-...`; they can never be interpreted as machine IDs.

The resolution is never moved, shared or reused across Trips or extractions. A
new extraction job and Snapshot create a new independent resolution path even
when the source package is unchanged.

### 24.2 Resolution root

The compact root has an exact, versioned shape:

```text
SupplierImportResolution
  schemaVersion: supplier_import_resolution_v1
  resolutionId: extractionId
  tripId
  extractionId
  sourcePackageId
  snapshotSchemaVersion: supplier_extraction_snapshot_v1
  status: active | finalized
  revision: positive integer
  createdByUid
  createdAt: server timestamp
  updatedByUid
  updatedAt: server timestamp
  finalizedByUid: UID | null
  finalizedAt: server timestamp | null
  resultingDraftId: itinerary draft ID | null
```

The linkage, schema, creator and creation timestamp are immutable. Current Trip
ownership is not copied into the root because ownership may be reassigned; each
read and mutation uses the authoritative parent Trip. The root does not embed
the Snapshot, decisions, audit history or a mutable readiness flag.

The first accepted `open_review` command creates the root at revision `1` and
appends the matching `0 -> 1` audit event. A repeated open returns the existing
aggregate. There is no separately stored `not_started` state: absence of the
root means review has not started.

### 24.3 Lifecycle and readiness

Only two lifecycle states are persisted:

- `active`: consultant decisions may be changed through trusted commands;
- `finalized`: canonical output was committed and the resolution is locked.

`ready_to_finalize` is derived, never persisted. It could become stale whenever
a decision changes. `in_review` is equivalent to an existing `active` root and
does not need another value. There is no `superseded` state in this contract;
reruns are isolated by their parent extraction. A product view may label an old
active resolution as belonging to an older extraction without mutating it.

### 24.4 References, decisions and sparse field overrides

References are discriminated rather than bare IDs where both origins are valid:

```text
DayReference =
  { kind: staged_day, dayId }
  | { kind: consultant_day, manualDayId }

ServiceReference =
  { kind: staged_service, serviceId }
  | { kind: consultant_service, manualServiceId }
```

Every decision child has these common server-validated fields:

```text
decisionKind
targetEntityId
disposition
overrides: exact typed override object
lastRevision
updatedByUid
updatedAt
```

The concrete decision kind defines the only permitted disposition and override
fields. Arbitrary field paths and `Map<String, dynamic>` patches are forbidden.
The document contains decisions and references, not a mutable copy of its
Snapshot target.

An optional field override uses a closed union:

```text
FieldOverride<T> =
  { operation: set, value: T }
  | { operation: clear }
```

The four meaningful states are therefore unambiguous:

- no decision document or no override member: untouched source proposal;
- `retain`/`accept` with no override: explicitly accepted unchanged;
- `set`: consultant-authored correction;
- `clear`: consultant intentionally removed an optional source value.

Required canonical fields cannot be cleared. List fields use `set` with a full
typed replacement list or `clear`; list-element patch paths are not accepted.
All override text uses the same normalization and commercial-value rejection as
the Snapshot unless a later dedicated commercial domain owns the field.

### 24.5 Title and staged-day decisions

The title decision has `accept` or `override`. `override` requires one normalized
non-commercial title value. An absent title decision leaves the suggested title
untouched; it does not claim that the consultant accepted it.

A staged-day decision references one `staged-day-N` and has:

```text
disposition: retain | exclude
canonicalOrder: positive integer | absent
overrides:
  date: FieldOverride<YYYY-MM-DD> | absent
  title: FieldOverride<string> | absent
  summary: FieldOverride<string> | absent
  notes: FieldOverride<string> | absent
exclusionReason: ExclusionReason | null
exclusionNote: string | null
```

An absent decision retains the staged day and its source order as an untouched
proposal. A retained day may change canonical order and supported canonical
fields. `sourceDayNumber` is evidence and is never overridden; final canonical
day numbers come from resolved order. Clearing `date`, `summary` or `notes` is
allowed. A retained canonical day must end with a valid title, so title cannot
be cleared without a replacement.

Canonical order is the explicit override when present and otherwise the
Snapshot order. Retained and manual days must resolve to unique positive order
values; gaps are allowed in working state and are renumbered contiguously only
in the final canonical payload. A reorder command may update several day
decisions in one revision. Excluding a day is invalid while a retained service
still targets it.

The controlled `ExclusionReason` values are:

```text
duplicate
extracted_in_error
irrelevant_supplier_content
not_part_of_requested_itinerary
replaced_by_consultant_content
other
```

`other` requires a concise consultant note. Absence of a canonical destination
is never a valid exclusion reason by itself.

### 24.6 Assigned and unassigned service decisions

One `service` decision shape serves both Snapshot scopes:

```text
disposition: retain | exclude
day: DayReference | absent
canonicalOrder: positive integer | absent
overrides: ServiceOverrides
exclusionReason: ExclusionReason | null
exclusionNote: string | null
```

For an assigned service, no decision means retain it on its source day at its
source order. A `retain` decision with no day or field override explicitly
accepts that mapping. Supplying a day moves it to another retained staged or
manual day. Supplying `canonicalOrder` changes its order within that day.

An unassigned service is unresolved until a `retain` decision supplies a valid
day and order, or an `exclude` decision supplies a controlled reason. Opening
the review workspace never infers a day. Moving an assigned service and
assigning an unassigned service preserve the original Snapshot fact and trusted
provenance.

`ServiceOverrides` has only these typed members:

- common fields: `serviceType`, `title`, `description`, `startTime`, `endTime`,
  `location`, `city`, `inclusions`, `exclusions` and `notes`;
- hotel fields: `hotelName`, `city`, `orSimilar`, `checkInDate`,
  `checkOutDate`, `nightCount`, `roomType`, `mealPlan`, `numberOfRooms` and
  `supplierStarRating`;
- transfer fields: `pickup`, `dropoff`, `vehicleType` and `transferType`;
- activity fields: `activityName`, `duration` and `activityType`.

The enum vocabularies remain those of the Snapshot. Overrides must produce one
valid canonical classification and compatible detail branch. Changing a type
does not silently discard incompatible extracted details; those details must be
explicitly cleared, mapped to supported content or remain a blocker. Likewise,
staged service conditions or structured attributes not supported by the chosen
canonical destination cannot silently disappear.

Within one resolved day, effective service orders must be unique. Untouched
assigned services use their Snapshot order; moved, unassigned and manual
services require an explicit order. A cohesive reorder mutation may rewrite all
affected service order decisions atomically, after which finalization assigns
the canonical list order.

### 24.7 Package accommodation decisions

`package_accommodation` decisions support exactly:

```text
disposition:
  map_to_day_service | retain_package_level | exclude
day: DayReference | null
canonicalOrder: positive integer | null
overrides: AccommodationOverrides
exclusionReason: ExclusionReason | null
exclusionNote: string | null
```

`map_to_day_service` requires a retained day and service order, and produces one
hotel service rather than nightly duplicates. `AccommodationOverrides` mirrors
the exact staged hotel fields using sparse `FieldOverride` values. Dates are
never derived from day dates, Trip dates or night count. A consultant-set
check-in or check-out date is explicitly marked by its `set` operation and
captured by the audit event.

`retain_package_level` preserves the accommodation as package-wide reviewed
content. It can permit finalization only when a deployed canonical destination
supports every retained field. With today's `KayraItineraryDraft`, fields such
as package scope, `orSimilar` and an undated `nightCount` have no lossless root
home, so the assessment remains blocked. `exclude` requires an auditable reason.
Under the future v2 policy, `retain_package_level` is a valid explicit,
non-blocking package disposition subject to the same safety and issue gates as
default inclusion. It remains useful for corrections and explicit scope review;
ordinary safe package facts do not require it.

### 24.8 Package statement and condition decisions

Package inclusions and exclusions use a `package_statement` decision;
conditions use `package_condition`. Their dispositions are:

```text
retain_package_level
map_to_service
exclude
```

`map_to_service` requires a valid retained `ServiceReference` and a controlled
destination compatible with the fact:

```text
service_inclusion | service_exclusion | service_notes |
transfer_vehicle_type | transfer_type
```

The finalizer rejects an incompatible pair, such as mapping an exclusion to
`service_inclusion` or a guide condition to `transfer_type`. Sparse typed
overrides may correct category, text, quantity, frequency, applicability,
condition kind or condition value. They do not copy unchanged Snapshot values.

`retain_package_level` keeps the fact at package scope and is ready only when a
supported canonical package-content destination exists. Important package
facts therefore remain blockers against today's draft schema unless safely
mapped or deliberately excluded. They are never forced into an arbitrary day.
Section 25 removes this destination-only blocker for future canonical v2 and
defines safe untouched package retention. It does not alter today's code.

### 24.9 Ancillary flight and visa decisions

Flights remain ancillary. A `flight` decision supports:

```text
route_to_flight_workflow | handled_separately | exclude
```

`route_to_flight_workflow` records the supported destination identity when that
workflow exists. `handled_separately` is an explicit consultant disposition
that allows land-itinerary finalization without pretending the flight became a
service. Typed sparse overrides may correct only the existing non-commercial
flight fields and conditions. Fare, PNR, payment and ticketing values are not
part of this resolution contract.

A `visa` decision supports:

```text
route_to_visa_workflow | handled_separately | exclude
```

Its sparse overrides are limited to the existing controlled visa disposition
and non-commercial text. Visa pricing is forbidden. A route is complete only
when the named workflow exists and accepts the fact; otherwise the assessment
keeps it blocked or the consultant must choose an honest handled-separately or
exclusion decision.

### 24.10 Commercial-presence treatment

`commercial_presence` is informational. It has no decision document, does not
block land-itinerary finalization and is never copied to canonical itinerary
content. The review UI may display its controlled categories and direct the
consultant to the separate pricing workflow, but viewing it creates no
acknowledgement state. Resolution and audit schemas contain no amount, currency,
price, supplement value, markup, margin, discount, payment value or raw pricing
text field.

### 24.11 Review-issue decisions

Absence of a `review_issue` decision means the issue remains open. Viewing an
issue never writes a decision. The controlled outcomes are:

```text
acknowledged | resolved | overridden
```

- `acknowledged` is permitted only for a warning whose
  `resolutionRequired` is false. It records that the consultant saw a
  non-blocking uncertainty; it does not change the Snapshot issue.
- `resolved` requires one or more decision/manual-item references whose current
  state concretely addresses the issue target and code. The server validates
  those references rather than trusting a free-text assertion.
- `overridden` is exceptional. It requires a controlled reason and concise
  note, is auditable, and may not make an invalid canonical result valid.

`chronology_unknown`, `accommodation_span_unknown`,
`classification_ambiguous`, `conflicting_dates`, `global_mapping_required` and
`source_conflict` require a concrete mapping, correction, routing or exclusion;
they cannot be dismissed by acknowledgement. For the initial contract, only an
`other` warning or blocker may use `overridden`, and only when server policy
confirms that no fact would be lost. Expanding that allowlist requires a schema
or policy review. Any issue with `resolutionRequired: true` must be `resolved`
or validly `overridden`, regardless of warning severity.

### 24.12 Consultant-authored days and services

Manual days and services are allowed because a sparse source may require human
structure that has no machine entity. They live in `manual_items` as a strict
union, never inside a Snapshot decision:

```text
ConsultantDay
  itemKind: consultant_day
  manualDayId
  canonicalOrder
  date: YYYY-MM-DD | null
  title
  summary: string | null
  notes: string | null
  createdByUid, createdAt, updatedByUid, updatedAt, lastRevision

ConsultantService
  itemKind: consultant_service
  manualServiceId
  day: DayReference
  canonicalOrder
  complete canonical service fields and compatible typed details
  createdByUid, createdAt, updatedByUid, updatedAt, lastRevision
```

Their IDs are server-owned and their origin is always `consultant`; they contain
no Supplier Source provenance. If content corrects a Snapshot entity, a sparse
override is used instead. Removing a manual day is invalid while a retained
service targets it. Removing a manual item writes an audit event; it does not
delete or alter Snapshot evidence.

### 24.13 Pure finalization assessment

`canFinalize(snapshot, resolution)` is deterministic and has no UI state, clock
dependency or AI call. It returns an ephemeral typed result:

```text
FinalizationAssessment
  resolutionId
  evaluatedRevision
  canFinalize
  blockers: FinalizationFinding[]
  warnings: FinalizationFinding[]

FinalizationFinding
  code: controlled enum
  targetKind
  targetId: ID | null
```

The finding contains stable codes and references, not copied source text. The
UI supplies localized explanation from those codes.

Mandatory blockers include:

- invalid resolution/Snapshot linkage, schema, target or cross-reference;
- any unassigned service without a valid assignment or exclusion;
- any retained service targeting a missing or excluded day;
- duplicate or invalid effective day/service ordering;
- any retained service lacking the type, title or typed fields required by its
  selected canonical destination;
- incompatible or conflicting overrides, including date ranges;
- any package accommodation without a supported mapping, package destination
  or exclusion;
- any important package inclusion, exclusion or condition without a supported
  disposition;
- any flight or visa fact without a supported route, handled-separately choice
  or exclusion;
- any blocker or `resolutionRequired` issue that is still open, merely
  acknowledged or invalidly overridden;
- any unresolved chronology, date conflict, classification or relationship;
- any retained staging field that the selected canonical destination would
  silently discard;
- invalid or incomplete manual content; and
- failure of the existing canonical draft validator after deterministic
  assembly.

Warnings may remain when they concern optional source detail, non-critical
wording ambiguity, a missing source label with trusted file provenance, or
another warning with `resolutionRequired: false`. They do not require a write
unless the consultant chooses to acknowledge them. Acknowledgement is preserved
in audit history but does not erase the original issue. Commercial presence is
informational and is absent from both blocker and acknowledgement requirements.

Untouched valid assigned days and services do not require ceremonial acceptance
documents. They flow through the deterministic default mapping unless a review
issue or unsupported field makes that mapping unsafe. This keeps ordinary
well-structured supplier itineraries practical while preventing silent loss in
sparse sources.

### 24.14 Optimistic concurrency and audit events

Every mutating command carries:

```text
tripId
extractionId
expectedRevision
commandId
typed command payload
```

`commandId` is a validated idempotency identity and becomes the audit event ID.
Reusing it with the same actor and command returns the recorded result; reusing
it with different content is rejected. A stale `expectedRevision` returns a
stable `resolution_conflict` result with the current revision and performs no
write.

An audit event has this exact conceptual envelope:

```text
eventId
resolutionId
extractionId
previousRevision
resultingRevision
actorUid
occurredAt: server timestamp
action: controlled AuditAction
targetKind
targetId: ID | null
metadata: typed metadata for that AuditAction
```

Audit actions cover opening review, setting/reverting title, day, service,
package, ancillary and issue decisions, reordering, adding/updating/removing a
manual item, and finalizing. Metadata records controlled dispositions,
references, reason codes and changed field names. It stores consultant-authored
before/after override values only when needed to audit the correction and after
the same semantic/commercial validation. It never copies unchanged supplier
descriptions, Snapshot provenance arrays, file paths, source text or commercial
values. Events are never updated or deleted.

Each accepted command runs one Firestore transaction that:

1. authenticates an active company user and verifies current Trip owner/Admin
   access;
2. reloads the authoritative complete Snapshot and exact resolution linkage;
3. rejects a finalized resolution;
4. verifies `expectedRevision == resolution.revision`;
5. verifies command idempotency, target existence and semantic validity;
6. writes the affected root, decision and/or manual-item documents;
7. increments the root revision exactly once and updates server-owned audit
   metadata; and
8. creates exactly one append-only event with matching previous/resulting
   revisions.

There is no successful decision mutation without its event, and no event for a
rejected mutation. Child documents carry `lastRevision`; because every child
write and event also updates the root revision atomically, a finalizer that has
loaded revision `R` can reject any concurrent change by rechecking the root at
commit time.

### 24.15 Server command surface and security

All mutation writes use the Admin SDK behind authenticated callable Functions.
Direct Firestore resolution writes are denied, including for Admins. Future
Rules may allow active Trip owners and active Admins to read the root,
decisions, manual items and events; all access remains scoped through the parent
Trip. A former owner loses access after reassignment, and the new owner gains it
through the current Trip relationship. Resolution state is private Trip state
and never a cross-agent reusable source.

Use one callable with a closed command union for ordinary mutations:

```text
applySupplierImportResolutionMutation
  open_review
  set_title_decision
  set_day_decision
  set_day_order
  set_service_decision
  set_service_order
  set_package_fact_decision
  set_ancillary_decision
  set_review_issue_decision
  upsert_manual_day
  remove_manual_day
  upsert_manual_service
  remove_manual_service
  revert_decision
```

This keeps authorization, revision and audit behavior in one implementation
without accepting an arbitrary patch. The discriminator selects a strict input
schema and domain handler.

Use a separate `finalizeSupplierImport` callable. Finalization has a distinct
contract: it loads the whole aggregate, computes the pure assessment, assembles
and validates canonical output, and commits the result. Keeping it separate
prevents an ordinary item mutation from smuggling canonical writes.

### 24.16 Finalization transaction and locked boundary

The future finalizer first reads the immutable Snapshot plus all current
resolution children at revision `R`, computes `canFinalize`, builds the canonical
payload and passes it through the version-specific strict canonical validator.
If the result is ready, one transaction rechecks authorization, complete Snapshot identity,
`active` status and root revision `R`. It then:

- creates a new canonical v2 draft with embedded package content, plus the
  immutable finalization receipt described in section 25; it never overwrites
  an existing draft or quotation;
- sets resolution status to `finalized`;
- increments revision to `R + 1`;
- records `resultingDraftId`, `finalizedByUid` and `finalizedAt`; and
- appends the matching finalization event.

If any check changes, no canonical or resolution write commits. Once finalized,
every normal mutation command returns `resolution_finalized`. Later itinerary
editing belongs to canonical draft/version history. It never reopens the
resolution, rewrites the Snapshot or edits prior events.

### 24.17 Reruns and the selected canonical destination

A rerun creates a new extraction job, new Snapshot and new deterministic
resolution identity. Earlier decisions are neither copied nor applied. A future
comparison or assisted-migration feature must be explicit, revalidate every
target against the new Snapshot and write new audit events; it is out of scope.

Choose the expanded canonical root, `itinerary_draft_v2`. Section 25 and the
draft-model document define package content and its private lineage. No adjacent
canonical package entity is introduced. `retain_package_level` continues to name
semantic intent, not a client-selected collection. The pure V2 assembly and
assessment and internal Admin persistence now implement that destination. A
separate strict read-only Flutter V2 reader and review finalization UI are
implemented. Canonical navigation and finalization callable deployment remain
separate rollout work. No production V3 cutover
follows from internal backend readiness.
Neither this decision nor a rerun changes resolution identity, callable-only
writes, revision checks, append-only audit history or Snapshot immutability.

## 25. Canonical package content and exception-driven finalization

**Implementation status:** the pure canonical V2 domain and exception-driven
assembly policy below are implemented. `assembleSupplierImportV2` and
`assessSupplierImportFinalization` share one evaluator and the authoritative V2
validator. Trusted output context is explicit; assessment's default envelope is
validation-only and its candidate is discarded. Ready results include a validated
immutable candidate and deterministic private accounting; blocked results never
include a draft. Every package fact is automatically retained, explicitly
retained, mapped once, excluded, or blocked. Source-relative package ordering is
compacted after mapping/exclusion; day/service collisions are never repaired.
Package and manual content, sparse corrections, import linkage and count limits
are covered by focused tests. Pure Snapshot structural validation reuses the
stored parser; file authority remains the trusted reader's responsibility.

The pure private `supplier_import_finalization_v1` receipt domain is also
implemented. Its deterministic factory accepts only a successful assembly and
trusted finalization context, validates candidate/linkage/output coverage, and
retains compact existing accounting with review outcomes, mapping selectors and
field operations. SHA-256 binds the authoritative canonical map excluding root
server timestamps; a separate fixed-shape command/actor/revision/policy
fingerprint supports future retry comparison. Strict map conversion, defensive
Dates, deep immutability and the 2,000-source-entity / 2,000-decisions-plus-manual
bounds are tested. Source membership still belongs to the trusted reader and
assembler; the Admin writer applies conservative application payload budgets,
with Firestore enforcing the final platform limits.

Internal Admin persistence now creates the V2 draft and private receipt, seals
the Resolution and creates its finalization event in one transaction. Strict
stored serializers/readers, replay, authorization/revision checks and capacity
tests are implemented (section 25.7). The authenticated callable is implemented
but not deployed; strict read-only Flutter V2 support is implemented, with
review finalization UI implemented; canonical navigation remains future work.
The production V2.4 writer and extraction path remain unchanged.

### 25.1 One canonical destination and explicit versions

Choose **A: a versioned canonical draft root with embedded package content**.
The exact new contract is `itinerary_draft_v2`, stored at the existing
`trips/{tripId}/itinerary_drafts/{draftId}` path. Its `packageContent` contains
four required arrays: `accommodations`, `inclusions`, `exclusions`, `conditions`.
Its timeline retains the existing day/service contract. The full field,
correction, ordering and lineage definitions are in
[`ITINERARY_DRAFT_MODEL.md`](ITINERARY_DRAFT_MODEL.md#canonical-v2-architecture).

Package accommodation remains first-class package content after finalization.
It preserves explicit hotel/location, stay span, nights, room, meal and
or-similar facts without inventing dates or a day placement. Statements preserve
category, text, quantity, frequency and applicability. Conditions preserve kind,
value and applicability. Inclusions and exclusions stay separate from each
other and from all service/day notes. No arbitrary commercial-text field exists.

Reject an adjacent canonical entity for this bounded rollout: every private
read, client projection, PDF and reusable copy would acquire a join, a second
version/authorization surface and a possible stale or missing half. A single
root gives one rendered identity and atomic timeline/package content. Its size
is bounded explicitly in section 25.7; oversize data never silently spills into
a different storage model. The separate receipt is private audit evidence only.

Use these distinct version names:

| Contract | Meaning |
|---|---|
| Effective `itinerary_draft_v1` | Exact existing persisted draft shape, currently without a `schemaVersion` field. Infer only that complete legacy shape; do not rewrite old documents. |
| `itinerary_draft_v2` | Explicit root `schemaVersion`, embedded package content and immutable `importResult` lineage. |
| `supplier_extraction_snapshot_v1` | Existing immutable machine evidence; unchanged. |
| `supplier_import_resolution_v1` | Existing sparse decisions/revision contract; unchanged by this documentation task. |
| `supplier_import_exception_review_v1` | Future server-owned assessment/default-carry policy, recorded in preview and finalization. |
| `supplier_import_finalization_v1` | Future immutable receipt schema defined below. |

New policy is not inferred from a missing package decision in a historical
finalized result. An active compatible Resolution can be assessed under the new
policy only through its explicit policy-labelled preview and finalization
request. The server chooses the enabled policy; the client echoes the preview's
policy/revision as a precondition, not as permission to select an older policy.
Old v1 drafts/quotations and V2.4 jobs remain readable with no migration. Enable
v2 writes only after readers, validators, finalizer and access/projection support
are compatible. Unknown/mixed versions fail closed.

### 25.2 Exception-driven consultant review

The consultant opens a nearly finished, deterministic preview, with a single
summary of remaining blockers and links to the affected facts. Ordinary correct
facts show their extracted values without an Accept button requirement. Every
fact remains inspectable/correctable; explicit exclusion and deliberate mapping
remain available. Source inspection is available on demand, not a mandatory
step for each value. Safe optional warnings do not demand acknowledgements.

If there are no exceptions, one explicit finalization action after preview is
enough. It creates no per-fact acceptance writes. The backend records its
versioned default decisions in the finalization receipt; it must not label them
as individual consultant confirmations. No preview or ordinary autosave
automatically finalizes the import.

One correction/assignment/exclusion may also resolve the directly covered issue
in the same audited command, once a future typed command supports that
composition and the server proves the issue's resolution predicate. Do not add
a second ceremonial confirmation for the same correction. This is not blanket
issue dismissal and is not currently implemented command behavior.

No empty acceptance documents, synthetic dates, inferred day assignments or
hidden reclassification are used to make the preview look complete. Capacity,
unsupported-field and integrity failures remain visible exceptions. Quote
Prepared and publication/pricing checks still apply after import finalization.

### 25.3 Exact default, precedence and safe inclusion gate

**Rule:** an untouched Supplier fact flows to its source-scoped canonical
destination by default if and only if every gate below succeeds. No explicit
`retain` is required for that fact. Failure of any gate is a typed blocker or a
specific supported exclusion/routing decision, never silent omission.

1. The authoritative Snapshot is complete, schema-valid and linked to this
   Trip, trusted source package and Resolution. Fact IDs and source references
   are valid members. Package-only provenance for a valid multi-file source is
   permitted; optional missing labels/file locators do not create fake IDs.
2. The effective fact, after validated sparse corrections, satisfies its exact
   canonical destination, including every retained field and source qualifier.
   No loss through string flattening, field dropping or arbitrary notes occurs.
3. Scope/classification and relationships are unambiguous. A package fact stays
   package-wide; an assigned service retains its valid explicit day. No new
   chronology, span, counts, hotel relationship or multi-target map is inferred.
4. No unresolved blocking/structural issue applies to the fact, its containing
   day/relationship, or the whole Snapshot. Exclusion does not erase an issue
   affecting other retained facts. Issue predicates are evaluated separately.
5. The fact passes non-commercial content validation; no known pricing,
   supplier/client private content, ancillary misclassification or contradictory
   source claims are admitted. A valid schema or high AI confidence alone is
   not proof that prose is correct. Known violations surface as exceptions;
   consultants can inspect/correct unflagged extraction mistakes as well.
6. There is no incompatible or conflicting Resolution decision. All references,
   effective ordering and provenance are valid, and the full output passes the
   version-specific canonical validator and capacity limits.

Absence of an optional value is not itself ambiguity. An undated global hotel
with an explicit room type can be safe package content; contradictory hotel
spans or unclear alternative-versus-multiple-stay relationships are not. The
backend may detect contradictions, but cannot repair them by inference.

Apply decisions in this order:

- Validate aggregate integrity and all current decision references first. Even
  a decision attached to an excluded entity may not contain foreign references.
- Explicit `exclude` wins over default inclusion and produces no canonical
  content for that fact. Keep its evidence/decision/receipt outcome privately.
- A valid explicit mapping selects its supported destination and consumes the
  fact once; it does not also retain a package copy.
- Otherwise a package fact uses the package destination, whether untouched or
  explicitly `retain_package_level`. Ordinary assigned days/services use their
  existing timeline destination.
- Apply sparse fields: **untouched** uses the canonicalized Snapshot value;
  **set** uses the validated consultant override; **clear** deliberately removes
  an optional value (`null` or `[]` in the required canonical shape). Required
  fields cannot be cleared; use supported correction or exclusion instead.
- Validate effective content and review-issue resolution, then create one
  deterministic output and complete fact-outcome ledger. No exact-text deduping
  silently collapses independent source facts.

Canonicalization is structural (validated types, existing normalization and
stable order), not AI rewriting, paraphrasing or content repair. Overrides do
not mutate the Snapshot. A fully cleared accommodation option is not a valid
retained fact. Preserve actor/time and set/clear operations in the decision
history and lineage.

| Fact / state | Future default or required action |
|---|---|
| Valid title, assigned day and assigned service, fully representable | Use extracted values. No mandatory explicit retain. This principle already exists for ordinary days/services in the assessment. |
| Safe global/undated package accommodation | Include as package accommodation, without a fake day, date or booking guarantee. |
| Safe package inclusion, exclusion or condition | Include in the matching package array, with all structured fields/provenance. |
| Unassigned service | Explicit consultant assignment to a valid retained day, or explicit exclusion. Never assign automatically. |
| Ambiguous hotel relationship/span, incompatible mapping, unsupported retained field | Concrete supported correction/disposition, or exclusion; otherwise block. |
| Explicit exclusion | Omit content; audit the exclusion. Reassess dependent services/issues rather than automatically excluding them. |
| Optional non-structural warning | May remain open, or be acknowledged voluntarily. No per-fact confirmation. |
| Flight/visa fact | Explicit supported ancillary handling or exclusion; no default land-content destination. |
| Commercial-presence marker | Informational ledger entry only, never rendered content or a required acknowledgement. |

### 25.4 Issues, mapping and `retain_package_level`

The exact future meaning of **`retain_package_level` is a valid non-blocking
explicit disposition**, provided the same safe-inclusion gate succeeds. It
remains useful with corrections or exceptional scope confirmation. It is
optional for a safe untouched package fact, whose default output is identical.
It does not waive validation, erase issues or imply that every source field has
been personally confirmed.

Mapping into a day/service is exceptional and deliberate. It is never required
merely to preserve a package fact. Keep existing destination/type compatibility
checks, require an actual retained target, and reject collisions or competing
values rather than overwrite an existing field. The destination must preserve
all effective fields, qualifiers and provenance. A plain string service
inclusion/notes destination cannot silently absorb structured quantity,
frequency or applicability. A legacy hotel service cannot silently lose package
city/or-similar/night-count fields. If the supported mapping cannot preserve the
fact, keep it package-wide or require explicit valid corrections; block the map.
Do not flatten structure to prose or replicate a fact across several services.

Future review policy distinguishes:

| Issue class | Finalization behavior |
|---|---|
| `severity: blocker` | Blocks until concretely resolved, or validly overridden only under the existing narrow `other` policy with no invalid/lost content. |
| Structural code | Blocks while unresolved, regardless of a permissive AI severity/flag. Codes: `chronology_unknown`, `accommodation_span_unknown`, `classification_ambiguous`, `conflicting_dates`, `global_mapping_required`, `source_conflict`. Acknowledge/override cannot substitute for structural resolution. |
| Non-structural warning with `resolutionRequired: true` | Requires supported resolution or narrow valid `other` override. Acknowledgement is insufficient. |
| Non-structural warning with `resolutionRequired: false` | Open is non-blocking; acknowledgement is optional and audited. It does not change source truth. |
| Informational | Snapshot issues currently have only warning/blocker severities. Do not invent an `info` issue variant. Commercial presence is a separate assessment informational result. |

The shared pure assessment/assembly now enforces the structural-code rule above,
including historical acknowledgements that remain valid intermediate decisions.
It reuses existing concrete-resolution predicates and requires correction of the
actual target. Snapshot-wide issues have no typed affected-entity list, so the
policy conservatively requires concrete referenced coverage of every source day
and non-commercial fact; an unrelated correction cannot waive the issue. The
mutation contract remains unchanged and may store intermediate blocked states.

Adding a package destination does not silently resolve historical
`global_mapping_required` issues. An explicit “keep package-wide” action can
record a retain decision and a validated resolved-issue reference together when
the sole issue was lack of a package destination. Similarly, confirming an
undated package scope may resolve `accommodation_span_unknown` **only** where
the issue was inability to place it on a day, not conflicting/ambiguous supplied
dates. Future typed issue-resolution predicates must make that distinction
explicit; do not infer it from free-text issue messages. If the existing issue
cannot express/prove the narrower reason, keep it blocked until the consultant
supplies a supported concrete correction or exclusion. Never invent dates to
satisfy it. Actual date/source conflicts still require concrete resolution.

Targeted issue decisions must reference the actual correction, assignment,
mapping, scope confirmation or exclusion covering the issue. Excluding one
target resolves only issues whose affected content has genuinely been removed.
Snapshot-wide issues require coverage of all affected retained content. Default
inclusion, a bare acknowledgement, or an unrelated decision ID is not evidence.

Only applicable open non-blocking warnings enter the canonical `reviewIssues`
array, using deterministic IDs and valid canonical field targets. Resolved or
excluded-content issues remain in Snapshot/Resolution/receipt history, not as
false blockers on the resulting draft. If a warning cannot be projected without
losing its target meaning, preserve it in private review history and the visible
finalization summary; do not invent a canonical field reference.

### 25.5 Future pure finalization assessment

Keep assessment deterministic and separate from persistence/AI. It should
evaluate the same versioned assembly plan that preview and finalizer use,
return policy version/revision plus blockers/warnings/information, and account
for every input fact. Do not let the UI maintain a second acceptance checklist.

| Existing finding / situation | Future v2 policy |
|---|---|
| `unresolved_package_fact` solely because no explicit decision exists | Removed for safe untouched inclusions/exclusions/conditions; they have a real default destination. |
| `unresolved_package_accommodation` solely because no explicit decision exists | Removed for safe package accommodation. |
| `package_level_destination_unavailable` for `retain_package_level` | Removed after the entire v2 destination is implemented/enabled. Explicit retain is assessed like default package inclusion. |
| `incomplete_package_accommodation` solely because a day hotel needs a name | Not applicable to a valid package option with other meaningful fields. Still applies to a day mapping requiring that name. |
| `unsupported_package_accommodation_content` for city/or-similar/night count | Removed for the first-class package destination, which preserves them; remains for a lossy day mapping. |
| `unresolved_unassigned_service`, missing day/order/type/title/required details, duplicate ordering | Remain. No invented assignment or implicit descendant exclusion. |
| `unsupported_service_content` | Remains wherever the timeline cannot preserve retained fields. Root package support does not automatically move service-scoped facts into package content. |
| `unresolved_review_issue`, `structural_review_issue_unresolved` | Remain with section 25.4's exact predicates; default retention never resolves them. |
| `unresolved_ancillary_fact` | Remains without an actual supported disposition. A descriptive route name alone is not proof of a persisted ancillary result. |
| Malformed/foreign references, conflicting decisions, invalid provenance | Remain integrity failures before assessment/assembly; cannot be overridden. |
| Oversize, unsupported relationship, commercial/ancillary contamination, destination conflict | Typed blocking findings in the future policy. No truncation, arbitrary notes or guessed destination. |
| Explicit valid exclusion | No retained-content blocker for that fact; preserve exclusion outcome and check dependent issues/references. |

The existing timeline still lacks service-level structured conditions and some
accommodation detail fields. This package-only architecture does not declare
those representable or weaken `unsupported_service_content`. They require a
separate lossless timeline extension or an explicit valid consultant correction
before affected imports can finalize. V3 production readiness must not be
claimed just because package blockers have been resolved architecturally.

Flights/visas remain separate ancillary facts. Do not route them into `other`,
package notes or generic land services, including through a package statement's
existing `visa` category. A later real ancillary route needs a verified receipt;
a handled-separately choice must satisfy its own explicit audited policy. That
workflow is outside this decision. Exclusion remains explicit, never default.

Rates, prices, totals, currencies, supplements, markup, margins, payment amounts
and commercial terms are prohibited in canonical content and copied audit
payloads. Commercial-presence markers contain no values and are informational.
An operational `payment_basis` qualifier is not permission to add amounts or
commercial notes. Publication/reuse also apply private-content sanitization.

### 25.6 Trusted lineage and immutable finalization receipt

Inline package provenance preserves trusted extraction/package/fact identity,
validated source file where applicable, source label and contributing sparse
decisions/field operations. The backend supplies identities; provider-supplied
trusted IDs are never used. Manual content must remain explicitly consultant
authored, without forged Supplier references. Full field definitions and
client/reuse projections are in the draft model.

Create one private, immutable receipt at
`trips/{tripId}/supplier_extractions/{extractionId}/resolutions/{resolutionId}/finalizations/{commandId}`.
As in section 24.1, `resolutionId` equals `extractionId`; this adds an audit
subcollection under the existing Resolution rather than moving that aggregate.
Direct client writes are denied. Current client Rules default-deny this private
path for both reads and writes; no client access is added by the internal Admin
writer. Future receipt reads require the same current owner/Admin authorization
as the Resolution. The internal writer now implements these exact fields:

| Field | Required purpose / contents |
|---|---|
| `schemaVersion` | Literal `supplier_import_finalization_v1`. |
| `tripId`, `extractionId`, `resolutionId`, `sourcePackageId` | Trusted aggregate identities; exact Snapshot/Resolution linkage. |
| `finalizationId`, `commandId`, `actorUid`, `finalizedAt` | Idempotency/event identity (same command ID), authorized actor and server timestamp. |
| `evaluatedRevision`, `resultingRevision` | `R` and `R + 1`, matching the seal and event. |
| `policyVersion`, `canonicalSchemaVersion`, `resultingDraftId` | Exact policy, `itinerary_draft_v2` and committed output identity. |
| `requestFingerprint` | Backend canonical hash of the validated finalize command, actor, expected revision and policy; no raw arbitrary request payload. |
| `contentDigest` | Hash of the validated initial canonical payload, excluding server timestamps; deterministic serialization/version belongs to this receipt schema. Detects mismatched retries, not permission to overwrite later edits. |
| `outcomes` | Ordered complete ledger described below; no raw source prose, commercial values or file paths. |

Each outcome has required `targetKind`, `targetId`, `outcome`, `decisionIds`,
`outputTargets` and `fieldOperations`. Root title uses a controlled root target
with null ID; other targets identify real Snapshot/manual items. Outcomes cover
title, days, services, package facts, ancillary facts, review issues and
commercial-presence markers. Controlled outcomes distinguish default included,
explicit included/corrected, mapped, excluded, consultant authored, ancillary
handled, issue resolved/overridden/open warning/acknowledged, and informational
not included. They must not equate automatic inclusion with consultant approval.

`outputTargets` contains exact canonical entity IDs or day numbers plus closed
typed field identifiers (never arbitrary write paths). `fieldOperations`
contains only closed field names and set/clear operations linked to contributing
decisions; no duplicated unchanged values. Excluded/informational outcomes have
no output targets. Each eligible input has exactly one accounted outcome, even
if its fields target several compatible canonical fields. Timeline mappings
retain their complete contributor lineage here when legacy `sourceReference`
cannot express it inline. Immutable Snapshot and sealed decisions/audit provide
the source/actor history; the receipt references rather than duplicates it.

Later canonical edits neither mutate the receipt nor masquerade as the initial
Supplier Import result. Preserve initial reconstruction through sealed inputs,
policy version and digest; later quotation/version history remains independent.
Never publish receipts, source labels, internal issues or private source IDs to
clients or copying Agents. Reusable content is a separate sanitized projection,
not an adjacent mutable canonical package entity.

### 25.7 Firestore bounds and atomic finalization

Use bounded embedded package content; no subcollection/chunking fallback in
v2. Firestore's document limit is 1 MiB, map/array nesting limit is 20, API
request limit is 10 MiB, and transactions have a 270-second duration limit with
60-second idle expiry. Index limits also apply. These are platform ceilings,
not operating targets. See the official
[Firestore quotas](https://firebase.google.com/docs/firestore/quotas) and
[transaction documentation](https://firebase.google.com/docs/firestore/manage-data/transactions).

Adopt these stricter **application limits for the first finalizer**:

- Complete canonical root at most **768 KiB**, including field names, values,
  provenance and metadata under the conservative application calculation below.
- Its embedded `packageContent` at most **256 KiB** and at most **256 total
  records**, counting accommodation envelopes/options and every statement and
  condition. All existing source/override field limits continue to apply.
- Receipt at most **256 KiB**; sealed Resolution root and finalization event
  at most **32 KiB each**. Ledger growth counts toward the receipt limit.
- At most **2,000 Snapshot entities** and **2,000 current decisions/manual
  items combined** for one assessment, and **16 MiB** total serialized inputs.
  Events needed for authoritative validation count in this byte budget. The
  existing stored Resolution validator requires the complete contiguous audit
  chain; finalization reads it in bounded pages under the same 16 MiB guard,
  rather than weakening that integrity check. This adds no preview endpoint or
  unbounded history scan.
- At most **2 MiB** conservatively budgeted final commit, including document
  encoding/index reserve. The application estimate is not exact SDK encoding or
  index measurement; JSON character counts alone are insufficient.

Before enabling v2 writes, exempt the large embedded timeline/package/provenance
and receipt-ledger fields from indexing where they are never queried, while
preserving indexes required by real existing queries. Bound nesting below the
platform limit. This is a future deployment prerequisite, not permission to
edit indexes or deploy now. Reject output beyond any bound with a visible
capacity blocker. Preserve all evidence/decisions, make no partial canonical
write and do not truncate or tell consultants to discard correct facts to fit.
A larger import requires a separately versioned persistence extension.

Finalize with **four writes in one Firestore transaction**:

1. Create the canonical `itinerary_draft_v2` root, including package content and
   immutable `importResult` receipt/policy linkage.
2. Create the immutable finalization receipt.
3. Seal the Resolution as `finalized`, advance `R` to `R + 1`, and set its
   existing result/actor/time fields.
4. Create the append-only finalization event using the same `commandId`, revision
   pair and actor/time. Use the existing `action: finalize`,
   `targetKind: finalization`, `targetId: commandId`, and lifecycle metadata
   `{kind: lifecycle, status: finalized}`. The target resolves to the receipt;
   result identity is in the receipt and sealed root. Do not invent additional
   fields in the existing event metadata union.

No source job, Snapshot, decision or Storage object is changed by finalization.
No new quotation replaces an existing revision. No canonical `writing` phase
is needed because the bounded aggregate and visibility link commit together.

The safe protocol is:

1. Authenticate and read current Trip authorization. Read complete immutable
   Snapshot identity and Resolution root revision `R`, load bounded current
   children, then re-read root `R`. Reject/reload on change. All accepted child
   mutations must already advance the root atomically, as section 24 requires.
2. Outside the transaction, build the deterministic plan, assess issues, account
   for all facts, strictly validate v2 and enforce size limits. No model call.
   The finalize request includes the preview's expected revision/policy.
3. In the transaction perform all reads first. Recheck active owner/Admin and
   current Trip ownership, immutable complete Snapshot/linkage, enabled policy,
   Resolution active/revision `R`, and receipt/event/draft idempotency state.
   A stale preview or changed authorization cannot commit the prepared plan.
4. Use a backend deterministic draft ID in a reserved Supplier Import namespace
   derived from the Resolution identity. Create only; any unrelated existing
   document is a conflict, never overwritten. Receipt/event IDs use command ID.
5. Commit the four writes together with server timestamps. Conflict retries
   recheck conditions; never merge a changed revision into the old preview.
   Do not call AI, Storage, PDF generation or an external service in the callback.

On an ambiguous response, re-read the authorized Resolution/receipt/event/draft
identity tuple. The same command/actor/fingerprint with a consistent completed
tuple returns the same result as already applied, without a second write or
comparing against a subsequently edited draft's current content. A different
command cannot reopen a finalized Resolution. Mismatched/partial state is an
integrity failure requiring operational inspection, not cleanup or overwrite.
On a verified uncommitted retry, rerun the preconditions. PDF/client/reuse
projections are later derived from the committed result version only.

#### Implemented internal Admin boundary

`finalizeSupplierImportAdmin(db, actor, request)` accepts only `tripId`,
`extractionId`, `commandId`, `expectedRevision` and the supported `policyVersion`.
The separately trusted actor is `{uid, email}`; the existing Resolution-mutation
authorization function checks company domain, authoritative active profile,
Agent/Admin role and current Trip ownership. The engine repeats authorization
inside the transaction. No caller Snapshot, Resolution, candidate, receipt,
role, source-package truth or timestamp is accepted.

The writer derives `finalizationId = commandId` and the reserved draft ID
`supplier-import-${sha256(JSON.stringify([tripId, extractionId]))}` (UTF-8,
lowercase hex). Resolution identity stays `extractionId`. The canonical path is
`trips/{tripId}/itinerary_drafts/{draftId}`; receipt and event are the section
25.6 path and `.../resolutions/{extractionId}/events/{commandId}`. Only the
internal Admin entry point writes these artifacts; serializers do not persist.

Preflight uses the existing trusted Supplier Source metadata reader and strict
complete-Snapshot/stored-Resolution boundaries. Child collections use pages of
at most 32 documents; entity counts, combined decisions/manual counts and input
bytes are bounded. The Resolution root is read again after its children, and
the transaction rechecks its exact active revision/root and immutable Snapshot
root. Every valid child mutation already advances that root atomically, so
concurrent changes invalidate the plan. Assembly and the existing receipt factory
run before the transaction; blocked assessment or factory failure writes nothing.

All transactional reads precede the four writes. The draft, receipt and event
use create-only semantics; the root update contains only `status`, `revision`,
`resultingDraftId`, `updatedByUid`, `updatedAt`, `finalizedByUid`, `finalizedAt`.
One backend millisecond timestamp is captured before the retryable callback and
stored consistently as `Timestamp`. No random identities, clock reads, external
calls or logging occur inside the callback. Existing mutations reject a sealed
Resolution permanently.

Exact replay validates the receipt fingerprint/digest, reconstructs the initial
assembly from immutable Snapshot plus sealed Resolution history, and checks the
root/event/draft linkage. It returns `already_applied` with no writes or revision
increment, including after a lost commit acknowledgement. The digest is not
compared against later edited canonical prose. A different command cannot reopen
the Resolution; conflicting fingerprints, linkage, digest or partial artifacts
fail closed. Raw SDK text, error causes and source/commercial text are neither
logged nor returned. Infrastructure failures expose a generic internal error;
Firestore resource/known size errors become `persistence_capacity_exceeded`.

`supplierImportFinalizationStored.ts` applies the authoritative V2/receipt
validators around explicit Timestamp conversion. Root times and timeline dates
use Firestore Timestamp (UTC midnight for date-only timeline fields); package
dates remain strings. Non-millisecond stored times are rejected to avoid silent
loss in the Date-based domain. V1 and unknown versions cannot pass the V2 reader.
Unknown/undefined values fail; deterministic array/map content is preserved.

`supplierImportFinalizationCapacity.ts` measures UTF-8 JSON payload of plain
Firestore-compatible values plus document-path, node and map-field overhead.
The combined budget is twice the four-document estimate plus 4 KiB; nesting is
bounded below the platform ceiling. This conservative application estimate uses
no undocumented SDK internals and makes **no exact Firestore protobuf or index
size claim**. Firestore is the final hard limit. Any exceeded budget blocks
without truncation or writes. Required index exemptions remain a future rollout
prerequisite; no index or Rules changes are included here.

Deterministic tests exercise the actual Admin adapter with read-before-write,
optimistic version retry, create/update preconditions and atomic staged commits,
including the existing Admin child-mutation adapter. No production connection or
emulator is required for these tests. The authenticated callable now delegates
to this engine. A separate strict read-only Flutter V2 reader is now implemented;
no Finalize UI, extraction routing change or deployment is included.

#### Implemented authenticated callable (not deployed)

The Gen2 `finalizeSupplierImport` export runs in `asia-south2` under the existing
Node 22 runtime and shared Admin initialization. Its exact request is `tripId`,
`extractionId`, `commandId`, `expectedRevision`, `policyVersion`. It reuses the
Admin validator (bounded exact IDs, command maximum 128, positive safe revision
with safe successor, exact authoritative `supplier_import_exception_review_v1`
policy). Unknown fields and caller-owned actor/content/timestamp fields fail
before engine invocation. Authenticated UID/token email are the only actor
inputs; authoritative domain/profile/Trip checks remain in Admin.

The wrapper invokes the engine once, forwarding command, revision and policy
unchanged. It neither retries conflicts nor assembles or persists content.
`applied`/`already_applied` expose only outcome, Resolution ID, resulting
`revision` and `resultingDraftId`. `not_ready` is a normal assessment containing
Resolution ID, evaluated revision, false readiness, and blocker/warning
`code`/`targetKind`/`targetId` triples. Conflict returns the current revision;
not-started/finalized outcomes return their revision. Capacity remains a normal
outcome with its safe boundary. No private receipt or source payload is returned.

Authentication, authorization, invalid input, unavailable Snapshot/invalid trusted
state and unexpected infrastructure map respectively to `unauthenticated`,
`permission-denied`, `invalid-argument`, `failed-precondition` and `internal`.
Errors have fixed safe messages; logs record only function name and outcome/error
code. The callable is not deployed; Flutter review finalization UI is
implemented, and
`requestItineraryExtraction` remains on V2.4 with no V3 production cutover.

### 25.8 Rollout boundaries and future verification

No model/prompt/response schema, V2.4 processor, Firebase Rule or client changes
are made by this internal persistence implementation. The backend V2 validator,
stored reader/writer, shared assessment and bounded atomic receipt protocol now
have focused tests. Before enabling finalization, implement and test its trusted
callable deployment, production Flutter integration, projections and required access/index
support together. No job cutover is implied.

Backend tests now cover the assembly, persistence and replay cases below;
future rollout acceptance must also verify client and publication behavior:

- safe untouched package facts and assigned days/services finalize without
  per-fact decisions, preserving every field, count, ordering and provenance;
- absent optional dates stay absent, unassigned services still block, and
  unsupported service fields/ambiguous relationships never disappear;
- set/clear/exclude/map precedence, no duplicate mapped copy, real issue
  resolution and non-blocking optional warnings follow one policy;
- no commercial/ancillary escape hatch, no false source IDs, and reusable/client
  projections expose neither private lineage nor embedded private text;
- legacy drafts remain readable, old writers cannot destroy v2 data, and
  preview/finalize policy or revision mismatch creates zero writes;
- capacity edges, concurrent changes, permission changes, transaction failure,
  duplicate commands and ambiguous responses produce one consistent result or
  no commit, with a complete receipt/event and no overwritten history.

The canonical destination and default-review rules are settled. Remaining
separate work is limited to explicit flight/visa destinations, lossless timeline
field extensions and a typed multi-hotel alternatives grouping action where
the current Snapshot/Resolution cannot express the relationship. None may be
silently approximated to declare the whole V3 workflow ready.
