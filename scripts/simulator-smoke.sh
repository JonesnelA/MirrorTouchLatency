#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Simulator/MirrorLatency.app
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
arch="$(uname -m)"
xcrun --sdk iphonesimulator swiftc \
  -sdk "$sdk" -target "$arch-apple-ios15.0-simulator" -swift-version 5 \
  -module-name MirrorLatency -parse-as-library -O -whole-module-optimization \
  App/*.swift -framework UIKit -framework QuartzCore -framework Network \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -o build/Simulator/MirrorLatency.app/MirrorLatency
cp App/Info.plist build/Simulator/MirrorLatency.app/Info.plist
device="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
devices=json.load(sys.stdin)["devices"]
pads=[d for group in devices.values() for d in group if "iPad" in d["name"] and d.get("isAvailable")]
assert pads, "No available iPad simulator"
print(pads[0]["udid"])
')"
xcrun simctl boot "$device"
xcrun simctl bootstatus "$device" -b
xcrun simctl install "$device" build/Simulator/MirrorLatency.app
xcrun simctl launch "$device" com.mirrortest.latency --visual-test
sleep 3
python3 scripts/test-usb-protocol.py
xcrun simctl terminate "$device" com.mirrortest.latency
xcrun simctl launch "$device" com.mirrortest.latency
sleep 3
python3 scripts/test-usb-protocol.py --touch-only
xcrun simctl io "$device" screenshot dist/iPad-launch.png
xcrun simctl spawn "$device" launchctl list | grep -F 'com.mirrortest.latency' > dist/simulator-process.txt
python3 -c 'from pathlib import Path; rows=Path("dist/simulator-process.txt").read_text().splitlines(); assert any(r.split()[0].isdigit() and int(r.split()[0])>0 for r in rows), "App exited after launch"; print("PASS iPad simulator app remains running")'
