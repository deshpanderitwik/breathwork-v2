APP_NAME = Breathe
BUILD_DIR = build
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BIN = $(BUNDLE)/Contents/MacOS/$(APP_NAME)

.PHONY: build run clean sync-core

sync-core:
	@../../scripts/sync-core.sh

build: sync-core
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp Info.plist $(BUNDLE)/Contents/
	swift build -c release
	@cp .build/release/Breathe $(BIN)
	@# Copy SPM-generated resource bundles (e.g. BreathRuntime_BreathRuntime.bundle
	@# which holds core.iife.js) into Contents/Resources so Bundle.module resolves
	@# at runtime.
	@for b in .build/release/*.bundle; do \
		[ -e "$$b" ] && cp -R "$$b" $(BUNDLE)/Contents/Resources/; \
	done

run: build
	@open $(BUNDLE)

clean:
	@rm -rf $(BUILD_DIR) .build
