#!/usr/bin/env bash
# sync-upstream.sh — Sync hanlin-luo/alt-tab-macos fork with upstream lwouis/alt-tab-macos
#
# What it does:
#   1. Fetches upstream (official repo) and origin (fork)
#   2. Merges upstream/master into local master (which carries the [FORK-PATCH] unlock commit)
#   3. Verifies the Pro-unlock patch survived the merge
#   4. Pushes the result to origin (GitHub fork)
#
# Safe to run repeatedly. If upstream touches the patched region, the merge may
# conflict — the script stops and tells you to resolve manually.
#
# Usage:  bash sync-upstream.sh           # sync + push
#         bash sync-upstream.sh --no-push # sync locally only

set -euo pipefail
cd "$(dirname "$0")"

PUSH=1
[[ "${1:-}" == "--no-push" ]] && PUSH=0

log() { echo "[sync] $*"; }
fail() { echo "[sync][ERROR] $*" >&2; exit 1; }

# --- 0. Sanity checks --------------------------------------------------------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not a git repo"
git remote get-url upstream >/dev/null 2>&1 || fail "missing 'upstream' remote"
git remote get-url origin   >/dev/null 2>&1 || fail "missing 'origin' remote"
[[ -z "$(git status --porcelain)" ]] || fail "working tree dirty — commit or stash first"

# --- 1. Unshallow if needed (first run after a shallow clone) ----------------
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  log "shallow clone detected — fetching full history"
  git fetch --unshallow origin || git fetch --depth=2147483647 origin
fi

# --- 2. Fetch both remotes ---------------------------------------------------
log "fetching upstream (lwouis/alt-tab-macos)…"
git fetch upstream --tags
log "fetching origin (hanlin-luo fork)…"
git fetch origin --tags

# --- 3. Anything new upstream? ----------------------------------------------
git checkout master --quiet
LOCAL_UPSTREAM_BASE="$(git merge-base master upstream/master)"
UPSTREAM_HEAD="$(git rev-parse upstream/master)"
if [[ "$LOCAL_UPSTREAM_BASE" == "$UPSTREAM_HEAD" ]]; then
  log "already up to date with upstream ($(git rev-parse --short upstream/master)) — nothing to merge"
else
  NEW_COUNT="$(git rev-list --count master..upstream/master)"
  LATEST_TAG="$(git describe --tags upstream/master 2>/dev/null || echo '?')"
  log "merging $NEW_COUNT new upstream commit(s), latest tag: $LATEST_TAG"
  if ! git merge upstream/master --no-edit; then
    echo
    echo "=============================================================="
    echo " MERGE CONFLICT — upstream touched code near the fork patch."
    echo " Resolve manually:"
    echo "   1. Edit conflicted files (look for [FORK-PATCH] markers)"
    echo "   2. Keep:  let forkUnlockPro = true / if forkUnlockPro { return .pro }"
    echo "   3. git add <files> && git merge --continue"
    echo "   4. Re-run this script"
    echo "=============================================================="
    exit 2
  fi
fi

# --- 4. Verify the unlock patch survived ------------------------------------
PATCH_FILE="src/pro/license/LicenseManager.swift"
if ! grep -q "FORK-PATCH" "$PATCH_FILE"; then
  fail "unlock patch LOST after merge — $PATCH_FILE no longer contains [FORK-PATCH]. Restore it before pushing!"
fi
if ! grep -q "if forkUnlockPro { return .pro }" "$PATCH_FILE"; then
  fail "unlock logic changed unexpectedly in $PATCH_FILE — review before pushing!"
fi
log "unlock patch verified in $PATCH_FILE"

# --- 5. Push to GitHub fork --------------------------------------------------
if [[ "$PUSH" == "1" ]]; then
  log "pushing master + tags to origin…"
  git push origin master --tags
  log "done. Fork is up to date: https://github.com/hanlin-luo/alt-tab-macos"
else
  log "--no-push given; local master updated only"
fi
