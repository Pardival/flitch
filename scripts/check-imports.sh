#!/usr/bin/env bash
# FlitchKit must stay headless: only the FlitchStage target may import AppKit / SwiftUI / Cocoa.
set -euo pipefail
cd "$(dirname "$0")/../Packages/FlitchKit/Sources"
bad=$(grep -rlE '^\s*import\s+(AppKit|Cocoa|SwiftUI)\b' --include='*.swift' . | grep -v '^./FlitchStage/' || true)
if [[ -n "$bad" ]]; then
  echo "error: UI frameworks imported outside FlitchStage:" >&2
  echo "$bad" >&2
  exit 1
fi
echo "module boundaries ok"
