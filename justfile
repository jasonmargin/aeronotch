set shell := ["bash", "-cu"]

app := "AeroNotch"
install_dir := "/Applications"

# Build the release binary.
build:
    swift build -c release

# Assemble and ad-hoc sign the .app bundle in ./build.
bundle: build
    #!/usr/bin/env bash
    set -euo pipefail
    BIN="$(swift build -c release --show-bin-path)/{{app}}"
    APP_DIR="build/{{app}}.app"
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS"
    cp "$BIN" "$APP_DIR/Contents/MacOS/{{app}}"
    cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
    codesign --force --sign - --timestamp=none "$APP_DIR"
    echo "Bundled $APP_DIR"

# Install to /Applications and launch.
install: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    pkill -x {{app}} 2>/dev/null || true
    rm -rf "{{install_dir}}/{{app}}.app"
    ditto "build/{{app}}.app" "{{install_dir}}/{{app}}.app"
    codesign --force --sign - --timestamp=none "{{install_dir}}/{{app}}.app"
    open "{{install_dir}}/{{app}}.app"
    echo "Installed to {{install_dir}}/{{app}}.app and launched."
    echo "If you haven't yet, wire the AeroSpace hook — see: just hook"

# Run the release binary directly (no bundle, for development).
run: build
    "$(swift build -c release --show-bin-path)/{{app}}"

# Print the exact aerospace.toml hook line.
hook:
    @echo 'Add (or extend) this in ~/.config/aerospace/aerospace.toml:'
    @echo ''
    @echo 'exec-on-workspace-change = ["/bin/bash", "-c", "sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE ; /Applications/{{app}}.app/Contents/MacOS/{{app}} ping-workspace-change"]'
    @echo ''
    @echo 'Then run: aerospace reload-config'

# Remove the installed app.
uninstall:
    #!/usr/bin/env bash
    pkill -x {{app}} 2>/dev/null || true
    rm -rf "{{install_dir}}/{{app}}.app"
    echo "Removed {{install_dir}}/{{app}}.app"

# Build a versioned release zip and print the publish steps.
release version: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    APP_DIR="build/{{app}}.app"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString {{version}}" "$APP_DIR/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion {{version}}" "$APP_DIR/Contents/Info.plist"
    # Ad-hoc sign (no Developer ID cert in keychain). If you later add a
    # "Developer ID Application" identity, replace the next line with:
    #   codesign --force --options runtime --timestamp \
    #     --sign "Developer ID Application: Your Name (TEAMID)" "$APP_DIR"
    # and notarize the zip:
    #   xcrun notarytool submit "$ZIP" --keychain-profile "aeronotch-notary" --wait
    #   xcrun stapler staple "$APP_DIR"   (then re-zip)
    codesign --force --sign - --timestamp=none "$APP_DIR"
    ZIP="build/{{app}}-{{version}}.zip"
    rm -f "$ZIP"
    ditto -ck --keepParent "$APP_DIR" "$ZIP"
    echo
    echo "sha256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
    echo "zip:    $ZIP"
    echo
    echo "Next steps:"
    echo "  git tag v{{version}} && git push origin main v{{version}}"
    echo "  gh release create v{{version}} '$ZIP' --repo jasonmargin/aeronotch --title 'AeroNotch {{version}}' --generate-notes"
    echo "  just bump-cask {{version}}"

# Update ../homebrew-tap/Casks/aeronotch.rb with version + sha256 of the release zip.
bump-cask version:
    #!/usr/bin/env bash
    set -euo pipefail
    ZIP="build/{{app}}-{{version}}.zip"
    [ -f "$ZIP" ] || { echo "Missing $ZIP — run: just release {{version}}"; exit 1; }
    SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    CASK="../homebrew-tap/Casks/aeronotch.rb"
    sed -i '' -e "s/^  version \".*\"/  version \"{{version}}\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
    echo "Updated $CASK → {{version}} / $SHA"
    echo "Commit + push the tap, then: brew upgrade --cask aeronotch"
