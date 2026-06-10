#!/bin/zsh
# 把 DeskCat 打包成双击即用的 .app
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release

APP="DeskCat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/DeskCat "$APP/Contents/MacOS/"
cp -R .build/release/DeskCat_DeskCat.bundle "$APP/Contents/Resources/"

# GLTFKit2 动态框架
FRAMEWORK=$(find .build -name "GLTFKit2.framework" -path "*release*" -maxdepth 4 | head -1)
if [ -z "$FRAMEWORK" ]; then
  FRAMEWORK=$(find .build -name "GLTFKit2.framework" | head -1)
fi
cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/DeskCat" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DeskCat</string>
    <key>CFBundleIdentifier</key><string>com.teddy.deskcat</string>
    <key>CFBundleName</key><string>DeskCat</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "✅ 已生成 $PWD/$APP"
