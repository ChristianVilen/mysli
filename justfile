# List available commands
default:
    @just --list

# Build the app (Debug)
build:
    #!/bin/bash
    set -e
    xcodebuild -project Mysli.xcodeproj -scheme Mysli -configuration Debug build
    APP_PATH=$(xcodebuild -project Mysli.xcodeproj -scheme Mysli -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
    codesign --force --deep --sign - "$APP_PATH/Mysli.app"

# Build for release
release:
    #!/bin/bash
    set -e
    xcodebuild -project Mysli.xcodeproj -scheme Mysli -configuration Release build
    APP_PATH=$(xcodebuild -project Mysli.xcodeproj -scheme Mysli -configuration Release -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
    codesign --force --deep --sign - "$APP_PATH/Mysli.app"

# Run all tests
test:
    xcodebuild -project Mysli.xcodeproj -scheme Mysli test

# Run unit tests only
test-unit:
    xcodebuild -project Mysli.xcodeproj -scheme Mysli -only-testing:MysliTests test

# Clean build artifacts
clean:
    xcodebuild -project Mysli.xcodeproj -scheme Mysli clean

# Clean and rebuild
rebuild: clean build

# Package the app as a zip for distribution
package: clean release
    #!/bin/bash
    APP_PATH=$(xcodebuild -project Mysli.xcodeproj -scheme Mysli -configuration Release -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
    codesign --force --deep --sign - "$APP_PATH/Mysli.app"
    cd "$APP_PATH" && zip -r -y "{{justfile_directory()}}/Mysli.zip" Mysli.app
    echo "Packaged: Mysli.zip"

# Build, package, and publish a GitHub release (usage: just publish v1.0.0)
publish version: package
    git tag {{version}}
    git push origin {{version}}
    gh release create {{version}} Mysli.zip --title "Mysli {{version}}" --generate-notes

# Build release and install to /Applications (replaces existing)
install: package
    #!/bin/bash
    osascript -e 'tell application "Mysli" to quit' 2>/dev/null || true
    rm -rf /Applications/Mysli.app
    unzip -o Mysli.zip -d /Applications
    echo "Installed to /Applications/Mysli.app"
    open /Applications/Mysli.app
