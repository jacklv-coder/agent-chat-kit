#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKED_BASELINE_PATH="$REPOSITORY_ROOT/API/AgentChatKit-iOS.json"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentchat-api.XXXXXX")"
BASE_WORKTREE=""

cleanup() {
  if [[ -n "$BASE_WORKTREE" ]]; then
    git -C "$REPOSITORY_ROOT" worktree remove --force "$BASE_WORKTREE" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

dump_api() {
  local source_root="$1"
  local output_path="$2"
  local derived_data="$3"
  local products="$derived_data/Build/Products/Release-iphonesimulator"
  local checkouts="$derived_data/SourcePackages/checkouts"
  local sdk
  sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"

  (
    cd "$source_root"
    xcodebuild -quiet \
      -scheme AgentChatKit-Package \
      -destination 'generic/platform=iOS Simulator' \
      -configuration Release \
      -derivedDataPath "$derived_data" \
      build

    xcrun swift-api-digester \
      -dump-sdk \
      -module AgentChatCore \
      -module AgentChatMarkdown \
      -module AgentChatUIKit \
      -module AgentChatTesting \
      -module AgentChatKit \
      -I "$products" \
      -sdk "$sdk" \
      -target arm64-apple-ios17.0-simulator \
      -swift-only \
      -avoid-location \
      -avoid-tool-args \
      -Xcc "-fmodule-map-file=$checkouts/swift-markdown/Sources/CAtomic/include/module.modulemap" \
      -Xcc "-fmodule-map-file=$checkouts/swift-cmark/src/include/module.modulemap" \
      -Xcc "-fmodule-map-file=$checkouts/swift-cmark/extensions/include/module.modulemap" \
      -Xcc "-I$checkouts/swift-markdown/Sources/CAtomic/include" \
      -Xcc "-I$checkouts/swift-cmark/src/include" \
      -Xcc "-I$checkouts/swift-cmark/extensions/include" \
      -o "$output_path"
  )
}

CURRENT_PATH="$TEMP_DIR/current.json"
dump_api "$REPOSITORY_ROOT" "$CURRENT_PATH" "$TEMP_DIR/CurrentDerivedData"

if [[ "${1:-}" == "--record" ]]; then
  mkdir -p "$(dirname "$CHECKED_BASELINE_PATH")"
  cp "$CURRENT_PATH" "$CHECKED_BASELINE_PATH"
  echo "Recorded public API baseline at $CHECKED_BASELINE_PATH"
  exit 0
fi

BASELINE_PATH="$CHECKED_BASELINE_PATH"
BASE_REF="${AGENTCHAT_API_BASE_REF:-}"
if [[ "$BASE_REF" =~ ^0+$ ]] && git -C "$REPOSITORY_ROOT" rev-parse --verify HEAD^ >/dev/null 2>&1; then
  BASE_REF="HEAD^"
fi
if [[ -n "$BASE_REF" ]]; then
  git -C "$REPOSITORY_ROOT" rev-parse --verify "$BASE_REF^{commit}" >/dev/null
  BASE_WORKTREE="$TEMP_DIR/baseline-source"
  git -C "$REPOSITORY_ROOT" worktree add --detach "$BASE_WORKTREE" "$BASE_REF" >/dev/null
  BASELINE_PATH="$TEMP_DIR/baseline.json"
  dump_api "$BASE_WORKTREE" "$BASELINE_PATH" "$TEMP_DIR/BaselineDerivedData"
  echo "Comparing public API with $BASE_REF using $(xcodebuild -version | head -1)"
elif [[ ! -f "$BASELINE_PATH" ]]; then
  echo "Missing API baseline: run Scripts/check-api-baseline.sh --record" >&2
  exit 1
fi

xcrun swift-api-digester \
  -diagnose-sdk \
  -input-paths "$BASELINE_PATH" \
  -input-paths "$CURRENT_PATH" \
  -print-module \
  -compiler-style-diags \
  -error-on-abi-breakage
