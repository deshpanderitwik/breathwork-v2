APP_NAME = Breathe
BUILD_DIR = build
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BIN = $(BUNDLE)/Contents/MacOS/$(APP_NAME)

.PHONY: build run clean

build:
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@cp Info.plist $(BUNDLE)/Contents/
	swift build -c release
	@cp .build/release/Breathe $(BIN)

run: build
	@open $(BUNDLE)

clean:
	@rm -rf $(BUILD_DIR) .build
