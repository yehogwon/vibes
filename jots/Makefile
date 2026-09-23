# Dev tasks for the Jots app. Everything builds with SwiftPM and the Command Line Tools, so Xcode
# isn't needed. CI runs these same targets, so a green `make lint test` locally means a green PR.
#
#   make format   rewrite Swift sources in place with the pinned swift-format
#   make lint     fail on any formatting drift or lint warning
#   make build    build a debug Jots.app into build/debug
#   make test     run the tests
#   make run      build a debug copy and open it (it appears in the menu bar)
#   make install  build a release copy into /Applications and open it
#
# Pass CONFIG=release to build or run the optimized app.

SHELL := /bin/bash

CONFIG ?= debug
# SwiftPM's .build/<config> links to the host architecture's products.
BIN := .build/$(CONFIG)/Jots
APP := build/$(CONFIG)/Jots.app
CONTENTS := $(APP)/Contents
SIGNED := build/$(CONFIG)/.signed
ICON := build/AppIcon.icns
INSTALL_DIR := /Applications

# Ad hoc signing keeps the scratchpad on this Mac and needs no Apple Developer account.
# Config/Signing.local.mk (git ignores it) switches to a real identity and turns on iCloud sync;
# see Config/Signing.local.mk.example.
SIGN_IDENTITY := -
ENTITLEMENTS := Resources/Jots.entitlements
PROVISIONING_PROFILE :=
-include Config/Signing.local.mk
ifneq ($(PROVISIONING_PROFILE),)
ENTITLEMENTS := build/Jots-iCloud.entitlements
EMBEDDED_PROFILE := $(CONTENTS)/embedded.provisionprofile
endif

# swift-format is pinned in Tools/Package.swift and built from source once (cached in Tools/.build).
TOOLS_PACKAGE := Tools
SWIFT_FORMAT := $(TOOLS_PACKAGE)/.build/release/swift-format
SWIFT_FORMAT_CONFIG := .swift-format
# Recursing skips hidden directories, so SwiftPM's .build folders are never formatted.
SOURCE_PATHS := Sources Tests Package.swift $(TOOLS_PACKAGE)/Package.swift $(TOOLS_PACKAGE)/MakeIcon.swift

.PHONY: tools format lint build test run install clean FORCE

tools: $(SWIFT_FORMAT)

$(SWIFT_FORMAT): $(TOOLS_PACKAGE)/Package.swift $(TOOLS_PACKAGE)/Package.resolved
	swift build -c release --package-path $(TOOLS_PACKAGE) --product swift-format
	touch $@

format: $(SWIFT_FORMAT)
	"$(SWIFT_FORMAT)" format --configuration $(SWIFT_FORMAT_CONFIG) --in-place --recursive --parallel $(SOURCE_PATHS)

lint: $(SWIFT_FORMAT)
	"$(SWIFT_FORMAT)" lint --configuration $(SWIFT_FORMAT_CONFIG) --strict --recursive --parallel $(SOURCE_PATHS)

build: $(SIGNED)

# SwiftPM decides what to recompile, and leaves the binary untouched when nothing changed, so the
# bundle steps below only rerun when something did.
$(BIN): FORCE
	swift build -c $(CONFIG) --product Jots

$(CONTENTS)/MacOS/Jots: $(BIN)
	@mkdir -p $(@D)
	cp $< $@

$(CONTENTS)/Info.plist: Resources/Info.plist
	@mkdir -p $(@D)
	cp $< $@
	printf 'APPL????' > $(CONTENTS)/PkgInfo

$(CONTENTS)/Resources/AppIcon.icns: $(ICON)
	@mkdir -p $(@D)
	cp $< $@

$(ICON): $(TOOLS_PACKAGE)/MakeIcon.swift
	swift $< build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o $@

$(EMBEDDED_PROFILE): $(PROVISIONING_PROFILE)
	@mkdir -p $(@D)
	cp $< $@

# Xcode adds the app and team identifiers to the entitlements when it signs for iCloud; do the same.
build/Jots-iCloud.entitlements: Resources/Jots-iCloud.entitlements Config/Signing.local.mk
	@mkdir -p $(@D)
	cp $< $@
	plutil -insert com.apple.application-identifier -string "$(TEAM_ID).io.github.yehogwon.Jots" $@
	plutil -insert com.apple.developer.team-identifier -string "$(TEAM_ID)" $@

$(SIGNED): $(CONTENTS)/MacOS/Jots $(CONTENTS)/Info.plist $(CONTENTS)/Resources/AppIcon.icns \
		$(EMBEDDED_PROFILE) $(ENTITLEMENTS)
	codesign --force --sign "$(SIGN_IDENTITY)" --entitlements $(ENTITLEMENTS) --options runtime $(APP)
	touch $@

test:
	swift test

run: build
	-pkill -x Jots
	open $(APP)

install:
	$(MAKE) build CONFIG=release
	-pkill -x Jots
	rm -rf $(INSTALL_DIR)/Jots.app
	ditto build/release/Jots.app $(INSTALL_DIR)/Jots.app
	open $(INSTALL_DIR)/Jots.app

clean:
	rm -rf build .build
