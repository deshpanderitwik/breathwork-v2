SCHEME = Breathe
PROJECT = Breathe.xcodeproj
BUNDLE_ID = com.breathe.ios
DEVICE = E2291A1F-8481-4237-93DE-422683F39644
DERIVED = build
APP = $(DERIVED)/Build/Products/Debug-iphoneos/Breathe.app

.PHONY: project build install launch run clean devices

# Regenerate .xcodeproj from project.yml
project:
	@xcodegen generate

# Compile + sign for the device (no install)
build: project
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS' -configuration Debug \
		-allowProvisioningUpdates -derivedDataPath $(DERIVED) build

# Copy the .app onto the phone
install: build
	@xcrun devicectl device install app --device $(DEVICE) $(APP)

# Open it
launch:
	@xcrun devicectl device process launch --device $(DEVICE) $(BUNDLE_ID)

# Everyday command: rebuild, install, launch
run: install launch

# List paired devices (handy when DEVICE changes after re-pairing)
devices:
	@xcrun devicectl list devices

clean:
	@rm -rf $(DERIVED)
