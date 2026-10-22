#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Payload/MirrorLatency.app dist
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos swiftc \
  -sdk "$sdk" -target arm64-apple-ios15.0 -swift-version 5 \
  -module-name MirrorLatency -parse-as-library -O -whole-module-optimization \
  App/*.swift -framework UIKit -framework QuartzCore -framework Network \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -o build/Payload/MirrorLatency.app/MirrorLatency
cp App/Info.plist build/Payload/MirrorLatency.app/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" build/Payload/MirrorLatency.app/Info.plist
plutil -lint build/Payload/MirrorLatency.app/Info.plist
# A direct swiftc binary can have an ad-hoc signature. Strip it before re-signing.
if codesign -dv build/Payload/MirrorLatency.app/MirrorLatency 2>/dev/null; then
  codesign --remove-signature build/Payload/MirrorLatency.app/MirrorLatency
fi
file build/Payload/MirrorLatency.app/MirrorLatency
otool -L build/Payload/MirrorLatency.app/MirrorLatency
python3 scripts/validate-build.py build/Payload/MirrorLatency.app
(cd build && /usr/bin/zip -qr ../dist/MirrorLatency-unsigned.ipa Payload)
shasum -a 256 dist/MirrorLatency-unsigned.ipa > dist/SHA256SUMS.txt
cp README.md dist/README.md
printf 'Unsigned IPA ready: dist/MirrorLatency-unsigned.ipa\n'
