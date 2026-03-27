#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Nu.xcodeproj"
SCHEME="Nu"
DEFAULT_SIMULATOR_ID="745AB4F1-065A-4353-A78F-960A78AFF179"
SIMULATOR_ID="${SIMULATOR_ID:-$DEFAULT_SIMULATOR_ID}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/NuMapDebugScript}"
APP_BUNDLE_ID="Jiajia.Nu"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/Nu.app"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/.debug-artifacts/map}"
PREFERENCES_PLIST=""
ACCESS_ID_KEY="nu.rejseplanen.accessID"
BASE_URL_KEY="nu.rejseplanen.baseURL"
VERSION_KEY="nu.rejseplanen.apiVersion"
BEARER_KEY="nu.rejseplanen.authBearer"
NEARBY_CACHE_KEY="nearby_stations_cache_v1"

usage() {
  cat <<'EOF'
Usage:
  scripts/map-debug.sh build
  scripts/map-debug.sh install
  scripts/map-debug.sh capture-live-id
  scripts/map-debug.sh screenshot-live-map
  scripts/map-debug.sh screenshot-live-detail
  scripts/map-debug.sh screenshot-state <empty|failure|denied>
  scripts/map-debug.sh print-live-id

Optional env:
  SIMULATOR_ID=<udid>
  DERIVED_DATA_PATH=/tmp/NuMapDebugScript
  OUTPUT_DIR=.debug-artifacts/map
EOF
}

ensure_output_dir() {
  mkdir -p "$OUTPUT_DIR"
}

ensure_booted() {
  xcrun simctl boot "$SIMULATOR_ID" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild -quiet build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1
}

install_app() {
  local access_id="${REJSEPLANEN_ACCESS_ID:-}"
  local base_url="${REJSEPLANEN_BASE_URL:-}"
  local api_version="${REJSEPLANEN_API_VERSION:-}"
  local bearer="${REJSEPLANEN_AUTH_BEARER:-}"

  if [[ -z "$access_id" ]]; then
    access_id="$(xcrun simctl spawn "$SIMULATOR_ID" defaults read "$APP_BUNDLE_ID" "$ACCESS_ID_KEY" 2>/dev/null || true)"
  fi
  if [[ -z "$base_url" ]]; then
    base_url="$(xcrun simctl spawn "$SIMULATOR_ID" defaults read "$APP_BUNDLE_ID" "$BASE_URL_KEY" 2>/dev/null || true)"
  fi
  if [[ -z "$api_version" ]]; then
    api_version="$(xcrun simctl spawn "$SIMULATOR_ID" defaults read "$APP_BUNDLE_ID" "$VERSION_KEY" 2>/dev/null || true)"
  fi
  if [[ -z "$bearer" ]]; then
    bearer="$(xcrun simctl spawn "$SIMULATOR_ID" defaults read "$APP_BUNDLE_ID" "$BEARER_KEY" 2>/dev/null || true)"
  fi

  ensure_booted
  xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

  if [[ -n "$access_id" ]]; then
    xcrun simctl spawn "$SIMULATOR_ID" defaults write "$APP_BUNDLE_ID" "$ACCESS_ID_KEY" "$access_id"
  fi
  if [[ -n "$base_url" ]]; then
    xcrun simctl spawn "$SIMULATOR_ID" defaults write "$APP_BUNDLE_ID" "$BASE_URL_KEY" "$base_url"
  fi
  if [[ -n "$api_version" ]]; then
    xcrun simctl spawn "$SIMULATOR_ID" defaults write "$APP_BUNDLE_ID" "$VERSION_KEY" "$api_version"
  fi
  if [[ -n "$bearer" ]]; then
    xcrun simctl spawn "$SIMULATOR_ID" defaults write "$APP_BUNDLE_ID" "$BEARER_KEY" "$bearer"
  fi
}

terminate_app() {
  xcrun simctl terminate "$SIMULATOR_ID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
}

launch_app() {
  ensure_booted
  terminate_app
  xcrun simctl launch "$SIMULATOR_ID" "$APP_BUNDLE_ID" "$@" >/dev/null
}

set_copenhagen_location() {
  xcrun simctl location "$SIMULATOR_ID" set 55.676098,12.568337
}

write_screenshot() {
  local output_name="$1"
  ensure_output_dir
  xcrun simctl io "$SIMULATOR_ID" screenshot "$OUTPUT_DIR/$output_name" >/dev/null
  printf '%s\n' "$OUTPUT_DIR/$output_name"
}

refresh_preferences_path() {
  local data_container
  data_container="$(xcrun simctl get_app_container "$SIMULATOR_ID" "$APP_BUNDLE_ID" data)"
  PREFERENCES_PLIST="$data_container/Library/Preferences/$APP_BUNDLE_ID.plist"
}

read_pref() {
  local key="$1"
  refresh_preferences_path
  defaults read "$PREFERENCES_PLIST" "$key"
}

wait_for_pref() {
  local key="$1"
  local attempts="${2:-15}"
  local delay_seconds="${3:-1}"
  local value=""

  for ((i = 0; i < attempts; i++)); do
    if value="$(read_pref "$key" 2>/dev/null)"; then
      printf '%s\n' "$value"
      return 0
    fi
    sleep "$delay_seconds"
  done

  echo "Timed out waiting for preference: $key" >&2
  return 1
}

capture_live_id() {
  set_copenhagen_location
  launch_app --open-map-tab --map-debug-capture-live-stations
  sleep 1
  xcrun simctl openurl "$SIMULATOR_ID" "nu-debug://map"
  wait_for_first_station_id 20 1
}

print_live_id() {
  local station_id station_name
  station_id="$(read_first_station_field_from_cache id)"
  station_name="$(read_first_station_field_from_cache name)"
  printf 'name=%s\nid=%s\n' "$station_name" "$station_id"
}

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

read_first_station_field_from_cache() {
  local field="$1"
  refresh_preferences_path
  python3 - "$PREFERENCES_PLIST" "$NEARBY_CACHE_KEY" "$field" <<'PY'
import json
import plistlib
import sys

plist_path, cache_key, field = sys.argv[1:4]

with open(plist_path, "rb") as fh:
    plist = plistlib.load(fh)

payload = plist.get(cache_key)
if not payload:
    raise SystemExit(1)

stations = json.loads(payload.decode("utf-8"))
if not stations:
    raise SystemExit(1)

value = stations[0].get(field)
if value is None:
    raise SystemExit(1)

print(value)
PY
}

wait_for_first_station_id() {
  local attempts="${1:-20}"
  local delay_seconds="${2:-1}"
  local value=""

  for ((i = 0; i < attempts; i++)); do
    if value="$(read_first_station_field_from_cache id 2>/dev/null)"; then
      printf '%s\n' "$value"
      return 0
    fi
    sleep "$delay_seconds"
  done

  echo "Timed out waiting for first live station in nearby cache" >&2
  return 1
}

screenshot_live_map() {
  set_copenhagen_location
  launch_app --open-map-tab
  sleep 1
  xcrun simctl openurl "$SIMULATOR_ID" "nu-debug://map"
  sleep 3
  write_screenshot "live-map.png"
}

screenshot_live_detail() {
  local live_id encoded
  live_id="$(capture_live_id)"
  encoded="$(urlencode "$live_id")"
  xcrun simctl openurl "$SIMULATOR_ID" "nu-debug://map?stationId=$encoded"
  sleep 2
  write_screenshot "live-station-detail.png"
}

screenshot_state() {
  local state="$1"
  case "$state" in
    empty|failure|denied) ;;
    *)
      echo "Unsupported state: $state" >&2
      exit 1
      ;;
  esac

  launch_app --open-map-tab --map-debug-state "$state"
  sleep 1
  write_screenshot "state-$state.png"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    build)
      build_app
      ;;
    install)
      build_app
      install_app
      ;;
    capture-live-id)
      build_app
      install_app
      capture_live_id
      ;;
    print-live-id)
      print_live_id
      ;;
    screenshot-live-map)
      build_app
      install_app
      screenshot_live_map
      ;;
    screenshot-live-detail)
      build_app
      install_app
      screenshot_live_detail
      ;;
    screenshot-state)
      if [[ $# -lt 2 ]]; then
        echo "Missing state name" >&2
        usage
        exit 1
      fi
      build_app
      install_app
      screenshot_state "$2"
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
