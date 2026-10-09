#!/usr/bin/env bash
#
# build-release.sh —— 构建红果桌面 macOS 客户端并发布到公开 releases 仓库。
#
# 前置：
#   - Xcode 16+ 命令行工具（xcodebuild）
#   - 环境变量 GITHUB_TOKEN（有 hongguo-desktop-releases 的 contents/release 写权限）
#   - 已用 Xcode 完成 App archive 并将 .app 放入 ./release/RedGuo.app
#     （或设置 XCODE_SCHEME / XCODE_PROJECT 由脚本调用 xcodebuild archive）
#
# 产出：
#   ./release/RedGuo-mac-vX.Y.Z-universal.dmg
#   ./release/RedGuo-mac-vX.Y.Z-universal.zip
#   ./release/latest.json
# 并上传到 g-star1024/hongguo-desktop-releases 的对应 Release。
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
RELEASE_DIR="$ROOT/release"
mkdir -p "$RELEASE_DIR"

VERSION="${1:-1.0.0-mac}"
APP_NAME="RedGuo"
DMG_NAME="${APP_NAME}-mac-v${VERSION}-universal"
: "${GITHUB_TOKEN:?请先 export GITHUB_TOKEN}"
REPO="g-star1024/hongguo-desktop-releases"

echo "==> [1/5] 编译本地网关 (release, universal)"
swift build -c release --arch arm64 --arch x86_64
GATEWAY_BIN="$ROOT/.build/apple/Products/Release/HongguoGateway"

echo "==> [2/5] 打包 App（若 release/ 下已有 .app 则跳过 archive）"
APP_PATH="$RELEASE_DIR/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  if [ -n "${XCODE_PROJECT:-}" ] && [ -n "${XCODE_SCHEME:-}" ]; then
    echo "    调用 xcodebuild archive ..."
    xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" \
      -configuration Release -destination "generic/platform=macOS" \
      -archivePath "$RELEASE_DIR/${APP_NAME}.xcarchive" archive
    APP_PATH=$(find "$RELEASE_DIR/${APP_NAME}.xcarchive" -name "${APP_NAME}.app" -type d | head -1)
  else
    echo "    未找到 $APP_PATH 且未设置 XCODE_PROJECT/XCODE_SCHEME，请先在 Xcode 完成 archive。"
    exit 1
  fi
fi

# 将网关可执行嵌入 App 的 Helpers（运行时由 App 启动）
HELPERS="$APP_PATH/Contents/Helpers"
mkdir -p "$HELPERS"
cp "$GATEWAY_BIN" "$HELPERS/HongguoGateway"
chmod +x "$HELPERS/HongguoGateway"

echo "==> [3/5] 生成 dmg 与 zip"
# 依赖 create-dmg（brew install create-dmg）或回退 hdiutil
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg --overwrite "$RELEASE_DIR/${DMG_NAME}.dmg" "$APP_PATH" || true
else
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" \
    -ov -format UDZO "$RELEASE_DIR/${DMG_NAME}.dmg"
fi
(cd "$RELEASE_DIR" && zip -r -q "${DMG_NAME}.zip" "${APP_NAME}.app")

echo "==> [4/5] 生成 latest.json"
cat > "$RELEASE_DIR/latest.json" <<EOF
{
  "version": "${VERSION}",
  "pub_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "platforms": {
    "darwin-universal": {
      "url": "https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_NAME}.dmg",
      "signature": ""
    }
  }
}
EOF

echo "==> [5/5] 发布到 $REPO"
# 创建（或复用）release
curl -s -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d "{\"tag_name\":\"v${VERSION}\",\"name\":\"v${VERSION}\",\"draft\":false,\"prerelease\":false}" \
  "https://api.github.com/repos/${REPO}/releases" >/dev/null || true

REL_ID=$(curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  "https://api.github.com/repos/${REPO}/releases/tags/v${VERSION}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('id',''))")

for f in "${DMG_NAME}.dmg" "${DMG_NAME}.zip" "latest.json"; do
  echo "    上传 $f ..."
  curl -s -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$RELEASE_DIR/$f" \
    "https://uploads.github.com/repos/${REPO}/releases/${REL_ID}/assets?name=$f" >/dev/null
done

echo "==> 完成。版本 v${VERSION} 已发布到 https://github.com/${REPO}/releases"
