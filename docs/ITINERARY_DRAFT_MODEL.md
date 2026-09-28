# Structured itinerary draft model

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
