#!/usr/bin/env bash
# Format Swift sources in place.
set -euo pipefail
cd "$(dirname "$0")/.."
swift format format --in-place --recursive App Packages/FlitchKit/Sources Packages/FlitchKit/Tests
