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
APP_NAME="剧立方"
BUNDLE_ID="com.dramacube.mac"
EXEC_NAME="HongguoMacApp"
BUILD_DIR=".build/dist"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/dramacube-macOS-$ARCH-$VERSION.zip"
DMG_PATH="$BUILD_DIR/dramacube-macOS-$ARCH-$VERSION.dmg"

echo "==> [1/6] Swift Release 构建 (arch: ${ARCH})"
# 用 xcrun 确保走 Xcode 完整工具链（裸 /usr/bin/swift 在仅有 CLT 的环境找不到标准库）
SWIFT="${SWIFT:-xcrun swift}"
if [ "$ARCH" = "universal" ]; then
    # 分架构各编一次再 lipo 合成（实测 Intel mac 交叉编 arm64 也可行，v2.3.2 验证）。
    # 注意两点：
    # 1) 不能一次 `swift build --arch arm64 --arch x86_64`——SwiftPM 多 --arch
    #    destination 下评估依赖包 swiftLanguageVersions 有已知 bug。
    # 2) 交叉编译用 --triple（--destination 在 Swift 6 已不接受 triple 字符串，
    #    报 "doesn't exist in file system"）；且必须给第二个架构独立 --scratch-path，
    #    否则 .build/release 会被后编的架构覆盖，拿不到两种切片。
    echo "    分架构构建：arm64 + x86_64 → lipo 合成 universal"
    $SWIFT build --disable-sandbox -c release --product "$EXEC_NAME" --triple "arm64-apple-macosx14.0"
    ARM_BIN=".build/arm64-apple-macosx/release/$EXEC_NAME"
    [ -x "$ARM_BIN" ] || ARM_BIN="$(find .build -path "*arm64*/release/$EXEC_NAME" -type f | head -1)"
    $SWIFT build --disable-sandbox -c release --product "$EXEC_NAME" --triple "x86_64-apple-macosx14.0" --scratch-path ".build-x86"
    X86_BIN=".build-x86/x86_64-apple-macosx/release/$EXEC_NAME"
    [ -x "$X86_BIN" ] || X86_BIN="$(find .build-x86 -path "*x86_64*/release/$EXEC_NAME" -type f | head -1)"
    [ -x "$ARM_BIN" ] || { echo "arm64 二进制未找到: $ARM_BIN"; exit 1; }
    [ -x "$X86_BIN" ] || { echo "x86_64 二进制未找到: $X86_BIN"; exit 1; }
    BIN_DIR=".build/dist/universal-bin"
    mkdir -p "$BIN_DIR"
    lipo -create "$ARM_BIN" "$X86_BIN" -output "$BIN_DIR/$EXEC_NAME"
else
    $SWIFT build --disable-sandbox -c release --product "$EXEC_NAME" --arch "$ARCH"
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
    <key>NSHumanReadableCopyright</key><string>© 2026 DramaCube</string>
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
ditto -c -k --keepParent "$APP_NAME.app" "dramacube-macOS-$ARCH-$VERSION.zip"
cd - > /dev/null

echo "==> [5/6] DMG 镜像"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $VERSION" \
    -srcfolder "$APP_PATH" -ov -format UDZO -size 300m "$DMG_PATH" > /dev/null

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
  "architectures": ["$ARCH"],
  "downloads": {
    "zip": "https://github.com/g-star1024/hongguo-mac/releases/download/v$VERSION/dramacube-macOS-$ARCH-$VERSION.zip",
    "dmg": "https://github.com/g-star1024/hongguo-mac/releases/download/v$VERSION/dramacube-macOS-$ARCH-$VERSION.dmg"
  }
}
JSON

echo ""
echo "✅ 打包完成:"
ls -lh "$APP_PATH" "$ZIP_PATH" "$DMG_PATH" "$BUILD_DIR/latest.json"
