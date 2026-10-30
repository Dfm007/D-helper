#!/bin/bash
# 构建 D-helper.app（x86_64 + arm64 通用二进制，ad-hoc 签名）
#
# 需要 SMCBridge.c（AppleSMC 的 C 桥）——Swift 侧通过 -import-objc-header 引入。
set -euo pipefail
cd "$(dirname "$0")"

APP="build/D-helper.app"
BIN="$APP/Contents/MacOS/D-helper"
MACOS_MIN="13.0"
ARCHS=(x86_64 arm64)
SOURCES=(Sources/*.swift)
FRAMEWORKS=(-framework IOKit -framework AppKit -framework SwiftUI -framework Combine)

echo "==> 清理旧产物"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BUILT=()
for ARCH in "${ARCHS[@]}"; do
    echo "==> 编译 $ARCH"
    clang -c -O2 -arch "$ARCH" -mmacosx-version-min="$MACOS_MIN" \
        -o "build/SMCBridge_$ARCH.o" Sources/SMCBridge.c
    swiftc -O -swift-version 5 \
        -target "$ARCH-apple-macos$MACOS_MIN" \
        -import-objc-header Sources/SMCBridge.h \
        "${SOURCES[@]}" "build/SMCBridge_$ARCH.o" \
        -o "build/D-helper_$ARCH" \
        "${FRAMEWORKS[@]}"
    BUILT+=("build/D-helper_$ARCH")
done

echo "==> 合并通用二进制"
lipo -create "${BUILT[@]}" -output "$BIN"
chmod +x "$BIN"

cp Resources/Info.plist "$APP/Contents/Info.plist"
for res in Resources/*; do
    name=$(basename "$res")
    [ "$name" = "Info.plist" ] && continue
    cp "$res" "$APP/Contents/Resources/$name"
done
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc 签名"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "完成：$(pwd)/$APP"
