# Security and ATS Audit

## Date
- 2026-02-13

## Entitlements
- Custom entitlements file: **None found** (`rg --files -g '*.entitlements'` returned no matches).
- Capability risk: low (no additional entitlement surface checked into project).

## ATS (App Transport Security)
- No `NSAppTransportSecurity` exceptions are configured in build settings.
- API endpoint configured in app code: `https://www.rejseplanen.dk/api`.
- Compliance posture: HTTPS-only, no ATS override required.

## API Key Handling
- Source default key removed from code.
- Runtime key is injected via:
  - `REJSEPLANEN_ACCESS_ID` environment variable, or
  - `REJSEPLANEN_ACCESS_ID` build setting -> Info.plist key.

## Logging
- Network diagnostics are routed through `AppLogger.debug` and compiled out in Release.
- Sensitive request payload URLs are no longer emitted in Release builds.

## Residual Risks
- Debug builds can still emit request details if debug flags are enabled intentionally.
- Third-party API ToS/commercial constraints must be maintained outside source code controls.
