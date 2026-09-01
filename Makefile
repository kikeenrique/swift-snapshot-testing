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
		-scheme SnapshotTesting \
		-destination platform="macOS" \

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

format:
	swift format \
		--ignore-unparsable-files \
		--in-place \
		--recursive \
		./Package.swift ./Sources ./Tests ./TestsApp

test-all: test-linux test-macos test-ios
