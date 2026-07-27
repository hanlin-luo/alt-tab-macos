#!/usr/bin/env bash
# build-fork.sh — Build the patched AltTab.app (Release)
# Run from a normal Terminal (not sandboxed). Logs to build.log, writes
# .build-done or .build-failed marker when finished.
cd "$(dirname "$0")"
rm -f .build-done .build-failed build.log

echo "== AltTab fork build started: $(date) ==" | tee build.log
xcodebuild -project alt-tab-macos.xcodeproj -scheme Release -derivedDataPath DerivedData 2>&1 | tee -a build.log | tail -5

if [[ -d "DerivedData/Build/Products/Release/AltTab.app" ]]; then
  echo "== BUILD OK: DerivedData/Build/Products/Release/AltTab.app ==" | tee -a build.log
  touch .build-done
else
  echo "== BUILD FAILED — see build.log ==" | tee -a build.log
  touch .build-failed
fi
