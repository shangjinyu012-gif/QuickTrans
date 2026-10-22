#!/bin/zsh
# 编译并打包 build/QuickTrans.app。加 --install 时复制到 /Applications 并重新启动。
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/QuickTrans.app
SIGN_ID="QuickTrans Dev"

swift build -c release --product QuickTrans
BIN=$(swift build -c release --product QuickTrans --show-bin-path)/QuickTrans

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/QuickTrans"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  codesign --force --sign "$SIGN_ID" --identifier com.shangjinyu.QuickTrans "$APP"
else
  echo "未找到证书「$SIGN_ID」，使用临时签名（每次编译后需重新授权辅助功能）。先执行 scripts/make-cert.sh 可避免。"
  codesign --force --sign - --identifier com.shangjinyu.QuickTrans "$APP"
fi
echo "已生成 $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x QuickTrans 2>/dev/null && sleep 0.5 || true
  rm -rf /Applications/QuickTrans.app
  cp -R "$APP" /Applications/
  open /Applications/QuickTrans.app
  echo "已安装到 /Applications 并启动"
fi
