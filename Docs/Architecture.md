# Nu Architecture

## Overview
Nu uses SwiftUI + MVVM with a service-based data layer. The target architecture is a pragmatic layered model:

1. `Core/`
- App configuration
- Error definitions
- Logging/diagnostics flags
- Feature flags and common policies

2. `Networking/`
- `HafasClient` request execution
- Request construction (service path, query, encoding)
- Retry/cancellation/rate-limit hooks

3. `Domain/` (target)
- Pure logic, no UI framework dependency:
  - ETA interval
  - Reliability score
  - Catch probability
  - Station grouping
  - Journey progress inference

4. `Features/` (target split)
- Nearby
- DepartureBoard
- JourneyDetail
- Map

5. `UIComponents/`
- Reusable presentational components and style tokens

6. `Resources/`
- English-only localizable strings
- Assets

## Dependency Direction
- Views -> ViewModels -> Services/Domain
- Services -> Networking/Core
- Domain -> Core only (no UI / no networking)

## Why this structure
- Keeps business logic testable without UI/runtime coupling.
- Prevents transport/API concerns from leaking into row rendering code.
- Enables App Store readiness checks per layer (privacy, performance, localization).

## Current Gaps
- Some domain logic still sits in models/viewmodels.
- `LocationManager` and storage are not fully protocol-driven.
- Dedicated test target is missing, preventing `xcodebuild test`.

## Refactor Plan
1. Complete protocol DI for location/storage/clock/network.
2. Move pure logic into `Domain/` with unit tests.
3. Keep feature VMs thin: fetch + map + state only.
