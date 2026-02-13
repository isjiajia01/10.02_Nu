PROJECT=Nu.xcodeproj
SCHEME=Nu
BUILD_DEST=generic/platform=iOS Simulator
TEST_DEST=platform=iOS Simulator,name=iPhone 17

.PHONY: build test lint format ci

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(BUILD_DEST)' build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(TEST_DEST)' test

lint:
	swiftlint lint

format:
	swiftformat Nu

ci: build test lint
