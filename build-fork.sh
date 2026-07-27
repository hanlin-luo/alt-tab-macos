#!/usr/bin/env bash
# build-fork.sh — Build the patched AltTab.app (Release)
# Run from a normal Terminal (not sandboxed). Logs to build.log, writes
# .build-done or .build-failed marker when finished.
cd "$(dirname "$0")"
rm -f .build-done .build-failed build.log

# Inject the app version from the latest git tag. REQUIRED: without it the built
# Info.plist omits CFBundleVersion and the app SIGTRAPs at launch
# (App.swift force-unwraps it). Upstream CI does the same via config/local.xcconfig.
version=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
version=${version:-0.0.0}
echo "== AltTab fork build started: $(date), version $version ==" | tee build.log

xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData \
  CURRENT_PROJECT_VERSION="$version" 2>&1 | tee -a build.log | tail -5
status=${PIPESTATUS[0]}

binary="DerivedData/Build/Products/Release/AltTab.app/Contents/MacOS/AltTab"
if [[ $status -eq 0 && -f "$binary" ]]; then
  echo "== BUILD OK: DerivedData/Build/Products/Release/AltTab.app ($version) ==" | tee -a build.log
  touch .build-done
else
  echo "== BUILD FAILED (xcodebuild exit $status) — see build.log ==" | tee -a build.log
  touch .build-failed
fi
