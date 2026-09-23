# Kayra Holiday Maps — Product Specification

## Product Purpose

Kayra Holiday Maps is initially an internal itinerary and quotation management platform for Kayra travel consultants. It will later evolve into a CRM. V1 is not a customer CRM portal.

## Primary Users

- Agent
- Admin

## Authentication and User Administration

- Google sign-in only
- Access restricted to @kholidaymaps.com
- New users default to Agent
- Initial Admin accounts can be seeded
- Admin can later promote/demote users
- Admin can deactivate users without deleting history
- Active trips must be reassigned before an Agent can be deactivated
- Reassignment may be bulk or individual
- New owner receives an in-app notification

## Clients

**Mandatory when creating a normal client:**

- First Name
- Last Name
- Mobile Number

**Optional:**

- Email
- City
- Company

**For Corporate/Group:**

- Company name is mandatory
- Multiple contacts supported
- Contacts and travellers are separate entities
- Client/contact may be different from traveller

## Travellers

**Eventually store:**

- First Name
- Last Name
- Date of Birth
- Gender
- Passport Number
- Passport Expiry
- Nationality
- Age must be system-calculated, never manually entered

Additional traveller data becomes relevant after the trip is Confirmed.
Passport information is not mandatory for domestic travel.
Incomplete post-confirmation traveller information gives warnings but does not block work.

## Age Rules

- Infant is globally defined as under 2 years
- Child/adult limits can vary by destination
- Hotel-specific override may supersede destination child-age rule
- Age is evaluated according to the relevant travel/check-out/end date

## New Trip Brief

**Required:**

- Client
- Destination(s)
- Travel Date
- Number of Nights
- Adults
- Children
- Infants
- Hotel Category
- Trip Type

**Hotel Category:**

- 3 Star
- 4 Star
- 5 Star
- Luxury

**Trip Type:**

- FIT
- Business
- Corporate
- Groups

**Trip names are auto-generated using:**

First Name + Last Name + Destination(s) + Travel Month/Year

One client may have multiple active trips.

## Supplier-First Workflow

- Every new itinerary normally starts from supplier/vendor material
- Client/trip must exist or be selected before supplier files are uploaded
- Multiple supplier files may be uploaded together as one source package
- Same trip may involve multiple suppliers
- Supplier information is never shown in client-facing material
- Supplier original content should remain stored for reference
- System extracts/structures supplier material
- Agent reviews/edits the draft
- AI uncertain fields are marked Needs Review
- Needs Review fields block Quote Prepared until resolved
- Agent resolves using Accept Extracted Value or Edit Value
- Corrections should be stored as structured extraction feedback
- Extraction learning should support supplier-specific behavior
- AI use should remain minimal and focused on document extraction/structuring/matching
- Do not add AI rewriting/polishing features by default

## Supported Source Inputs

**Product-level ingestion must be designed to support:**

- PDF
- DOCX
- XLSX/CSV
- Images/screenshots
- Pasted text
- Email content
- Multiple files

## Supplier Master

Store suppliers persistently.

**New supplier should capture at minimum:**

- Supplier/company name
- Contact person
- Phone
- Email
- Destination coverage
- Service categories

Multiple supplier contacts should be architecturally supported.

**When documents are uploaded:**

- attempt automatic supplier matching
- otherwise let Agent select existing supplier
- or add a new supplier

Maintain supplier quotation/rate history.
Historical rate comparison should support absolute and percentage change.

## Itinerary Reuse

Before using AI to generate a fresh itinerary, search existing reusable itineraries first.

**Similarity should consider:**

- Destination
- Travel month/season
- Number of nights
- Hotel category
- Trip type
- Traveller mix

Origin/departure airport is not required for itinerary similarity.

**Reusable itinerary from another Agent:**

- Show creator Agent
- Hide client identity/contact
- Hide suppliers/vendors
- Hide supplier documents
- Hide supplier costs
- Hide selling prices
- Hide margins/markups/discounts
- Hide payment data
- Hide internal notes
- Hide confirmation numbers
- Allow viewing travel structure/client-facing content

Reusing creates a fully independent copy belonging to the new Agent.
Later edits never flow back to the source.

**When reusing:**

### Clear

- supplier/vendor assignments
- supplier costs
- selling prices
- markups
- discounts
- confirmation numbers
- payment schedule
- client-specific data

Cross-agent reuse happens silently.
Admin analytics may later track reuse and AI cost savings.

## Hotel Master

Reusable Hotel Master supported.

**May store:**

- Hotel name
- City
- Master star category
- Standard description
- Contact details
- Lightweight approved images
- Hotel-specific child-age overrides

Client-facing star rating must use the supplier-provided rating for that quote.

Agents may propose new Hotel Master entries.
New entries remain Pending Admin Review.
Only Admin approves/edits/deletes existing master records.
Agent-created pending record may still be used in the current itinerary.
Duplicate detection should run before creating a new master entry.

## Activity/Sightseeing Master

Reusable master supported.

**May contain:**

- Destination
- Name
- Standard concise description
- Lightweight approved imagery
- Optional category/duration reference

Agents may propose entries.
Pending Admin Review rules are the same as Hotel Master.
Duplicate detection required.

No Transfer/Vehicle Master is required.

## Activity Content

Do not force a rigid activity schema.
Preserve supplier structure.
Extract clear fields when obvious.
Original supplier wording remains internally.
Agent may edit separate client-facing wording.
No AI polish button.

## Flights

Usually entered manually.

**Store full structured flight details including:**

- Airline
- Flight number
- Departure airport
- Arrival airport
- Departure date/time
- Arrival date/time
- Zero or more stops/segments
- Baggage
- Cabin class
- Booking class
- PNR
- Fare
- Ticketing deadline

Adult fare, Child fare, and Infant fare/taxes are separate internal fields.
Client-facing Agent can choose total airfare or per-person presentation.
Flights are always priced separately from the land package.
Every client-facing flight quote must prominently state that flight pricing is valid for 24 hours / subject to reconfirmation.

## Hotels

**Support fields including:**

- Hotel name
- City
- Check-in/check-out
- Room category
- Meal plan
- Number of rooms
- Occupancy count
- Child policy
- Confirmation number
- Supplier
- Supplier cost
- Selling price
- Cancellation policy
- Inclusions
- Special requests
- Hotel contact details

Some values such as confirmation number and supplier costing may be added later and should not block initial quoting.

## Rooming

**V1 uses simple:**

- Number of rooms
- Occupancy count

## Transfers

Transfer data remains supplier/itinerary-specific.
Use supplier source information similarly to hotel handling.
Do not create a global vehicle master in v1.

## Visa

**Keep simple:**

- Per-person cost
- Basic notes

Visa pricing is always displayed separately from land package and flights.

## Pricing

INR only in v1.

**Support:**

- Itemized supplier costing
- Lump-sum supplier package costing
- Both costing modes in the same quote
- Service-level markup
- Overall package markup
- Service-level discounts only
- Flights default to non-discountable

Do not calculate GST/TCS in v1.

**Client-facing proposal includes:**

"GST and TCS will be charged extra as applicable."

## Land Package

Flights and visa are always separate.

**Agent chooses whether land package is displayed as:**

- Total package price

or

- Per-person price

**For per-person land package pricing, Agent manually enters different:**

- Adult price
- Child price
- Infant price

Do not simply divide package total automatically.

## Quotations

One Trip may contain multiple separate quotations.
Each new quotation receives a globally unique reference number.

**Example style:**

KHM-YYYY-NNNNN

**Revision:**

- retains same quotation reference
- increments version

**Completely separate quotation:**

- receives new quotation reference

**Quote validity:**

- Fixed 7 days
- Expired quote shows warning
- Does not block Agent
- Pricing Review Recommended warning may appear in Needs Attention

## Multiple Options

One proposal may contain multiple options when the overall itinerary is substantially the same.
Recommended practical maximum: 3 options.
Each option is internally an independent snapshot.

Agent may optionally mark one option Recommended.

**Duplicating Option A to Option B:**

- Copy existing pricing
- Mark copied pricing clearly as Unreviewed
- Agent may review individually
- Agent may bulk confirm Reviewed All Copied Prices
- Unreviewed copied pricing blocks Quote Prepared

If itinerary structure is materially different, prefer a separate quotation rather than another option.

## Status Workflow

**Statuses:**

- Draft
- Quote Prepared
- Sent to Client
- Under Discussion
- Revised
- Client Approved
- On Hold
- Confirmed
- Cancelled
- Lost
- Travel Completed

**General lifecycle:**

Draft → Quote Prepared → Sent to Client → Under Discussion / Revised loop as needed → Client Approved → Confirmed → Travel Completed

Confirmed means required client deposit/payment has been received.

Travel Completed is a simple final successful status.

**Cancelled and Lost are distinct:**

- Lost = sale did not convert
- Cancelled = committed/approved/confirmed booking later cancelled

**Status changes require:**

- mandatory note
- minimum 20 characters
- previous status
- new status
- user
- timestamp
- quote/version context

Sent to Client and Under Discussion require Next Follow-up Date.

System suggests follow-up date based on urgency.
Agent may override it.
If selecting a later-than-recommended date, require a reason.

Reminder behavior in v1 remains basic.
Due/overdue items appear in dashboard.
No complicated advance-reminder system.

## Client Response Events

Keep separate from itinerary status.

**Support Agent-recorded client responses such as:**

- Approved
- Changes Requested
- Has Questions
- Needs More Time
- Declined
- Option Selected where relevant

In v1, client responses are recorded manually by Agent based on WhatsApp/email/phone communication.

## Client Approval

No online client approval workflow required in v1.
Architecture may permit it later.

## Payments

**Each quotation may define its own required deposit:**

- Fixed amount

or

- Percentage

Support multiple payment milestones/installments.

**Payment information may include:**

- Amount
- Due date
- Paid amount
- Payment date
- Method
- Transaction/reference number
- Receipt number
- Proof-of-payment attachment
- Internal notes
- Status such as Upcoming, Due, Partially Paid, Paid, Overdue

Confirmed is allowed only after the required deposit/payment threshold is received.

## Client-Facing Output

**Must eventually support BOTH:**

- Premium PDF
- Secure responsive web itinerary

Both must render from the same structured itinerary data.

**Web itinerary:**

- secure unguessable unique link
- no login/OTP in v1
- link remains valid indefinitely until revoked
- existing link automatically shows latest published version
- show Last Updated timestamp
- show assigned Kayra consultant name/phone/email

Proposal should not show general office/emergency number.
That may appear in final travel documents.

Client-facing supplier/vendor identity must never be exposed.

## Imagery

Automatically support destination/hotel/activity images.
Keep imagery lightweight.
Prefer compressed responsive assets.
Avoid excessive galleries.
Optimize PDF images aggressively.
Performance matters more than decorative image volume.

## PDF Final Travel Pack

**One downloadable PDF pack:**

- Kayra branded cover
- final itinerary
- vouchers/documents

Keep it simple: no table of contents required in v1.

**Voucher order:**

- system proposes logical trip-flow order
- Agent can manually reorder before final generation

Kayra-branded cover may precede supplier voucher material.

## Terms

Every proposal includes Kayra Standard Terms & Conditions.

**Terms are:**

- maintained by Admin
- completely locked for Agents
- snapshotted when proposal is first created
- later Admin changes apply only to future proposals

**Supplier cancellation conditions:**

- original wording retained internally
- Agent may create/edit client-facing wording
- Agent may hide supplier cancellation clauses from client output
- no reason required for hiding
- hide action should remain auditable

## Content Library

Destination-based reusable content library supported.

**May contain:**

- destination overview
- visa notes
- general inclusions/exclusions
- cancellation notes
- travel tips
- other standard content

Admin controls master content.
Agent may edit an inserted copy for the current itinerary.
Master updates affect future itineraries only.

## Operations

**When a trip becomes Confirmed:**

- create standardized global operations checklist
- Admin manages checklist in Settings
- Agents may add extra trip-specific checklist items
- V1 checklist is completed/not completed only
- no assignments/due dates required for checklist items in v1

**If Admin changes global checklist:**

- sync relevant changes to already-confirmed active trips
- preserve completed items
- notify affected Agent in-app about unchecked/new items

## Notifications

V1 uses simple in-app notifications only.
Read-once style feed is enough.

## Dashboard

Default Agent landing view is My Trips.

Agents do not browse other Agents' private trip records directly.
Reusable itinerary library provides sanitized access to reusable content.

**Dashboard should include:**

- Create New Itinerary
- Global Search
- Needs Attention
- My Trips
- optional List / Pipeline views later

My Trips should prioritize upcoming/urgent work rather than simple recent activity.

## Needs Attention

Use deterministic rules, not AI.

**Examples:**

- Travel approaching
- Overdue follow-up
- Client silence
- Pending deposit/payment
- Client Approved but not Confirmed
- Missing traveller details after confirmation
- Incomplete operations checklist
- Unresolved Needs Review fields
- Unreviewed copied pricing
- Supplier discrepancies
- Missing final documents
- Expired quote warning

Rank by severity/urgency.
Main dashboard shows top 6.
Provide View All for full Attention Queue.

## Global Search

**Search across:**

- Client name
- Mobile
- Trip
- Destination
- Quotation reference
- Supplier
- Hotel
- Activity
- Itinerary text
- Uploaded supplier-document extracted/indexed text

Search results must clearly identify result type and source.

Do not invoke AI for each search.
Create searchable/indexed representations during ingestion.

## Past Trips

Trips whose travel has finished belong in Past Trips after appropriate lifecycle completion.
Travel Completed remains searchable and reusable.

## Editing

Continuous auto-save.

**Display:**

- Saving
- Saved
- Save failed

Single active editor per itinerary.

**If another authorized user opens it:**

- show read-only
- show who is currently editing

Locks must expire safely if user leaves/disconnects.
Admin may force-release stale lock.

## Version History

Maintain meaningful restore points.
Do not create a visible version for every keystroke.

**Restore points include major:**

- itinerary structure changes
- pricing changes
- supplier reprocessing
- quote revisions
- status transitions
- pre-publish snapshots

Agents may view relevant history.
Only Admin may restore an older version.
Restore creates a new audit entry and must not erase subsequent history.

## Design

One standardized premium Kayra design.

**Brand:**

- Primary deep navy approximately #061742
- Crisp white/light surfaces
- Premium clean sans-serif typography
- restrained radius/shadows/borders
- professional B2B travel-tech appearance
- no generic admin-template look
- no purple gradients
- excellent responsive behavior

## AI Strategy

AI should be deliberately minimal.

**Primary AI purposes:**

- supplier document extraction
- first-draft structuring
- matching/normalization when useful

**Before AI generation:**

- search reusable itineraries first

**Do NOT introduce AI for:**

- normal search
- urgency scoring
- generic copy polishing
- deterministic calculations
- ordinary CRUD operations

## Future CRM

Architect entities and services cleanly enough that CRM functionality can later expand, but do NOT build unrelated CRM modules now.

## V1 Scope Discipline

We are currently building the itinerary-builder foundation. Do not implement future features merely because they appear in this specification. Features will be implemented incrementally only when explicitly requested.
