#!/usr/bin/env bash
#
# BiliGlass 真机安装脚本
#
# 前置条件（只需做一次）：
#   1. Xcode → Settings → Accounts 添加 Apple ID（taojt08@icloud.com）
#   2. iPhone 解锁后重新连接数据线，弹窗点「信任」
#   3. iPhone → 设置 → 隐私与安全性 → 开发者模式 → 打开并重启
#
# 用法：
#   ./install-device.sh               # 自动探测已连接设备
#   ./install-device.sh <设备UDID>    # 指定设备
#
set -euo pipefail

cd "$(dirname "$0")"

SCHEME="BiliGlass"
TEAM="4486C55NWW"
BUNDLE_ID="com.biliglass.app"

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$1"; exit 1; }

# ---------- 1. 签名条件检查 ----------
step "检查签名条件"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
PROFILE_COUNT=$(ls "$PROFILE_DIR"/*.mobileprovision 2>/dev/null | wc -l | tr -d ' ')
# 已登录时该 plist 会包含 "identifier = <UUID>"；注意 Xcode 生成 profile 后
# 可能反过来清空这个键，所以不能只靠它判断
ACCOUNT_HINTS=$(defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists 2>/dev/null | grep -c "identifier" || true)

if [ "${PROFILE_COUNT:-0}" -eq 0 ] && [ "${ACCOUNT_HINTS:-0}" -eq 0 ]; then
    cat <<'EOM'
✗ 既没有可用的 provisioning profile，Xcode 也未登录 Apple ID，无法签名。

  请完成其一：
    A) 用 Xcode 打开本工程，选中 target → Signing & Capabilities →
       Team 选「Tao Jiang (Personal Team)」，再按 ⌘R 运行一次，
       Xcode 会自动创建 profile 并装到手机。之后本脚本可直接使用。
    B) Xcode → Settings（⌘,）→ Accounts → 登录 taojt08@icloud.com
EOM
    exit 1
fi

if [ "${PROFILE_COUNT:-0}" -gt 0 ]; then
    echo "✓ 已有 $PROFILE_COUNT 个 provisioning profile"
else
    echo "✓ 账号已登录（首次构建将自动申请 profile）"
fi

# ---------- 2. 设备检查 ----------
step "探测已连接的真机"
if [ $# -ge 1 ]; then
    UDID="$1"
else
    # 只挑物理设备（排除模拟器），状态可能是 connected 或 available。
    # UDID 形如 00008140-001878511A39801C，用正则提取比按列号取更稳。
    # 必须再排掉 "My Mac"：本机也会作为 destination 出现在列表里，
    # 一旦排在第一位就会拿 Mac 的 UDID 去构建，报 "macOS platform doesn't match"。
    UDID=$(xcrun devicectl list devices 2>/dev/null \
        | grep -v simulated \
        | grep -vi "My Mac" \
        | grep -E "connected|available" \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' \
        | head -1)
fi
[ -n "${UDID:-}" ] || fail "没找到已连接的真机。请用数据线连接 iPhone 并解锁后重试。"

echo "✓ 设备 UDID: $UDID"

DEVICE_NAME=$(xcrun devicectl list devices 2>/dev/null \
    | grep "$UDID" | sed "s/$UDID.*//" | sed 's/[[:space:]]*$//')

# ---------- 3. 生成工程 ----------
step "生成 Xcode 工程"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate >/dev/null
    echo "✓ 工程已刷新"
else
    echo "· 未安装 xcodegen，沿用已有 .xcodeproj"
fi

# ---------- 4. 编译（自动生成 profile） ----------
step "编译并签名（首次会自动申请 provisioning profile）"
BUILD_LOG="/tmp/biliglass-device-build.log"
if ! xcodebuild \
    -project "${SCHEME}.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "id=$UDID" \
    -configuration Debug \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    build > "$BUILD_LOG" 2>&1; then
    echo
    grep -E "error:" "$BUILD_LOG" | head -12
    fail "编译失败，完整日志：$BUILD_LOG"
fi
echo "✓ 编译完成"

# ---------- 5. 定位产物 ----------
APP_PATH=$(grep -oE '/[^ ]*Debug-iphoneos/BiliGlass\.app' "$BUILD_LOG" | head -1 || true)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    APP_PATH=$(xcodebuild -project "${SCHEME}.xcodeproj" -scheme "$SCHEME" \
        -destination "id=$UDID" -configuration Debug -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/BiliGlass.app
fi
[ -d "$APP_PATH" ] || fail "找不到构建产物，请检查 $BUILD_LOG"
echo "✓ 产物: $APP_PATH"

# ---------- 6. 安装 ----------
step "安装到 ${DEVICE_NAME:-设备}"
if ! xcrun devicectl device install app --device "$UDID" "$APP_PATH" 2>&1 | tail -8; then
    cat <<'EOM'
✗ 安装失败。常见原因：
  · iPhone 处于锁屏状态 → 解锁后重试
  · 未信任此电脑 → 拔插数据线，弹窗点「信任」
  · 未开启开发者模式 → 设置 → 隐私与安全性 → 开发者模式
EOM
    exit 1
fi

# ---------- 7. 启动 ----------
step "启动 App"
LAUNCH_OUT=$(xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" 2>&1 || true)

if echo "$LAUNCH_OUT" | grep -qi "not been explicitly trusted\|invalid code signature"; then
    cat <<EOM

\033[1;33m⚠ 已安装，但需要先在手机上信任开发者证书（免费签名首次必现）\033[0m

  在 iPhone 上操作：
    设置 → 通用 → VPN 与设备管理 → 开发者 App
    → 点「taojt08@icloud.com」→ 信任

  完成后点桌面图标即可打开；也可重跑本脚本自动启动。

注意：个人免费团队的签名有效期只有 7 天，到期后 App 会闪退打不开，
      重新运行本脚本即可续签。
EOM
    exit 0
fi

if echo "$LAUNCH_OUT" | grep -qi "error"; then
    echo "$LAUNCH_OUT" | tail -3
    exit 1
fi

echo "✓ 已启动"

cat <<EOM

\033[1;32m✓ 全部完成\033[0m

注意：个人免费团队的签名有效期只有 7 天，到期后 App 会闪退打不开，
      重新运行本脚本即可续签。
EOM
