# Nu

`Nu` is a native iOS transit app portfolio project built with SwiftUI. It focuses on real commuter workflows: nearby stations, departure boards, journey detail, favorites, map exploration, walking ETA support, and vehicle-tracking-oriented flows backed by Rejseplanen/HAFAS-style APIs.

## Portfolio Project Context

This repository is published as a portfolio project.

- It is intentionally more substantial than a sample CRUD app
- It emphasizes product thinking, external API integration, app architecture, and release-minded engineering choices
- It is meant to be readable by both engineers and hiring managers

## For Recruiters and Hiring Managers

If you are reviewing this repository as a portfolio project:

- `Nu` is a native app project, not a toy CRUD sample.
- It demonstrates API integration, location-aware UX, MVVM state management, dependency injection, caching, privacy-aware configuration, and test coverage on core logic.
- The fastest way to evaluate it is:
  1. read this README
  2. read `Docs/HIRING_MANAGER_GUIDE.md`
  3. scan `Docs/Architecture.md`
  4. inspect `Nu/Networking/HafasClient.swift`, `Nu/Core/AppConfig.swift`, and `NuTests/NuCoreTests.swift`

## Project Snapshot

- Platform: iOS
- Language: Swift
- UI: SwiftUI
- Architecture: pragmatic MVVM with layered services and domain logic extraction
- External systems: Rejseplanen / HAFAS transport APIs, Apple MapKit, CoreLocation
- Primary concerns covered:
  - transport API integration
  - location-aware discovery flows
  - stateful UI for transit data
  - favorites and lightweight local persistence
  - release-readiness, privacy, and secret handling

## Key Features

- Nearby stations flow driven by user location
- Station hub and departure board browsing
- Journey detail flow
- Favorites management
- Map-based station exploration
- Walking ETA and delay-aware presentation work
- Vehicle tracking map flows
- Error-state and stale-data handling

## Repository Structure

```text
Nu/
├── Nu/                  # App source
├── NuTests/             # Tests
├── Docs/                # Architecture, privacy, release, security notes
├── Nu.xcodeproj/        # Xcode project
├── Makefile             # Convenience commands
└── README.md
```

Important directories inside `Nu/`:

- `Core/`: app configuration, errors, diagnostics, shared policies
- `Networking/`: HTTP request construction and transport client logic
- `Services/`: API-facing services and app services
- `Domain/`: business logic extracted away from UI
- `ViewModels/`: screen state and orchestration
- `Views/`: SwiftUI screens and reusable components

## Why This Repo Matters

This repository is intended to show more than UI polish. It demonstrates:

- product thinking around high-frequency transit use cases
- handling of real external data instead of mock-only demos
- pragmatic app architecture that is readable and testable
- awareness of privacy, secrets, and release constraints
- ability to document tradeoffs and current limitations honestly

## Local Setup

### Prerequisites

- macOS with Xcode 16 or newer
- iOS Simulator runtime
- optional: `swiftlint`
- optional: `swiftformat`
- a valid `REJSEPLANEN_ACCESS_ID` for live API-backed features

### Build

```bash
make build
```

Equivalent command:

```bash
xcodebuild -project Nu.xcodeproj -scheme Nu -destination 'generic/platform=iOS Simulator' build
```

### Test

```bash
make test
```

Equivalent command:

```bash
xcodebuild -project Nu.xcodeproj -scheme Nu -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Lint and Format

```bash
make lint
make format
```

## Runtime Configuration

The project does not ship with a committed production credential.

Required for live transport data:

- `REJSEPLANEN_ACCESS_ID`

Optional:

- `REJSEPLANEN_BASE_URL`
- `REJSEPLANEN_API_VERSION`
- `REJSEPLANEN_AUTH_BEARER`
- `NU_WALK_ETA_MULTIPLIER`
- `NU_WALK_ETA_OVERHEAD_SECONDS`
- `NU_API_GENERAL_MIN_INTERVAL`
- `NU_API_POLLING_MIN_INTERVAL`

### Recommended local configuration

Use one of these approaches:

1. Xcode scheme environment variable
   Set `REJSEPLANEN_ACCESS_ID=<your key>`
2. Build setting / Info.plist-backed injection
   Provide `REJSEPLANEN_ACCESS_ID`
3. CI environment variable
   Export `REJSEPLANEN_ACCESS_ID` before calling `xcodebuild`

If no valid access ID is configured, API-backed runtime features fail explicitly instead of silently using a committed default.

### Open-source publishing note

Before pushing publicly:

- keep `REJSEPLANEN_ACCESS_ID` and any optional bearer token out of git history
- avoid committing simulator/debug artifacts from `.debug-artifacts/`
- avoid committing local Xcode user data, caches, or `.env` files
- rotate any credential immediately if it was ever committed by mistake

## Documentation Map

- `Docs/HIRING_MANAGER_GUIDE.md`: non-engineering-friendly evaluation guide
- `Docs/Architecture.md`: codebase structure and dependency direction
- `Docs/Privacy.md`: runtime data handling and storage notes
- `Docs/SecurityAudit.md`: ATS, entitlement, and secret-handling posture
- `Docs/ReleaseEngineering.md`: versioning and release checklist
- `Docs/MapDebugging.md`: fixed simulator commands for map debugging and screenshots
- `Docs/AppStoreReadinessChecklist.md`: audit-style readiness notes
- `SECURITY.md`: public security reporting expectations

## Current Status

This is a serious portfolio repository, not a claim of finished commercial production readiness.

What is already here:

- working app structure with multiple transit-facing user flows
- test target with core logic and flow coverage
- explicit privacy and release documentation
- secret handling moved out of committed defaults

What remains intentionally honest:

- live data depends on external API access
- some architectural cleanup is still documented as ongoing
- App Store submission polish and full operationalization would still require additional work

## License

MIT. See `LICENSE`.
