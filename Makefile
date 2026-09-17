TRANSCRIBE_CPP ?= $(abspath ../../1agents_app/reference_repo/transcribe.cpp)
XCFRAMEWORK := $(CURDIR)/Vendor/TranscribeCpp.xcframework
APP := $(CURDIR)/VoiceInputMac.app
SWIFT_FLAGS := --configuration release
export TRANSCRIBE_CPP

DEVELOPER_ID_APPLICATION ?= Developer ID Application: XIAOFENG ZENG (3HJ3R6SXAL)
DMG := $(CURDIR)/dist/VoiceInputMac-$(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist 2>/dev/null || echo 0.0.0).dmg

.PHONY: all native vendor app test run install dmg signed-dmg notarize release-dmg clean

all: app

vendor:
	mkdir -p vendor
	ln -sfn "$(TRANSCRIBE_CPP)" vendor/transcribe.cpp
	ln -sfn "$(TRANSCRIBE_CPP)/bindings/swift" vendor/transcribe-cpp

native: vendor
	./scripts/build_macos_xcframework.sh "$(XCFRAMEWORK)"

$(XCFRAMEWORK):
	$(MAKE) native

app: vendor $(XCFRAMEWORK)
	swift build $(SWIFT_FLAGS) --product VoiceInputMac
	./scripts/bundle_app.sh .build/release/VoiceInputMac "$(APP)"

test: vendor $(XCFRAMEWORK)
	swift test

run: app
	open "$(APP)"

install: app
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/VoiceInputMac.app"
	rsync -a "$(APP)/" "$(HOME)/Applications/VoiceInputMac.app/"
	@echo "installed $(HOME)/Applications/VoiceInputMac.app"

dmg: app
	./scripts/make_dmg.sh "$(APP)" "$(CURDIR)/dist"

signed-dmg:
	CODESIGN_IDENTITY="$(DEVELOPER_ID_APPLICATION)" RELEASE_SIGN=1 $(MAKE) app
	./scripts/make_dmg.sh "$(APP)" "$(CURDIR)/dist"

notarize:
	./scripts/notarize.sh "$(DMG)"

release-dmg: signed-dmg
	./scripts/notarize.sh "$(DMG)"

clean:
	rm -rf .build tmp Vendor VoiceInputMac.app dist
	rm -f vendor/transcribe.cpp
