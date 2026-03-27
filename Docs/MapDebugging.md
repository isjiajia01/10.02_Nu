# Map Debugging

This project includes fixed debug entry points for the rebuilt minimal map flow. Use them when you need repeatable simulator validation without manually tapping through the app.

## Prerequisites

- Xcode with an installed iOS Simulator runtime
- A bootable simulator device
- A valid `REJSEPLANEN_ACCESS_ID` if you want live map data

Default simulator used by the script:

- `745AB4F1-065A-4353-A78F-960A78AFF179` (`iPhone 17 Pro`)

You can override it:

```bash
SIMULATOR_ID=<your-udid> scripts/map-debug.sh screenshot-live-map
```

## Main Script

Use:

```bash
scripts/map-debug.sh --help
```

Supported commands:

- `scripts/map-debug.sh build`
- `scripts/map-debug.sh install`
- `scripts/map-debug.sh capture-live-id`
- `scripts/map-debug.sh print-live-id`
- `scripts/map-debug.sh screenshot-live-map`
- `scripts/map-debug.sh screenshot-live-detail`
- `scripts/map-debug.sh screenshot-state empty`
- `scripts/map-debug.sh screenshot-state failure`
- `scripts/map-debug.sh screenshot-state denied`

Artifacts are written to:

```text
.debug-artifacts/map/
```

## Recommended Flows

### 1. Capture a live station ID

Launches the live map, pins the simulator location to central Copenhagen, and persists the first returned station ID into simulator app preferences.

```bash
make map-live-id
```

Then print the captured value:

```bash
make map-print-live-id
```

### 2. Verify `openurl -> station detail`

This is the full end-to-end check for the live deep link flow.

```bash
make map-live-detail
```

Output screenshot:

- `.debug-artifacts/map/live-station-detail.png`

### 3. Verify debug states

```bash
make map-empty
make map-failure
make map-denied
```

Output screenshots:

- `.debug-artifacts/map/state-empty.png`
- `.debug-artifacts/map/state-failure.png`
- `.debug-artifacts/map/state-denied.png`

## Debug Entry Points Wired Into the App

### Launch arguments

- `--open-map-tab`
- `--map-debug-state <empty|failure|denied>`
- `--map-debug-station-id <station-id>`
- `--map-debug-capture-live-stations`
- `--use-mock-api`

### URL scheme

Scheme:

- `nu-debug`

Examples:

```bash
xcrun simctl openurl "$SIMULATOR_ID" 'nu-debug://map?stationId=<encoded-station-id>'
xcrun simctl openurl "$SIMULATOR_ID" 'nu-debug://map/station/<station-id>'
```

## Where Captured Live IDs Are Stored

The live capture helper writes these keys into app preferences:

- `nu.debug.map.firstStationID`
- `nu.debug.map.firstStationName`
- `nu.debug.map.stationIDs`
- `nu.debug.map.stationNames`

The helper script reads them from the simulator app container automatically, so you do not need to inspect the plist manually during normal use.
