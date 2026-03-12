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
    codesign --force --deep --sign "KuKa Signing" "$APP_PATH/KuKa.app"
    cd "$APP_PATH" && zip -r -y "{{justfile_directory()}}/KuKa.zip" KuKa.app
    echo "Packaged: KuKa.zip"

# Build, package, and publish a GitHub release (usage: just publish v1.0.0)
publish version: package
    git tag {{version}}
    git push origin {{version}}
    gh release create {{version}} KuKa.zip --title "Ku-Ka {{version}}" --generate-notes

# Build release and install to /Applications (replaces existing)
install: package
    #!/bin/bash
    osascript -e 'tell application "KuKa" to quit' 2>/dev/null || true
    rm -rf /Applications/KuKa.app
    unzip -o KuKa.zip -d /Applications
    echo "Installed to /Applications/KuKa.app"
    open /Applications/KuKa.app
