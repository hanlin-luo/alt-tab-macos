#!/usr/bin/env bash
#
# build_local.sh — build AltTab.app and install it, without Xcode.
#
# The Xcode project (alt-tab-macos.xcodeproj) is the upstream build system and `xcodebuild` is the
# supported way to build AltTab. This script is the Command Line Tools equivalent: it compiles the
# app with SwiftPM (Package.swift), assembles the .app bundle the way the Xcode build phases do
# (resources, Info.plist, embedded frameworks, Sparkle helpers), signs it, and installs it.
#
# It exists because xcodebuild — like ibtool and actool — ships with a full Xcode installation.
# On a machine with only the Command Line Tools, the Xcode project cannot be built at all.
#
# Usage:
#   scripts/build_local.sh                 # build, sign, install to /Applications
#   scripts/build_local.sh --no-install    # build and sign only
#   scripts/build_local.sh debug           # build the Debug configuration
#
# Environment:
#   ALTTAB_CODESIGN_IDENTITY  signing identity (default: Local Self-Signed)
#   ALTTAB_INSTALL_DIR        install location (default: /Applications)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

BUILD="$ROOT/build"
SCRATCH="$BUILD/spm"
CONFIG="release"
STAGE="$BUILD/stage-$CONFIG"
APP="$STAGE/AltTab.app"
CONTENTS="$APP/Contents"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
IDENTITY="${ALTTAB_CODESIGN_IDENTITY:-Local Self-Signed}"
KEYCHAIN="${ALTTAB_KEYCHAIN:-$HOME/Library/Keychains/alttab-signing.keychain-db}"
INSTALL_DIR="${ALTTAB_INSTALL_DIR:-/Applications}"
ENTITLEMENTS="$ROOT/alt_tab_macos.entitlements"
SPARKLE_IDENTIFIER="org.sparkle-project.Sparkle"

install_app=1
for arg in "$@"; do
	case "$arg" in
	--no-install) install_app=0 ;;
	debug | release) CONFIG="$arg" ;;
	*) fail "unknown argument: $arg" ;;
	esac
done
PRODUCTS="$SCRATCH/$CONFIG"

step() { printf '\n==> %s\n' "$1"; }
fail() { printf 'error: %s\n' "$1" >&2; exit 1; }

SDK="$(xcrun --show-sdk-path)"
export ALTTAB_PRIVATE_FRAMEWORKS="$SDK/System/Library/PrivateFrameworks"

# The signing identity lives in its own keychain (see scripts/codesign/setup_local.sh). codesign
# needs it named explicitly: without --keychain it would look in the login keychain first, where a
# stale copy of the same identity can sit behind an ACL that makes the operation block on a prompt.
#
# The keychain auto-locks (set-keychain-settings -t 3600), and a locked keychain makes every
# private-key operation wait on an unlock prompt that never gets answered. Unlock it first, from the
# password the setup script stored next to the certificate.
codesign_args=(--keychain "$KEYCHAIN" --timestamp=none)
[ -e "$KEYCHAIN" ] || fail "signing keychain $KEYCHAIN not found — run scripts/codesign/setup_local.sh"
KEYCHAIN_PASSWORD_FILE="$ROOT/scripts/codesign/alttab-signing.pass"
[ -f "$KEYCHAIN_PASSWORD_FILE" ] || fail "missing $KEYCHAIN_PASSWORD_FILE — run scripts/codesign/setup_local.sh"
security unlock-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN"

step "Compiling (SwiftPM, release)"
swift build -c "$CONFIG" --scratch-path "$SCRATCH"

step "Assembling bundle"
rm -rf "$STAGE"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES" "$FRAMEWORKS"
cp "$PRODUCTS/AltTab" "$CONTENTS/MacOS/AltTab"
cp -R "$PRODUCTS/CrashReporter.framework" "$FRAMEWORKS/"

step "Packaging Sparkle.framework"
# SwiftPM builds the dynamic Sparkle product as a bare dylib. Sparkle has to be a framework bundle:
# it finds its own resources with [NSBundle bundleWithIdentifier:@"org.sparkle-project.Sparkle"] and
# NSWindowController loads its nibs from the framework's Resources. So the dylib is wrapped in the
# standard macOS versioned framework layout here.
SPARKLE_FW="$STAGE/Sparkle.framework"
mkdir -p "$SPARKLE_FW/Versions/A/Resources" "$SPARKLE_FW/Versions/A/Modules" "$SPARKLE_FW/Versions/A/Headers"
cp "$PRODUCTS/libSparkle.dylib" "$SPARKLE_FW/Versions/A/Sparkle"
chmod u+w "$SPARKLE_FW/Versions/A/Sparkle"
install_name_tool -id "@rpath/Sparkle.framework/Versions/A/Sparkle" "$SPARKLE_FW/Versions/A/Sparkle"
ln -sfn A "$SPARKLE_FW/Versions/Current"
ln -sfn Versions/Current/Sparkle "$SPARKLE_FW/Sparkle"
ln -sfn Versions/Current/Resources "$SPARKLE_FW/Resources"
ln -sfn Versions/Current/Modules "$SPARKLE_FW/Modules"
ln -sfn Versions/Current/Headers "$SPARKLE_FW/Headers"
cp "$ROOT/vendor/Sparkle/Sources/Sparkle/include/module.modulemap" "$SPARKLE_FW/Versions/A/Modules/module.modulemap"
cp "$ROOT/vendor/Sparkle/Sources/Sparkle/include/Sparkle/"*.h "$SPARKLE_FW/Versions/A/Headers/"
cat > "$SPARKLE_FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Sparkle</string>
	<key>CFBundleIdentifier</key>
	<string>$SPARKLE_IDENTIFIER</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Sparkle</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>2.9.1</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key>
	<string>2054</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.13</string>
</dict>
</plist>
PLIST

# The repo's own phase: copies Sparkle's prebuilt Updater.app/Autoupdate into the framework, mirrors
# the SPM resource bundle (nibs, lprojs, css) into the framework's Resources, and re-seals it.
cp -R "$PRODUCTS/Sparkle_Sparkle.bundle" "$STAGE/Sparkle_Sparkle.bundle"
SRCROOT="$ROOT" \
BUILT_PRODUCTS_DIR="$STAGE" \
FRAMEWORKS_FOLDER_PATH="" \
UNLOCALIZED_RESOURCES_FOLDER_PATH="" \
CODE_SIGN_IDENTITY="$IDENTITY" \
    bash "$ROOT/scripts/copy_sparkle_helpers.sh"
mv "$SPARKLE_FW" "$FRAMEWORKS/Sparkle.framework"

# The helpers ship signed with the upstream maintainer's Developer ID, which this machine doesn't
# have. Re-sign them with the local identity, then re-seal the framework around them, so the whole
# bundle carries one consistent signature.
codesign --force "${codesign_args[@]}" --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework/Versions/A/Autoupdate"
codesign --force "${codesign_args[@]}" --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework/Versions/A/Updater.app"
codesign --force "${codesign_args[@]}" --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework"

step "Copying resources"
cp -R "$ROOT/resources/l10n/"*.lproj "$RESOURCES/"
cp "$ROOT/resources/icons/app/app.png" "$RESOURCES/"
cp "$ROOT/resources/icons/menubar/"*.pdf "$RESOURCES/"
cp "$ROOT/resources/illustrations/"*.heic "$RESOURCES/"
cp "$ROOT/resources/SF-Pro-Text-Regular.otf" "$RESOURCES/"
cp "$ROOT/docs/acknowledgments.md" "$ROOT/docs/contributors.md" "$RESOURCES/"

step "Building ShortcutRecorder_ShortcutRecorder.bundle"
# ShortcutRecorder's SRBundle() looks this bundle up by name in the main bundle. Its asset catalog
# can't be compiled without actool (Xcode-only), so the PNGs are copied flat: -[NSBundle
# imageForResource:] pairs "<name>.png" with "<name>@2x.png" into one multi-representation NSImage,
# which is what the recorder's image loader expects.
SR_BUNDLE="$RESOURCES/ShortcutRecorder_ShortcutRecorder.bundle"
SR_SRC="$ROOT/vendor/ShortcutRecorder/Sources/ShortcutRecorder"
mkdir -p "$SR_BUNDLE/Contents/Resources"
cp "$SR_SRC/Images.xcassets/"*/*.png "$SR_BUNDLE/Contents/Resources/"
# The style descriptions ("sr-mojave-info", "sr-yosemite-info") are DATA assets: NSDataAsset only
# sees assets inside a compiled asset catalog, and compiling one needs actool (Xcode only). Ship the
# dataset's info.json — the very bytes the compiled catalog would have held — as a loose file;
# SRRecorderControlStyle falls back to it. Without it the style loader raises "Missing
# sr-mojave-info" and the app dies as soon as the Settings window builds a recorder control.
for dataset in "$SR_SRC/Images.xcassets/"*.dataset; do
	[ -d "$dataset" ] || continue
	cp "$dataset/info.json" "$SR_BUNDLE/Contents/Resources/$(basename "$dataset" .dataset).json"
done
for lproj in "$SR_SRC/"*.lproj; do cp -R "$lproj" "$SR_BUNDLE/Contents/Resources/"; done
cat > "$SR_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleIdentifier</key>
	<string>com.kulakov.ShortcutRecorder</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>ShortcutRecorder</string>
	<key>CFBundlePackageType</key>
	<string>BNDL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
</dict>
</plist>
PLIST

step "Writing Info.plist"
python3 "$ROOT/scripts/generate_info_plist.py" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

step "Fixing dynamic references"
# Sparkle was built as a dylib; the app must load it from the embedded framework.
install_name_tool -change "@rpath/libSparkle.dylib" "@rpath/Sparkle.framework/Versions/A/Sparkle" \
	"$CONTENTS/MacOS/AltTab"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/AltTab"

step "Signing"
# Every nested framework has to carry a signature of its own: the app's signature records their
# CDHashes, so an unsigned one makes the whole bundle fail verification.
codesign --force "${codesign_args[@]}" --sign "$IDENTITY" "$FRAMEWORKS/CrashReporter.framework"
codesign --force "${codesign_args[@]}" --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"

if [ "$install_app" -eq 1 ]; then
	step "Installing to $INSTALL_DIR"
	rm -rf "$INSTALL_DIR/AltTab.app"
	cp -R "$APP" "$INSTALL_DIR/AltTab.app"
	codesign --verify --strict "$INSTALL_DIR/AltTab.app"
	echo "installed: $INSTALL_DIR/AltTab.app"
else
	echo "built: $APP"
fi
