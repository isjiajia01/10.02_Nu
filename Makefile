PROJECT=Nu.xcodeproj
SCHEME=Nu
BUILD_DEST=generic/platform=iOS Simulator
TEST_DEST=platform=iOS Simulator,name=iPhone 17

.PHONY: build test lint format ci
.PHONY: map-build map-install map-live-id map-print-live-id map-live-map map-live-detail map-empty map-failure map-denied

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(BUILD_DEST)' build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(TEST_DEST)' test

lint:
	swiftlint lint

format:
	swiftformat Nu

ci: build test lint

map-build:
	./scripts/map-debug.sh build

map-install:
	./scripts/map-debug.sh install

map-live-id:
	./scripts/map-debug.sh capture-live-id

map-print-live-id:
	./scripts/map-debug.sh print-live-id

map-live-map:
	./scripts/map-debug.sh screenshot-live-map

map-live-detail:
	./scripts/map-debug.sh screenshot-live-detail

map-empty:
	./scripts/map-debug.sh screenshot-state empty

map-failure:
	./scripts/map-debug.sh screenshot-state failure

map-denied:
	./scripts/map-debug.sh screenshot-state denied
