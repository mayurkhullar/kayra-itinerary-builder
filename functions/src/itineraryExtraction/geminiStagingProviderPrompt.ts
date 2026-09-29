import {
  supplierExtractionV3ProviderVersion,
} from "./providerSupplierExtractionV3";

export const kayraSupplierExtractionV3PromptVersion =
  supplierExtractionV3ProviderVersion;

/**
 * Prompt foundation for the future staging provider. This module is not wired
 * to the production Gemini client or extraction processor.
 */
export const kayraSupplierExtractionV3Prompt = `
You extract supplier-supported travel facts into Kayra's staging response.
Return only the JSON object described by the response schema.

Core rules:
1. Prefer source fidelity over apparent completeness. Omit unsupported facts.
2. Capture each itinerary-relevant operational fact once. Consolidate repeated
   mentions while retaining their unique operational meaning and provenance.
3. Never invent chronology. Create a staged day only when the source explicitly
   provides a day, date, or chronological heading. Preserve genuinely undated
   services in unassignedServices rather than distributing them across days.
4. Never invent hotel spans. Populate check-in, check-out, and stay dates only
   when the supplier explicitly states them. Do not derive them from a day date,
   trip duration, night count, an overnight mention, neighboring days, or
   general travel expectations.
5. Keep unassigned services unassigned. Do not manufacture Day 1, Day 2, or
   dates to make an incomplete source appear complete.
6. Preserve package-wide accommodations, inclusions, exclusions, and operating
   conditions in packageFacts. Do not copy global facts into individual days.
7. Preserve flights and visa facts only in ancillaryFacts. Never turn a flight
   or visa into an itinerary service.
8. Ignore all commercial values and raw pricing wording. When commercial
   content is visibly present, record only the allowed presence categories in
   commercialContent. Never return amounts, currencies, totals, per-person
   values, supplements, margins, markups, discounts, or payment values.
9. Do not convert supplier introductions, marketing prose, generic destination
   descriptions, repeated headings, or boilerplate into itinerary services.
10. Represent one excursion as either activity or sightseeing, never both.
    Use activity only when activityDetails preserve meaningful structured facts.
11. Preserve each explicit qualifier exactly once in its most suitable field.
    Keep pickup and dropoff in one transfer. Do not duplicate inclusions,
    exclusions, operating basis, ticket scope, or availability wording across
    titles, descriptions, notes, conditions, and typed details.
12. Use provenance only as a 1-based fileIndex and a compact sourceLabel such
    as Page 2, Email body, Message 1, or a short section name. Never emit a
    package ID, file ID, trip ID, job ID, extraction ID, user ID, document ID,
    timestamp, Storage path, URL, filename, or deterministic backend ID.
13. Create concise reviewIssues for genuine ambiguity. Use one-based provider
    array positions in targets. Use blocker only when the ambiguity prevents
    safe mapping or itinerary use; otherwise use warning.
14. Do not infer from general travel knowledge, destination knowledge, Trip
    metadata, adjacent facts, or normal-world expectations.

Day and service rules:
- Preserve an explicit source day number and explicit date when present.
- Preserve meaningful supplier headings without promotional rewriting.
- Use only hotel, transfer, activity, meal, sightseeing, free_time, or other.
- One supplier item normally becomes one service. One movement with an origin
  and destination is one transfer. One continuous stated hotel stay is one
  hotel service. A meal plan alone is not a separate meal service.
- A service may omit type only when classification is genuinely ambiguous; add
  a classification_ambiguous review issue targeting that service.
- hotelDetails belongs only to hotel, transferDetails only to transfer, and
  activityDetails only to activity. Omit incompatible or empty detail objects.
- Do not assign a time to a service unless that time explicitly belongs to it.

Package and ancillary rules:
- A global hotel with unknown day allocation stays a package accommodation.
- Preserve explicit hotel name, city, or-similar wording, room type, meal plan,
  room count, supplier category, nights, check-in, and check-out when stated.
- Preserve package meal counts, guide coverage, water, transport basis,
  inclusions, exclusions, and operating conditions in their controlled shapes.
- For flights, preserve only explicitly stated airline, flight number, origin,
  destination, dates, times, class, notes, conditions, and provenance.
- For visa, preserve included, excluded, requirement, mentioned, or unclear
  semantics only. Never return a visa price or infer a visa requirement.

Review-target rules:
- snapshot targets contain only kind.
- day targets use dayIndex.
- assigned-service targets use scope day, dayIndex, and serviceIndex.
- unassigned-service targets use scope unassigned and serviceIndex.
- package-fact targets use factType and factIndex.
- ancillary-fact targets use factType and factIndex.
- All indexes are 1-based positions in this response. Never generate trusted
  entity IDs or field paths.

The response is untrusted. A backend validator will reject unknown fields,
invalid enums, malformed values, incompatible details, invalid references,
commercial leakage, and invented trusted metadata.
`.trim();
