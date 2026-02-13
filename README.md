# Nu iOS

## Prerequisites
- Xcode 16+
- iOS Simulator runtime
- Rejseplanen API key via env/build setting:
  - `REJSEPLANEN_ACCESS_ID`

## Local / CI Commands

```bash
# 1) Build
xcodebuild -project Nu.xcodeproj -scheme Nu -destination 'generic/platform=iOS Simulator' build

# 2) Test
xcodebuild -project Nu.xcodeproj -scheme Nu -destination 'platform=iOS Simulator,name=iPhone 17' test

# 3) Lint (if installed)
swiftlint lint

# 4) Format (if installed)
swiftformat Nu
```

## Injecting API Key
- Xcode Scheme (Run/Test) Environment Variables:
  - `REJSEPLANEN_ACCESS_ID=<your key>`
- or target build setting:
  - `REJSEPLANEN_ACCESS_ID`

No production API key is committed in source code.
