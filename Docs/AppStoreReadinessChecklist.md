# Nu App Store Readiness Checklist

## Audit Scope
- Date: 2026-02-13
- Branch: `refactor/appstore-readiness`
- Scope: project structure, UI/HIG, localization, privacy/security, networking, performance, testing/release

## P0 (Release-blocking)

| ID | Area | Current Issue | Plan | Status | Evidence |
|---|---|---|---|---|---|
| P0-1 | Privacy copy | `NSLocationWhenInUseUsageDescription` is Danish, not English-only UI policy | Replace with clear English purpose text in Debug/Release build settings | Completed | `Nu.xcodeproj/project.pbxproj` now uses English location purpose text |
| P0-2 | Secrets | Rejseplanen `accessId` hardcoded in source (`AppConfig.defaultAccessID`) | Move key to build setting / env (`REJSEPLANEN_ACCESS_ID`), fail fast if missing in Release | Completed | `Nu/Core/AppConfig.swift` no longer contains committed key; `Info.plist` reads `REJSEPLANEN_ACCESS_ID` |
| P0-3 | Testing gate | `xcodebuild test` fails: scheme has no configured test targets | Add `NuTests` target and wire scheme TestAction | Completed | `xcodebuild ... test` now succeeds on `iPhone 17` simulator with passing tests |
| P0-4 | User-facing debug leakage | Request URLs / raw payload logs can leak identifiers in Debug workflows | Centralize debug logging and ensure fully excluded in Release | Completed | `Nu/Core/AppLogger.swift` + call-sites updated to `AppLogger.debug` |

## P1 (High-value before App Store submission)

| ID | Area | Current Issue | Plan | Status | Evidence |
|---|---|---|---|---|---|
| P1-1 | Architecture boundaries | Partial layering exists but Domain/UI/Networking boundaries are mixed in models and VMs | Formalize module boundaries and dependency direction; move pure business logic to Domain | In Progress | Added `Nu/Domain/JourneyProgressEstimator.swift`; JourneyDetail now consumes domain inference |
| P1-2 | Dependency Injection | `LocationManager` and storage use concrete types/singletons in several places | Introduce protocols for Location, Storage, Clock; inject through initializers | In Progress | Added `LocationManaging`, `KeyValueStoring`, `ClockProtocol`; wired VM/storage usage |
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

## Validation Results (2026-02-13)
- `build`: PASS (`** BUILD SUCCEEDED **`)
- `test`: PASS (`** TEST SUCCEEDED **` on `platform=iOS Simulator,name=iPhone 17`)
- `privacy key check`: PASS (`NSLocationWhenInUseUsageDescription` is English; hardcoded default accessId removed)
- unit tests added:
  - `NuCoreTests.testJourneyDetailURLEncodingEncodesPipe`
  - `NuCoreTests.testStationGroupingMergesSameBaseNameWithinThreshold`
  - `NuCoreTests.testORServiceHeuristicDistributionUsesRealtimeProfile`
  - `NuCoreTests.testORServiceCatchProbabilityStates`
  - `NuCoreTests.testJourneyProgressEstimatorInStopWindow`
  - `NuCoreTests.testJourneyProgressEstimatorAfterDestination`
  - `NuCoreTests.testNearbyViewModelRefreshBuildsGroupedStations` (Nearby -> grouped station flow)
  - `NuCoreTests.testDepartureBoardViewModelFetchPopulatesDepartures` (DepartureBoard flow)
