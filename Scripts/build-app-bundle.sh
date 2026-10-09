#!/bin/bash
# =============================================================
# 红果短剧 macOS 打包脚本
#
# 用法:
#   ./Scripts/build-app-bundle.sh                 # ad-hoc 签名 + .app + .zip + .dmg
#   VERSION=1.2.0 ./Scripts/build-app-bundle.sh   # 指定版本号
#
# 可选环境变量:
#   VERSION       版本号（默认 1.0.0）
#   SIGN_IDENTITY  签名身份（默认 "-" 即 ad-hoc；正式分发传 "Developer ID Application: ..."）
#   ARCH          arm64 / x86_64（默认跟随本机；universal 需在 Apple Silicon 上跑）
#
# 公证（可选）: 设置以下三项后自动走 notarytool 并 staple:
#   APPLE_ID / APPLE_PASSWORD（App 专用密码）/ APPLE_TEAM_ID
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCH="${ARCH:-$(uname -m)}"
APP_NAME="红果短剧"
BUNDLE_ID="com.hongguo.desktop"
EXEC_NAME="HongguoMacApp"
BUILD_DIR=".build/dist"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/hongguo-macOS-$ARCH-$VERSION.zip"
DMG_PATH="$BUILD_DIR/hongguo-macOS-$ARCH-$VERSION.dmg"

echo "==> [1/6] Swift Release 构建 (arch: ${ARCH})"
if [ "$ARCH" = "universal" ]; then
    # 仅在 Apple Silicon 上可行（Intel 机无法出 arm64 切片）
    swift build -c release --product "$EXEC_NAME" --arch arm64 --arch x86_64
    BIN_DIR=".build/apple/Products/Release"
else
    swift build -c release --product "$EXEC_NAME" --arch "$ARCH"
    BIN_DIR=".build/release"
fi
BIN="$BIN_DIR/$EXEC_NAME"
[ -x "$BIN" ] || { echo "二进制未找到: $BIN"; exit 1; }
lipo -info "$BIN"

echo "==> [2/6] 组装 ${APP_NAME}.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 hongguo-desktop</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

# 图标（可选）：若 Resources/AppIcon.icns 存在则引用
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
    plutil -insert CFBundleIconFile -string "AppIcon" "$APP_PATH/Contents/Info.plist"
fi

cp "$BIN" "$APP_PATH/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$EXEC_NAME"

echo "==> [3/6] 码签名 (identity: ${SIGN_IDENTITY})"
cat > "$BUILD_DIR/entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.network.server</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --entitlements "$BUILD_DIR/entitlements.plist" "$APP_PATH"
codesign --verify --strict --verbose=1 "$APP_PATH"

echo "==> [4/6] Zip 分发包"
cd "$BUILD_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_NAME.app" "hongguo-macOS-$ARCH-$VERSION.zip"
cd - > /dev/null

echo "==> [5/6] DMG 镜像"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $VERSION" \
    -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH" > /dev/null

# 公证（提供凭证时执行）
if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "==> [6/6] 公证 + staple"
    xcrun notarytool submit "$ZIP_PATH" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" --wait
    xcrun stapler staple "$APP_PATH"
    xcrun stapler staple "$DMG_PATH"
else
    echo "==> [6/6] 跳过公证（未设置 APPLE_ID / APPLE_PASSWORD / APPLE_TEAM_ID）"
fi

# latest.json（发布 API 清单）
cat > "$BUILD_DIR/latest.json" <<JSON
{
  "version": "$VERSION",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "minOS": "14.0",
  "arch": "$ARCH",
  "downloads": {
    "zip": "https://github.com/g-star1024/hongguo-desktop-releases/releases/download/v$VERSION/hongguo-macOS-$ARCH-$VERSION.zip",
    "dmg": "https://github.com/g-star1024/hongguo-desktop-releases/releases/download/v$VERSION/hongguo-macOS-$ARCH-$VERSION.dmg"
  }
}
JSON

echo ""
echo "✅ 打包完成:"
ls -lh "$APP_PATH" "$ZIP_PATH" "$DMG_PATH" "$BUILD_DIR/latest.json"
