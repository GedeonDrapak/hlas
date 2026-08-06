APP = Hlas.app
BIN = .build/release/Hlas

.PHONY: app debug clean run

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/
	cp $(BIN) $(APP)/Contents/MacOS/Hlas
	codesign --force --deep --sign - $(APP)
	@echo "Built $(APP)"

run: app
	open $(APP)

clean:
	swift package clean
	rm -rf $(APP)
