#!/usr/bin/env bash
#
# dev.sh —— 本地开发一键：后台启动本地网关 + 打开 Xcode 工程。
#
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 编译并后台启动本地网关 (Hummingbird :8787)"
swift build -c debug
swift run HongguoGateway &
GATEWAY_PID=$!
echo "    网关 PID=$GATEWAY_PID (curl http://127.0.0.1:8787/api/health 验证)"

echo "==> 打开 Xcode 工程"
if command -v open >/dev/null 2>&1; then
  open Package.swift   # Xcode 16 直接以 SPM 工程打开
fi

echo "==> 开发结束按 Ctrl+C 关闭网关"
trap "kill $GATEWAY_PID 2>/dev/null" EXIT
wait
