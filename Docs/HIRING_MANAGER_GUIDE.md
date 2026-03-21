# Hiring Manager Guide

This document is written for recruiters, hiring managers, and interviewers who want a quick but concrete understanding of what `Nu` demonstrates.

## One-paragraph summary

`Nu` is a native iOS public-transport app prototype focused on nearby stations, departure boards, journey detail, map-based exploration, favorites, walking ETA support, and live vehicle-tracking-oriented flows. It is valuable as a portfolio project because it combines user-facing product thinking with real API integration, location-aware UX, privacy-aware configuration, caching, error handling, and testable architecture work.

## What the candidate owned

- Product direction and feature scope for a commuter-focused transit app
- Native iOS implementation in SwiftUI
- API integration with Rejseplanen/HAFAS-style transport endpoints
- UI state management with MVVM and dependency injection
- Privacy and release-hardening work such as secret removal, configuration isolation, and audit docs
- Automated tests for core parsing, mapping, and view-model flows

## What to evaluate

### 1. Product judgment

- The app focuses on concrete commuter workflows rather than generic sample-app screens
- Core flows include nearby discovery, departures, journey detail, favorites, and map exploration

### 2. System design

- The codebase uses a pragmatic SwiftUI + MVVM structure
- `Core`, `Networking`, `Services`, `Domain`, `ViewModels`, and `Views` are separated with clear intent
- `AppDependencies` is used to keep long-lived services out of leaf views

### 3. API and data handling

- The app integrates with a real transport data source rather than mocked-only data
- It handles station IDs, journey IDs, location, and transport-specific response mapping
- Runtime credentials are injected externally instead of committed to source

### 4. Quality and risk management

- There are explicit docs for architecture, privacy, release engineering, and security posture
- The repository includes tests and a documented local build/test workflow
- The project acknowledges current gaps instead of presenting itself as fully production-ready

### 5. UX tradeoffs

- The UI is optimized for quick scanning and transit relevance
- The app includes stale-data messaging, error-state handling, and fallback behavior when location or API config is unavailable

## Suggested review path

If you only have 5 to 10 minutes:

1. Read `/README.md`
2. Scan `/Docs/Architecture.md`
3. Open `/Nu/Views/MainTabView.swift`
4. Open `/Nu/Networking/HafasClient.swift`
5. Open `/NuTests/NuCoreTests.swift`

If you have 20 to 30 minutes:

1. Review `/Docs/Privacy.md` and `/Docs/SecurityAudit.md`
2. Review `/Nu/Core/AppConfig.swift` for config isolation
3. Review `/Nu/ViewModels/DepartureBoardViewModel.swift` for app-state orchestration

## What this project is not

- It is not presented as a launched commercial product
- It is not presented as a fully productionized team codebase
- It should be read as a realistic engineering portfolio artifact with meaningful product, API, and app-architecture concerns

## Interview prompts this repo can support

- How would you evolve the current MVVM boundaries into feature modules?
- What would you change before a real App Store launch?
- How should API-key handling differ between local development, CI, and release pipelines?
- Which parts of the app are pure logic versus UI orchestration?
- How would you measure accessibility and performance readiness for this app?

## Honest limitations

- Live data depends on an external API key
- Build and test instructions assume a local Xcode/iOS simulator environment
- Some architecture cleanup is still documented as ongoing work rather than finished work

