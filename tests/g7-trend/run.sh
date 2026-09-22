#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

swiftc -swift-version 5 -o "$test_dir/g7-trend-tests" \
  "$repo_root/xDrip/Extensions/Data.swift" \
  "$repo_root/xDrip/BluetoothTransmitter/CGM/Dexcom/Generic/DexcomTransmitterOpCode.swift" \
  "$repo_root/xDrip/BluetoothTransmitter/CGM/Dexcom/Generic/DexcomG7GlucoseDataRxMessage.swift" \
  "$repo_root/tests/g7-trend/main.swift"
"$test_dir/g7-trend-tests"
