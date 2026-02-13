# Nu Privacy and Data Handling

## Data Collection
- Personal account data: **Not collected**
- Contact info: **Not collected**
- Health/biometric data: **Not collected**
- Ad tracking identifiers: **Not collected**

## Runtime Data Used
1. Location (When In Use)
- Purpose: fetch nearby stations and map station pins around user or visible region.
- Permission: `NSLocationWhenInUseUsageDescription` (English copy).
- Behavior on deny: app remains usable via search and manual map browsing.

2. Rejseplanen API requests
- Data sent: coordinates / station IDs / journey IDs required by API.
- Auth: accessId query parameter.
- Transport: HTTPS endpoint.

## Local Storage
- Favorites: station references (id/extId/globalId/name/type) in `UserDefaults`.
- Cache: nearby/departure snapshots in app cache store for resilience.
- No sensitive credentials should be persisted in source-controlled files.

## Third-party and External Services
- Rejseplanen/HAFAS API (transport data provider)
- Apple MapKit / CoreLocation

## App Store Compliance Notes
- Avoid hardcoding production API keys in repository code.
- Keep debug diagnostics disabled in Release builds.
- Keep ATS-compliant HTTPS-only endpoints unless explicit exception is documented.

## Open Risks
- API key currently present in source defaults (planned removal in P0).
- Full entitlement/ATS audit report not yet attached.
