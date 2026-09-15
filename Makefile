TRANSCRIBE_CPP ?= $(abspath ../../1agents_app/reference_repo/transcribe.cpp)
XCFRAMEWORK := $(CURDIR)/Vendor/TranscribeCpp.xcframework
APP := $(CURDIR)/VoiceInputMac.app
SWIFT_FLAGS := --configuration release
export TRANSCRIBE_CPP

.PHONY: all native vendor app test run install clean

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

clean:
	rm -rf .build tmp Vendor VoiceInputMac.app
	rm -f vendor/transcribe.cpp
