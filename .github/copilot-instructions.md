# Development Instructions

## Project and scope

- Product: **Kayra Holiday Maps**. Repository/project: `kayra_crm_v1`.
- Build a Flutter application for **Web first, Android later**, with Firebase as the backend.
- Begin with the itinerary-builder foundation; keep the architecture ready for a future full CRM without prematurely building unrelated CRM features.

## Architecture and code quality

- Use clean, maintainable, feature-based Flutter architecture. Separate UI, business logic, repositories/services, and data models.
- Avoid giant files and giant widgets; prefer reusable components.
- Use null safety and current Flutter best practices.
- Avoid unnecessary dependencies; introduce a package only when there is a clear need.
- Do not silently rewrite working architecture. Preserve existing working functionality when making changes.
- Add clear comments only where logic is genuinely non-obvious.
- Never hard-code secrets, API keys, credentials, or Firebase secrets.

## User experience

- Maintain a premium B2B travel appearance: primary Deep Navy approximately `#061742`, crisp white/light neutral backgrounds, and clean, luxurious sans-serif typography.
- Use restrained borders/shadows and rounded corners without cartoonish rounding. No purple SaaS gradients or generic AI-dashboard appearance.
- Support responsive layouts from mobile through large desktop. Use desktop space intelligently instead of stretching every element.
- Provide comfortable minimum mobile touch targets, accessibility, and clear focus states.

## Coding workflow

- Make small, incremental changes. Do not combine several unrelated features in one task.
- Inspect related files before changing an existing feature.
- Run Flutter analysis after meaningful changes.
- Keep Web support working at all times and preserve compatibility with future Android deployment.
- Do not implement iOS unless specifically requested.
- Do not implement AI functionality unless explicitly requested. Keep AI usage deliberately minimal because operating cost matters.

## Security and roles

- V1 is an internal application. Use Google authentication only; only `@kholidaymaps.com` accounts may access the application.
- New authenticated users default to **Agent**. **Admin** is controlled by application data/settings and includes all Agent abilities.
- Agents manage only trips they currently own. Admin can see and manage all trips.
- Never rely only on UI hiding for authorization. When Firebase is added, Firebase security rules must enforce access server-side.
- Agents may access sanitized reusable itineraries created by other Agents. Cross-agent reusable views may show the original Kayra Agent who created the itinerary and reusable travel content.
- Those views must hide original client identity/contact information, supplier/vendor identity, supplier documents, pricing/costing, margins, payments, confirmation numbers, and internal notes.

## Data safety

- Record an audit trail for important status changes and administrative actions.
- Never destructively overwrite historical quotation revisions.
- Only Admin may restore versions; restoration must preserve history.
- Architect for eventual continuous auto-save and only one active editor per itinerary at a time.

Before implementing a feature, read docs/PRODUCT_SPEC.md for product rules.
