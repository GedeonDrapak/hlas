APP = .xcbuild/Build/Products/Release/Hlas.app
WHISPER_DIR ?= ../whisper.cpp
DEPLOYMENT_TARGET ?= 15.0

.PHONY: vendor app install release clean

vendor:
	mkdir -p Vendor/lib
	cmake -S $(WHISPER_DIR) -B $(WHISPER_DIR)/build-hlas \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) \
		-DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_EXAMPLES=OFF \
		-DWHISPER_BUILD_TESTS=OFF -DGGML_METAL_EMBED_LIBRARY=ON
	cmake --build $(WHISPER_DIR)/build-hlas -j
	find $(WHISPER_DIR)/build-hlas -name "*.a" -exec cp {} Vendor/lib/ \;
	cp $(WHISPER_DIR)/include/whisper.h $(WHISPER_DIR)/ggml/include/*.h Sources/CWhisper/include/

# Xcode-managed build: Apple Development signing (team 74N9VPV9D6) gives a
# stable identity, so Accessibility/Microphone grants survive rebuilds.
app:
	xcodegen generate
	xcodebuild -project Hlas.xcodeproj -scheme Hlas -configuration Release \
		-derivedDataPath .xcbuild -allowProvisioningUpdates build | grep -E "error|SUCCEEDED|FAILED"

install: app
	pkill -x Hlas || true
	@i=0; while pgrep -x Hlas >/dev/null && [ $$i -lt 30 ]; do sleep 0.1; i=$$((i + 1)); done
	rm -rf /Applications/Hlas.app
	cp -R $(APP) /Applications/
	open -n /Applications/Hlas.app
	@echo "Installed + launched /Applications/Hlas.app"

# Builds a signed, notarized Apple Silicon DMG. Set NOTARY_PROFILE once with
# `xcrun notarytool store-credentials` before using this target.
release:
	tools/release.sh

clean:
	rm -rf .xcbuild Hlas.xcodeproj .build Hlas.app
