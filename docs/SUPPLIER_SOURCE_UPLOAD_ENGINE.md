# Supplier Source upload engine

## Canonical multi-channel architecture

Kayra is supplier-format-agnostic. Supplier layout and capture channel affect
how evidence enters the system, but never create a separate itinerary domain.
All channels converge on the same boundary:

```text
PDF / image / CSV / text / pasted email / pasted WhatsApp / future connector
    -> Supplier Source ingestion
    -> semantic extraction
    -> trusted normalization
    -> one canonical Kayra itinerary draft model
```

There must be no Supplier A parser, Supplier B parser, email itinerary schema or
WhatsApp itinerary schema. Channel adapters may capture and validate evidence;
they do not decide the downstream domain model. Semantic extraction interprets
the evidence, and trusted normalization alone maps supported facts into the
canonical draft contract.

### Current and target channels

| Channel | Status | Contract |
|---|---|---|
| PDF file | Current | Private file-backed Supplier Source; production extraction input. |
| JPG, PNG or WebP | Current | Private image-backed source, including screenshots and scanned itineraries; production extraction input. |
| TXT | Current | Private UTF-8 file-backed source; production extraction input. |
| CSV | Current | Private file-backed source decoded as bounded UTF-8 text for extraction. |
| DOC, DOCX, XLS or XLSX | Current upload only | Retained as private source evidence, but currently rejected as `unsupported_source` by production extraction. |
| Pasted plain text | Near-term target | Copied email, WhatsApp or other supplier-message text; capture and trusted persistence are not implemented yet. |
| Direct email ingestion | Future adapter | Must create the same Supplier Source representation and use the same extraction pipeline. |
| WhatsApp ingestion/import | Future adapter | Must create the same Supplier Source representation and use the same extraction pipeline. |
| Other connectors | Future adapter | Must stop at the shared Supplier Source boundary. |

Direct email and WhatsApp integrations do not exist today. Current persistence
and trusted reading are file-centric. The target Supplier Source concept may
eventually contain evidence captured as a file, image or pasted text, but this
document does not prescribe or implement a new persistence shape.

### Source-package invariants

- The client and Trip must already be selected before source capture.
- Every item in one Source Package belongs to the same supplier.
- Evidence from another supplier requires another Source Package, even for the
  same Trip.
- Multiple same-supplier items may be kept together when they form one evidence
  set; their trusted order and individual provenance remain intact.
- Package and item identity come from trusted application/backend context, not
  extracted content.
- Original evidence remains private. No public or signed source URL is part of
  the ingestion or extraction contract.
- An extracted draft is provisional. A consultant reviews it before downstream
  quotation use.

## Partial-source and no-invention policy

A Supplier Source is evidence, not a promise of completeness. It may contain a
full chronology, a few inclusions, a global hotel declaration, or facts spread
across narrative, tables and separate files. Extraction must preserve supported
facts without fabricating the structure that is absent.

For every fact, normalization must do one of three things:

1. Map it to the canonical draft when both the fact and its relationship to that
   structure are supported.
2. Leave the uncertain target field unset and create a concise warning or
   blocker when consultant resolution is needed.
3. Keep it outside the persisted draft when the current model has no safe
   representation. Retain the original Supplier Source, surface the structural
   gap for review and use a future staging/import mechanism to preserve the fact
   in structured form.

Missing chronology, dates, hotel stays, times, classifications and service
relationships must never be inferred merely to produce a complete-looking
draft. An incomplete but trustworthy result is preferable to a falsely complete
one. Review issues record uncertainty; they must not be used as justification
to persist an unsupported value.

### Chronology and day mapping

- When the source explicitly supplies a day number, date or service-to-day
  relationship, preserve it.
- A date belongs only to the fact or service the source associates it with.
- When services or inclusions have no chronology, do not distribute them across
  days, infer dates from Trip metadata, or attach them to an arbitrary day.
- Add Needs Review when chronology is important but missing or ambiguous.
- If no current draft location can preserve an unassigned fact without implying
  chronology, do not manufacture a placeholder itinerary day. The fact requires
  a future staging/import representation or explicit consultant mapping.

### Global and package-level facts

Sources may state one hotel for the package, a basis that applies to all tours
or transfers, a daily meal or water inclusion, one guide for the trip, or a pass
valid across several days. Preserve the declared scope. Do not mechanically
copy a global fact into every day or service unless the source explicitly maps
it that way.

When a global statement can be safely attached to an existing canonical field
or an explicit source-defined service, normalize it once there. Otherwise it
must remain pending in a future package-level staging/review structure rather
than being duplicated or assigned arbitrarily.

### Itinerary facts versus commercial content

Supplier quotations often mix itinerary semantics with price and commercial
terms. Extraction must separate them:

- Supplier prices, per-person amounts, supplements, total quotation prices,
  visa prices, FOC terms, costs, margins and payment data do not enter the
  itinerary draft.
- Non-commercial operational facts remain eligible: included visa, excluded
  meals or entrance tickets, hotel accommodation, guide, water, ticket class,
  transfer basis, tours and other supported inclusions or exclusions.
- For “Visa included — USD 30 per person,” “Visa included” is a potential
  ancillary/inclusion fact while “USD 30 per person” is commercial data. The
  current itinerary draft deliberately excludes visa, so the semantic fact
  needs a future appropriate domain or staging representation; it must not be
  forced into a day service or discarded together with the price.

## Current canonical-model gaps

The persisted `KayraItineraryDraft` is intentionally day-centric: services live
only inside ordered days, each day requires a positive day number and title, and
the root contains no unassigned-service or general package-fact collection.
Consequently:

- an undated service with no source-supported day cannot be persisted without
  implying chronology;
- package-level inclusions, exclusions and operational scope have no clean
  first-class location;
- a global hotel with no explicit day or stay span cannot be attached safely;
- a review issue can flag these gaps but cannot itself preserve the complete
  structured fact; and
- flights and visa remain deliberately outside the current day-service model.

The model can store an empty or partial day list and review issues, so it can
represent that a draft is incomplete. It cannot yet retain every unassigned or
global fact in structured form. A future staging/import representation or
explicit consultant-mapping workflow is therefore required before those facts
can cross into the canonical draft. This task does not select or implement that
future model.

## Quality-first extraction policy

Extraction optimization follows this order:

1. Source fidelity
2. Completeness
3. Correct semantic structure
4. Correct uncertainty handling
5. Provenance
6. Presentation compactness
7. Latency

Approximately 20–30 seconds for one extraction is currently acceptable when it
materially improves quality. This priority does not authorize extra provider
calls or a performance change by itself.

## Multi-supplier validation corpus

Extraction is not mature until it performs consistently across a privacy-safe
corpus containing at least these archetypes:

| Fixture | Required variation and focus |
|---|---|
| Detailed day-by-day PDF | Explicit chronology, dates and service-level hotel, transfer and activity facts. |
| Narrative PDF | Package heading, global declarations and facts distributed across prose and day bullets. |
| Table-heavy PDF or email | Day/date/itinerary rows plus separate hotel, inclusion, exclusion and commercial tables. |
| Short WhatsApp or plain-text quotation | Dense inclusions and services, potentially without dates or day mapping. |
| Screenshot or image source | Email/WhatsApp screenshot or scanned itinerary with layout and OCR challenges. |
| Global-hotel/package-inclusions source | Package-level scope that must not be repeated mechanically across days. |
| Incomplete-chronology source | Supported services without safe day assignments; requires review rather than invention. |
| Mixed pricing and itinerary source | Operational facts must survive while commercial values remain excluded. |
| Multi-file same-supplier package | Facts and provenance distributed across ordered files without cross-supplier mixing. |
| Poor-quality or scanned source | Unclear text, missing regions and uncertainty that must surface explicitly. |

Every fixture must be checked source by source for:

- missing source-supported facts;
- invented facts;
- service classification;
- dates, times and chronology;
- hotel, transfer, activity and sightseeing facts;
- inclusions and exclusions;
- global/package-level facts;
- uncertainty and review issues;
- package, file and page provenance where determinable;
- commercial-data leakage; and
- unnecessary duplication.

Fixtures and documentation must contain no real supplier or client private data.
The corpus should include structurally different suppliers and channels, not
multiple cosmetic variants of one benchmark.

## Current file-upload implementation

The current Flutter upload flow selects candidates with
`PlatformSupplierSourceFilePicker`, then passes a non-empty selection, an
existing Trip ID and the authenticated session UID to
`SupplierSourceUploadService`.
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
