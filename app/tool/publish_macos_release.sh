#!/bin/bash
set -euo pipefail
: "${RELEASE_VERSION:?}"
: "${GITHUB_SHA:?}"
: "${GITHUB_REF_NAME:?}"
: "${UPDATE_FEED_TAG:?}"
: "${SPARKLE_TOOLS:?}"
: "${SPARKLE_KEY_FILE:?}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
# Preflight before making any new release public. Never replace published ZIPs.
if gh release view "$GITHUB_REF_NAME" --json isDraft,targetCommitish > "$RUNNER_TEMP/current-release.json" 2>/dev/null; then
  python3 - "$RUNNER_TEMP/current-release.json" "$GITHUB_SHA" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r['isDraft'] and r['targetCommitish']==sys.argv[2], 'Only a draft for this exact commit can be resumed'
PY
fi
if [[ "$GITHUB_REF_NAME" != "$UPDATE_FEED_TAG" ]]; then
  mkdir -p "$RUNNER_TEMP/old-feed"
  gh release download "$UPDATE_FEED_TAG" --pattern appcast.xml --pattern SHA256SUMS --dir "$RUNNER_TEMP/old-feed"
  "$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" --verify "$RUNNER_TEMP/old-feed/appcast.xml"
  python3 app/tool/advance_update_feed.py "$RUNNER_TEMP/old-feed/appcast.xml" dist/appcast.xml \
    "$RUNNER_TEMP/old-feed/SHA256SUMS" "$RUNNER_TEMP/SHA256SUMS"
fi
if [[ ! -s "$RUNNER_TEMP/current-release.json" ]]; then
  gh release create "$GITHUB_REF_NAME" --verify-tag --target "$GITHUB_SHA" --draft --prerelease \
    --title "Linefold $RELEASE_VERSION — 测试版" --notes-file "app/releases/$RELEASE_VERSION.md"
fi
gh release upload "$GITHUB_REF_NAME" dist/*.zip dist/*.dmg dist/appcast.xml dist/SHA256SUMS --clobber
gh release edit "$GITHUB_REF_NAME" --draft=false --prerelease --latest=false
if [[ "$GITHUB_REF_NAME" != "$UPDATE_FEED_TAG" ]]; then
  # The signed feed moves only after its immutable download URL is public.
  gh release upload "$UPDATE_FEED_TAG" dist/appcast.xml "$RUNNER_TEMP/SHA256SUMS" --clobber
fi
