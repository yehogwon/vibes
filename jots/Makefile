# Dev tasks for the Jots app. CI runs these same targets, so a green `make lint test` locally means a green PR.
#
#   make format   rewrite Swift sources in place with the pinned swift-format
#   make lint     fail on any formatting drift or lint warning
#   make build    build the app
#   make test     build the app and run the tests
#   make ui-test  drive the app with the UI tests (needs Automation Mode; not run in CI)

SHELL := /bin/bash

# swift-format is pinned in Tools/Package.swift and built from source once (cached in Tools/.build).
TOOLS_PACKAGE := Tools
SWIFT_FORMAT = $(shell swift build -c release --package-path $(TOOLS_PACKAGE) --show-bin-path)/swift-format
SWIFT_FORMAT_CONFIG := .swift-format
# Recursing skips hidden directories, so SwiftPM's .build folders are never formatted.
SOURCE_PATHS := $(wildcard Jots JotsUITests Packages $(TOOLS_PACKAGE)/Package.swift)

PROJECT := Jots.xcodeproj
SCHEME := Jots
DESTINATION := platform=macOS,arch=$(shell uname -m)
RESULT_BUNDLE := build/TestResults.xcresult
UI_RESULT_BUNDLE := build/UITestResults.xcresult
# Extra xcodebuild settings, e.g. `make test XCODEBUILD_FLAGS='CODE_SIGNING_ALLOWED=NO'`.
XCODEBUILD_FLAGS ?=
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' $(XCODEBUILD_FLAGS)

# Pretty-print through xcbeautify when it's installed; otherwise keep xcodebuild to warnings and errors.
XCBEAUTIFY := $(shell command -v xcbeautify 2>/dev/null)
ifneq ($(XCBEAUTIFY),)
XCODEBUILD_OUTPUT := | $(XCBEAUTIFY)
else
XCODEBUILD := $(XCODEBUILD) -quiet
XCODEBUILD_OUTPUT :=
endif

.PHONY: tools format lint build test ui-test clean

tools:
	swift build -c release --package-path $(TOOLS_PACKAGE) --product swift-format

format: tools
	"$(SWIFT_FORMAT)" format --configuration $(SWIFT_FORMAT_CONFIG) --in-place --recursive --parallel $(SOURCE_PATHS)

lint: tools
	"$(SWIFT_FORMAT)" lint --configuration $(SWIFT_FORMAT_CONFIG) --strict --recursive --parallel $(SOURCE_PATHS)

build:
	set -o pipefail; $(XCODEBUILD) build $(XCODEBUILD_OUTPUT)

test:
	rm -rf $(RESULT_BUNDLE)
	set -o pipefail; $(XCODEBUILD) test -resultBundlePath $(RESULT_BUNDLE) $(XCODEBUILD_OUTPUT)

ui-test:
	rm -rf $(UI_RESULT_BUNDLE)
	set -o pipefail; xcodebuild -project $(PROJECT) -scheme JotsUI -destination '$(DESTINATION)' $(XCODEBUILD_FLAGS) \
		test -resultBundlePath $(UI_RESULT_BUNDLE) $(XCODEBUILD_OUTPUT)

clean:
	rm -rf build
	$(XCODEBUILD) clean
