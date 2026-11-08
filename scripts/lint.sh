#!/usr/bin/env bash
# Lint Swift sources (same check as CI) and module boundaries.
set -euo pipefail
cd "$(dirname "$0")/.."
swift format lint --strict --recursive App Packages/FlitchKit/Sources Packages/FlitchKit/Tests
./scripts/check-imports.sh
