#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

xcrun momc "$repo_root/xDrip/Core Data/xdrip.xcdatamodeld/xdrip v31.xcdatamodel" "$test_dir/v31.mom"
xcrun momc "$repo_root/xDrip/Core Data/xdrip.xcdatamodeld/xdrip v32.xcdatamodel" "$test_dir/v32.mom"
xcrun momc "$repo_root/xDrip/Core Data/xdrip.xcdatamodeld/xdrip v32-garmin.xcdatamodel" "$test_dir/v32-garmin.mom"
xcrun momc "$repo_root/xDrip/Core Data/xdrip.xcdatamodeld/xdrip v33.xcdatamodel" "$test_dir/v33.mom"
swiftc -swift-version 5 -o "$test_dir/migration-test" "$repo_root/tests/g7-trend/migration.swift"
for source in v31 v32 v32-garmin; do
    "$test_dir/migration-test" "$test_dir/$source.mom" "$test_dir/v33.mom" "$test_dir/$source.sqlite" "$source"
done
