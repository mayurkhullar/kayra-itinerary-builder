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

This model deliberately excludes pricing, margins, payments, flights, visa,
AI-provider payloads, extraction confidence scores, and master-record matching.
