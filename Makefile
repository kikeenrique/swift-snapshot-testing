# Optional result bundle: `make test-macos RESULT_BUNDLE=TestResults.xcresult`. Snapshot
# reference/failure/difference images are attached to the bundle, and only xcodebuild emits them —
# `swift test` reports a bare "does not match". CI uploads the bundle when a run goes red.
RESULT_BUNDLE_FLAG = $(if $(RESULT_BUNDLE),-resultBundlePath $(RESULT_BUNDLE))

test-linux:
	docker run \
		--rm \
		-v "$(PWD):$(PWD)" \
		-w "$(PWD)" \
		swift:5.7-focal \
		bash -c 'swift test'

test-macos:
	set -o pipefail && \
	xcodebuild test \
		-scheme swift-snapshot-testing-Package \
		-destination platform="macOS" \
		$(RESULT_BUNDLE_FLAG)

test-ios:
	set -o pipefail && \
	xcodebuild test \
		-scheme SnapshotTesting \
		-destination platform="iOS Simulator,name=iPhone 11 Pro Max,OS=13.3"

test-app:
	set -o pipefail && \
	xcodebuild test \
		-project TestsApp/HostApp.xcodeproj \
		-scheme HostApp \
		-destination platform="iOS Simulator,name=iPhone 17 Pro"

test-swift:
	swift test

test-tvos:
	set -o pipefail && \
	xcodebuild test \
		-scheme SnapshotTesting \
		-destination platform="tvOS Simulator,name=Apple TV 4K,OS=13.3"

test-visionos:
	set -o pipefail && \
	xcodebuild test \
		-scheme swift-snapshot-testing-Package \
		-destination platform="visionOS Simulator,name=Apple Vision Pro (at 2732x2048),OS=2.5" \
		$(RESULT_BUNDLE_FLAG)

format:
	swift format \
		--ignore-unparsable-files \
		--in-place \
		--recursive \
		./Package.swift ./Sources ./Tests ./TestsApp

test-all: test-linux test-macos test-ios test-visionos
