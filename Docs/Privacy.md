# Nu Privacy and Data Handling

## Data Collection
- Personal account data: **Not collected**
- Contact info: **Not collected**
- Health/biometric data: **Not collected**
- Ad tracking identifiers: **Not collected**

## Runtime Data Used

### 1. Location (When In Use)
- Purpose: fetch nearby stations and map station pins around the user or the currently visible map region.
- Permission: `NSLocationWhenInUseUsageDescription` (English copy).
- Behavior on deny: the app remains usable via manual browsing and other non-location-driven flows, but nearby/location-assisted features are limited.

### 2. Rejseplanen API Requests
- Data sent: coordinates, station IDs, journey IDs, and related transport query parameters required by the API.
- Auth: `accessId` query parameter derived from `REJSEPLANEN_ACCESS_ID`.
- Transport: HTTPS endpoint.
- Scope: used for nearby stops, departure boards, journey detail, trip / walking ETA, vehicle tracking, and related HAFAS-backed features.

## API Key Handling
- The app does **not** embed a default or hardcoded Rejseplanen production key in source code.
- `REJSEPLANEN_ACCESS_ID` must be supplied explicitly through environment configuration or build settings / Info.plist-backed configuration.
- If no valid key is configured, API-backed requests fail with a missing access ID error instead of silently falling back to a committed credential.
- Production or personal API credentials should never be committed to source-controlled files.

## Local Storage
- Favorites: station references (`id`, `extId`, `globalId`, `name`, `type`) in `UserDefaults`.
- Cache: nearby/departure snapshots in app cache store for resilience.
  - Nearby cache TTL: 180 seconds
  - Departure cache TTL: 90 seconds
  - Expired entries are ignored by the read path.
- Departure delay preference: locally stored user preference for the departure board walking/delay UI.
- No sensitive credentials should be persisted in source-controlled files.

## Third-party and External Services
- Rejseplanen/HAFAS API (transport data provider)
- Apple MapKit / CoreLocation

## App Store Compliance Notes
- Avoid hardcoding production API keys in repository code or shipped defaults.
- Keep debug diagnostics disabled in Release builds.
- Keep ATS-compliant HTTPS-only endpoints unless an explicit exception is documented.

## Open Risks
- No critical privacy blockers identified in the current implementation.
- Operational risk remains if a developer manually places a real API key into a tracked file or committed build setting.
- See `Docs/SecurityAudit.md` for ATS/entitlement audit details.