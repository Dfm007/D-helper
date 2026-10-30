#!/bin/bash
# 从 design/app-icon-D-1024.png 生成 Resources/AppIcon.icns
#
# 只在改了图标源文件后需要跑一次；生成的 icns 会进仓库，日常构建不用重跑。
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="design/app-icon-D-1024.png"
OUT="Resources/AppIcon.icns"
SET="build/AppIcon.iconset"

[ -f "$SRC" ] || { echo "缺少源图：$SRC"; exit 1; }

W=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
if [ "$W" != "1024" ] || [ "$H" != "1024" ]; then
    echo "源图必须是 1024×1024，当前 ${W}×${H}"
    exit 1
fi

rm -rf "$SET"
mkdir -p "$SET"

# macOS 需要的 10 个尺寸（基准 + @2x）
sips -z 16   16   "$SRC" --out "$SET/icon_16x16.png"      >/dev/null
sips -z 32   32   "$SRC" --out "$SET/icon_16x16@2x.png"   >/dev/null
sips -z 32   32   "$SRC" --out "$SET/icon_32x32.png"      >/dev/null
sips -z 64   64   "$SRC" --out "$SET/icon_32x32@2x.png"   >/dev/null
sips -z 128  128  "$SRC" --out "$SET/icon_128x128.png"    >/dev/null
sips -z 256  256  "$SRC" --out "$SET/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$SRC" --out "$SET/icon_256x256.png"    >/dev/null
sips -z 512  512  "$SRC" --out "$SET/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$SRC" --out "$SET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$SRC" --out "$SET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$SET" -o "$OUT"
echo "已生成 $OUT"
echo "下次构建会带进 app 包；若 Dock 仍显示旧图标：touch build/D-helper.app && killall Dock"
