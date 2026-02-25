# Default recipe
default: build

# Build the app (Debug)
build:
    xcodebuild -project KuKa.xcodeproj -scheme KuKa -configuration Debug build

# Build for release
release:
    xcodebuild -project KuKa.xcodeproj -scheme KuKa -configuration Release build

# Run all tests
test:
    xcodebuild -project KuKa.xcodeproj -scheme KuKa test

# Run unit tests only
test-unit:
    xcodebuild -project KuKa.xcodeproj -scheme KuKa -only-testing:KuKaTests test

# Run UI tests only
test-ui:
    xcodebuild -project KuKa.xcodeproj -scheme KuKa -only-testing:KuKaUITests test

# Clean build artifacts
clean:
    xcodebuild -project KuKa.xcodeproj -scheme KuKa clean

# Clean and rebuild
rebuild: clean build

# Package the app as a zip for distribution
package: clean release
    #!/bin/bash
    APP_PATH=$(xcodebuild -project KuKa.xcodeproj -scheme KuKa -configuration Release -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
    cd "$APP_PATH" && zip -r -y "{{justfile_directory()}}/KuKa.zip" KuKa.app
    echo "Packaged: KuKa.zip"
