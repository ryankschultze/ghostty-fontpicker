PREFIX ?= $(HOME)/.local
BINARY := .build/release/fontpicker

# The Command Line Tools ship the Swift Testing macro plugin but SwiftPM doesn't look in
# its folder, so `swift test` alone fails with "plugin for module 'TestingMacros' not
# found". Point the compiler at it when it's there; with Xcode installed this is a no-op.
TESTING_PLUGINS := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
TEST_FLAGS := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: build test run app dist install uninstall seed clean

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

run: build
	$(BINARY)

# A double-clickable build/FontPicker.app around the same executable.
app: build
	scripts/bundle.sh $(BINARY)

# What install.sh downloads on a Mac that can't build: one binary for both architectures,
# to attach to a GitHub release under this name.
dist:
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p build
	COPYFILE_DISABLE=1 tar -czf build/fontpicker-macos.tar.gz \
		-C "$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)" fontpicker
	@echo "Built build/fontpicker-macos.tar.gz"

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BINARY) $(PREFIX)/bin/fontpicker
	@echo "Installed $(PREFIX)/bin/fontpicker"

uninstall:
	rm -f $(PREFIX)/bin/fontpicker

# Regenerate the curated names and notes from the specimen page.
seed:
	node scripts/gen-seed.mjs

clean:
	swift package clean
	rm -rf build
