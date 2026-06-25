# StatusGlance — Makefile
#
# Assembles a proper macOS .app bundle around the SPM executable.
# Info.plist is generated inline (heredoc) so there is never a stale
# checked-in plist to drift out of sync.

# ---- Configuration -----------------------------------------------------------

APP_NAME      := StatusGlance
BUNDLE_ID     := com.nateritter.statusglance
VERSION       := 1.0.0
MIN_OS        := 14.0

BIN_NAME      := StatusGlance
RELEASE_BIN   := .build/release/$(BIN_NAME)
APP_BUNDLE    := $(APP_NAME).app
CONTENTS      := $(APP_BUNDLE)/Contents
MACOS_DIR     := $(CONTENTS)/MacOS
RESOURCES_DIR := $(CONTENTS)/Resources
INSTALL_DIR   := /Applications

# Bundle icon (generated in code — see scripts/make-icon.swift). `AppIcon` is the
# CFBundleIconFile name macOS looks up inside Contents/Resources.
ICON_SRC      := Resources/AppIcon.icns
ICON_SCRIPT   := scripts/make-icon.swift

# ---- Phony targets -----------------------------------------------------------

.PHONY: all build app run clean install update install-updater uninstall-updater icon help
.DEFAULT_GOAL := help

# ---- Self-update (build-from-source) -----------------------------------------

UPDATE_LABEL := com.nateritter.statusglance.update
UPDATE_PLIST := $(HOME)/Library/LaunchAgents/$(UPDATE_LABEL).plist
UPDATE_LOG   := $(HOME)/Library/Logs/StatusGlance-update.log
UPDATE_SCRIPT := $(CURDIR)/scripts/self-update.sh

all: app

## build: compile the release binary via SPM
build:
	swift build -c release

## run: build and run for development (swift run)
run:
	swift run

## app: assemble StatusGlance.app around the release binary
app: build
	@echo "Assembling $(APP_BUNDLE)..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(MACOS_DIR)"
	@mkdir -p "$(RESOURCES_DIR)"
	@cp "$(RELEASE_BIN)" "$(MACOS_DIR)/$(APP_NAME)"
	@chmod +x "$(MACOS_DIR)/$(APP_NAME)"
	@if [ ! -f "$(ICON_SRC)" ]; then echo "Generating app icon..."; swift "$(ICON_SCRIPT)"; fi
	@cp "$(ICON_SRC)" "$(RESOURCES_DIR)/AppIcon.icns"
	@printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
'<plist version="1.0">' \
'<dict>' \
'	<key>CFBundleName</key>' \
'	<string>$(APP_NAME)</string>' \
'	<key>CFBundleDisplayName</key>' \
'	<string>$(APP_NAME)</string>' \
'	<key>CFBundleExecutable</key>' \
'	<string>$(APP_NAME)</string>' \
'	<key>CFBundleIdentifier</key>' \
'	<string>$(BUNDLE_ID)</string>' \
'	<key>CFBundlePackageType</key>' \
'	<string>APPL</string>' \
'	<key>CFBundleShortVersionString</key>' \
'	<string>$(VERSION)</string>' \
'	<key>CFBundleVersion</key>' \
'	<string>$(VERSION)</string>' \
'	<key>CFBundleInfoDictionaryVersion</key>' \
'	<string>6.0</string>' \
'	<key>CFBundleIconFile</key>' \
'	<string>AppIcon</string>' \
'	<key>CFBundleIconName</key>' \
'	<string>AppIcon</string>' \
'	<key>LSUIElement</key>' \
'	<true/>' \
'	<key>LSMinimumSystemVersion</key>' \
'	<string>$(MIN_OS)</string>' \
'	<key>NSHighResolutionCapable</key>' \
'	<true/>' \
'	<key>NSHumanReadableCopyright</key>' \
'	<string>Copyright (c) 2026 Nate Ritter. MIT License.</string>' \
'</dict>' \
'</plist>' \
	> "$(CONTENTS)/Info.plist"
	@echo "Built $(APP_BUNDLE) (version $(VERSION))"

## install: copy the assembled .app into /Applications
install: app
	@echo "Installing $(APP_BUNDLE) to $(INSTALL_DIR)..."
	@rm -rf "$(INSTALL_DIR)/$(APP_BUNDLE)"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(APP_BUNDLE)"

## update: pull origin/main and rebuild+relaunch if there's anything new (no-op otherwise)
update:
	@sh "$(UPDATE_SCRIPT)"

## install-updater: install a LaunchAgent that runs `update` at login and every 6h
install-updater:
	@chmod +x "$(UPDATE_SCRIPT)"
	@mkdir -p "$(HOME)/Library/LaunchAgents" "$(HOME)/Library/Logs"
	@printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
'<plist version="1.0">' \
'<dict>' \
'	<key>Label</key>' \
'	<string>$(UPDATE_LABEL)</string>' \
'	<key>ProgramArguments</key>' \
'	<array>' \
'		<string>/bin/sh</string>' \
'		<string>$(UPDATE_SCRIPT)</string>' \
'	</array>' \
'	<key>RunAtLoad</key>' \
'	<true/>' \
'	<key>StartInterval</key>' \
'	<integer>21600</integer>' \
'	<key>StandardOutPath</key>' \
'	<string>$(UPDATE_LOG)</string>' \
'	<key>StandardErrorPath</key>' \
'	<string>$(UPDATE_LOG)</string>' \
'</dict>' \
'</plist>' \
	> "$(UPDATE_PLIST)"
	@launchctl unload "$(UPDATE_PLIST)" 2>/dev/null || true
	@launchctl load "$(UPDATE_PLIST)"
	@echo "Installed updater LaunchAgent ($(UPDATE_LABEL)); logs at $(UPDATE_LOG)"

## uninstall-updater: remove the auto-update LaunchAgent
uninstall-updater:
	@launchctl unload "$(UPDATE_PLIST)" 2>/dev/null || true
	@rm -f "$(UPDATE_PLIST)"
	@echo "Removed updater LaunchAgent ($(UPDATE_LABEL))"

## icon: (re)generate the bundle icon at Resources/AppIcon.icns (drawn in code)
icon:
	swift "$(ICON_SCRIPT)"

## clean: remove build artifacts and the assembled bundle
clean:
	swift package clean
	@rm -rf .build
	@rm -rf "$(APP_BUNDLE)"
	@echo "Cleaned."

## help: list available targets
help:
	@echo "StatusGlance — make targets:"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
