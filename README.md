# DramaCube (Flutter) CI 打包发布仓
#
# 本仓用于承载 Flutter 全平台版的 GitHub Actions 构建与 Release 发布。
# 源码在私有仓 [hongguo-desktop](https://github.com/g-star1024/hongguo-desktop)，
# 本仓 workflow 用 PAT checkout 后构建，Actions 免费（公开仓）。
#
# 发版：
#   gh workflow run build.yml -R g-star1024/DramaCube-releases -f ref=main -f version=2.7.8
#
# 参数：ref=源码 ref（main / vX.Y.Z / commit）、version=版本号
# 平台：Windows / Linux / Android / macOS(arm64) / macOS(x64) 五平台并行
name: DramaCube-releases
