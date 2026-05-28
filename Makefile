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

# ---- Phony targets -----------------------------------------------------------

.PHONY: all build app run clean install help
.DEFAULT_GOAL := help

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
