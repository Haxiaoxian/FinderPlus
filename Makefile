# FinderPlus build entry points. Phase 1 targets Apple Silicon (arm64); `make universal` adds Intel.

PROJECT   := FinderPlus.xcodeproj
SCHEME    := FinderPlus
BUILD_DIR := build
PACKAGE   := Packages/FinderPlusKit

.PHONY: help bootstrap generate build release universal test open run clean dist

help:
	@echo "make bootstrap   Install XcodeGen (Homebrew) and create Config/Local.xcconfig"
	@echo "make generate    Generate $(PROJECT) from project.yml"
	@echo "make build       Debug build for Apple Silicon (arm64)"
	@echo "make release     Release build for Apple Silicon (arm64)"
	@echo "make universal   Release build for Apple Silicon + Intel (arm64 x86_64)  [phase 2]"
	@echo "make test        Run FinderPlusKit unit tests"
	@echo "make run         Build (debug) and launch FinderPlus"
	@echo "make dist        Zip the release app into dist/"

bootstrap:
	./scripts/bootstrap.sh

generate:
	xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=macOS,arch=arm64' -derivedDataPath $(BUILD_DIR) build

release: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' ARCHS=arm64 -derivedDataPath $(BUILD_DIR) build

universal: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -derivedDataPath $(BUILD_DIR) build
	lipo -archs "$(BUILD_DIR)/Build/Products/Release/FinderPlus.app/Contents/MacOS/FinderPlus"

test:
	swift test --package-path $(PACKAGE)

run: build
	open "$(BUILD_DIR)/Build/Products/Debug/FinderPlus.app"

dist:
	./scripts/package.sh

open: generate
	open $(PROJECT)

clean:
	rm -rf $(BUILD_DIR) dist $(PROJECT) $(PACKAGE)/.build
