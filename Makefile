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

test-swift:
	swift test

test-tvos:
	set -o pipefail && \
	xcodebuild test \
		-scheme SnapshotTesting \
		-destination platform="tvOS Simulator,name=Apple TV 4K,OS=13.3"

# The visionOS references are recorded on this device and runtime; a different device type or
# runtime renders differently and overwrites them. visionOS 27 only runs the 4K device type, which
# runner images ship under the default name; create it locally when it is missing. The match is
# exact so a renamed "Apple Vision Pro (…)" device does not count.
VISIONOS_DEVICE = Apple Vision Pro
VISIONOS_RUNTIME = 27.0

visionos-simulator:
	xcrun simctl list devices "visionOS $(VISIONOS_RUNTIME)" \
		| grep -qE "^ +$(VISIONOS_DEVICE) \([0-9A-F-]{36}\)" || \
	xcrun simctl create "$(VISIONOS_DEVICE)" \
		com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro-4K \
		com.apple.CoreSimulator.SimRuntime.xrOS-$(subst .,-,$(VISIONOS_RUNTIME))

test-visionos: visionos-simulator
	set -o pipefail && \
	xcodebuild test \
		-scheme swift-snapshot-testing-Package \
		-destination platform="visionOS Simulator,name=$(VISIONOS_DEVICE),OS=$(VISIONOS_RUNTIME)" \
		$(RESULT_BUNDLE_FLAG)

format:
	swift format \
		--ignore-unparsable-files \
		--in-place \
		--recursive \
		./Package.swift ./Sources ./Tests

test-all: test-linux test-macos test-ios test-visionos
