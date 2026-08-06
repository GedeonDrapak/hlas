APP = .xcbuild/Build/Products/Release/Hlas.app

.PHONY: app install clean

# Xcode-managed build: Apple Development signing (team 74N9VPV9D6) gives a
# stable identity, so Accessibility/Microphone grants survive rebuilds.
app:
	xcodegen generate
	xcodebuild -project Hlas.xcodeproj -scheme Hlas -configuration Release \
		-derivedDataPath .xcbuild -allowProvisioningUpdates build | grep -E "error|SUCCEEDED|FAILED"

install: app
	pkill -x Hlas || true
	rm -rf /Applications/Hlas.app
	cp -R $(APP) /Applications/
	open /Applications/Hlas.app
	@echo "Installed + launched /Applications/Hlas.app"

clean:
	rm -rf .xcbuild Hlas.xcodeproj .build Hlas.app
