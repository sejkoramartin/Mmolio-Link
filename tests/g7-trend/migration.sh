#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

xcrun momc "$repo_root/xDrip/Core Data/xdrip.xcdatamodeld/xdrip v31.xcdatamodel" "$test_dir/v31.mom"
xcrun momc "$repo_root/xDrip/Core Data/xdrip.xcdatamodeld/xdrip v32.xcdatamodel" "$test_dir/v32.mom"
swiftc -swift-version 5 -o "$test_dir/migration-test" "$repo_root/tests/g7-trend/migration.swift"
"$test_dir/migration-test" "$test_dir/v31.mom" "$test_dir/v32.mom" "$test_dir/store.sqlite"
