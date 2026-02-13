# Nu App Store Readiness Checklist

## Audit Scope
- Date: 2026-02-13
- Branch: `refactor/appstore-readiness`
- Scope: project structure, UI/HIG, localization, privacy/security, networking, performance, testing/release

## P0 (Release-blocking)

| ID | Area | Current Issue | Plan | Status | Evidence |
|---|---|---|---|---|---|
| P0-1 | Privacy copy | `NSLocationWhenInUseUsageDescription` is Danish, not English-only UI policy | Replace with clear English purpose text in Debug/Release build settings | In Progress | `Nu.xcodeproj/project.pbxproj` contains `Vi bruger din lokation...` |
| P0-2 | Secrets | Rejseplanen `accessId` hardcoded in source (`AppConfig.defaultAccessID`) | Move key to build setting / env (`REJSEPLANEN_ACCESS_ID`), fail fast if missing in Release | In Progress | `Nu/Core/AppConfig.swift` |
| P0-3 | Testing gate | `xcodebuild test` fails: scheme has no configured test targets | Add `NuTests` target and wire scheme TestAction | In Progress | `xcodebuild ... test` output: `Scheme Nu is not currently configured for the test action.` |
| P0-4 | User-facing debug leakage | Request URLs / raw payload logs can leak identifiers in Debug workflows | Centralize debug logging and ensure fully excluded in Release | In Progress | `Nu/Services/RejseplanenAPIService.swift`, `Nu/Networking/HafasClient.swift` |

## P1 (High-value before App Store submission)

| ID | Area | Current Issue | Plan | Status | Evidence |
|---|---|---|---|---|---|
| P1-1 | Architecture boundaries | Partial layering exists but Domain/UI/Networking boundaries are mixed in models and VMs | Formalize module boundaries and dependency direction; move pure business logic to Domain | In Progress | Mixed logic in `Nu/Models` + `Nu/ViewModels` |
| P1-2 | Dependency Injection | `LocationManager` and storage use concrete types/singletons in several places | Introduce protocols for Location, Storage, Clock; inject through initializers | In Progress | `NearbyStationsViewModel`, `DepartureBoardViewModel`, `FavoritesManager.shared` |
| P1-3 | Error taxonomy | API/network/decode/data-missing handled, but not consistently mapped to UI states | Unify error mapping and fallback copy for all screens | In Progress | `APIError` + per-VM ad-hoc handling |
| P1-4 | Accessibility | Many controls already labeled; full pass still missing for map annotations and composite rows | Add/accessibility labels+hints; verify Dynamic Type truncation paths | In Progress | Screens under `Nu/Views/Screens` |
| P1-5 | Performance evidence | Optimizations implemented, but no Instruments artifacts checked in | Capture before/after CPU + SwiftUI recompute + CoreAnimation evidence | Pending | No profiling docs/screenshots in repo |
| P1-6 | CI reproducibility | No unified build/test/lint/format command surface in root docs | Add README + scripts/Makefile command set for local and CI | In Progress | Root has no README/CI command docs |

## P2 (Post-submission hardening)

| ID | Area | Current Issue | Plan | Status |
|---|---|---|---|---|
| P2-1 | Persistent cache governance | Cache TTL and data retention are implicit | Add retention policy + cleanup schedule + docs | Pending |
| P2-2 | Versioning discipline | Marketing/build version exists but no documented increment policy | Document SemVer + build increment release checklist | Pending |
| P2-3 | ATS and entitlement audit report | No explicit written audit report artifact | Add explicit ATS/entitlement checklist with screenshot evidence | Pending |

## Work Order
1. P0-1 / P0-2 / P0-4 (privacy + key handling + log hygiene)
2. P0-3 (testing target and scheme)
3. P1-1 / P1-2 (architecture + DI)
4. P1-3 / P1-4 / P1-6
5. P1-5 evidence capture

## Validation Commands (current baseline)
```bash
xcodebuild -project Nu.xcodeproj -scheme Nu -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Nu.xcodeproj -scheme Nu -destination 'generic/platform=iOS Simulator' test
rg -n "Vi bruger din lokation|defaultAccessID|print\(" Nu
```
