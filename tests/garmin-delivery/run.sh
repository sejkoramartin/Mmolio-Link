#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/mmolio-delivery.XXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT
swiftc -swift-version 5 \
    "$repo/xDrip/Managers/Garmin/GarminModels.swift" \
    "$repo/tests/garmin-delivery/BgReadingSnapshot.swift" \
    "$repo/tests/garmin-delivery/main.swift" \
    -o "$build_dir/garmin-delivery-tests"
"$build_dir/garmin-delivery-tests"
