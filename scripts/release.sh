#!/bin/zsh
# 编译打包并发布到 GitHub Release。版本号取自 Resources/Info.plist 的 CFBundleShortVersionString。
# 用法：先改 Info.plist 里的版本号，提交推送后执行 ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
ZIP="build.noindex/QuickTrans-$VERSION.zip"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG 已存在，先在 Info.plist 里升级版本号" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "工作区有未提交的改动，先提交再发布" >&2
  exit 1
fi

./scripts/build.sh
rm -f "$ZIP"
ditto -c -k --keepParent build.noindex/QuickTrans.app "$ZIP"

gh release create "$TAG" "$ZIP" --target "$(git rev-parse HEAD)" --title "QuickTrans $VERSION" --notes "需要 macOS 26 以上、Apple 芯片。安装步骤见 README 的「安装」一节。"
echo "已发布 $TAG"
