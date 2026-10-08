#!/usr/bin/env bash
# WebSpace Flutter CI gate: static checks + packaging, no interactive tests.
#   ./ci.sh
set -euo pipefail
cd "$(dirname "$0")"

flutter analyze
flutter test
./build.sh
