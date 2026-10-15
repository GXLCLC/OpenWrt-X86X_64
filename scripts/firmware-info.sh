#!/usr/bin/env bash
# =============================================================================
# firmware-info.sh
# 职责：编译结束后收集固件信息，生成 release_info.md 与版本清单
#   1. 定位 squashfs-combined.img（x86_64 默认镜像）
#   2. 从 config 中提取构建配置摘要（目标平台、分区大小）
#   3. 从源码中提取版本信息（ImmortalWrt 版本号、内核版本）
#   4. 汇总插件清单（从 X86_64.config 提取已启用的包）
#   5. 生成 release_info.md，供 Release 页面展示与用户查阅
# 用法：firmware-info.sh <openwrt_dir> <config_file> <输出目录>
# =============================================================================

set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
CONFIG_FILE="${2:-config/X86_64.config}"
OUTPUT_DIR="${3:-release_info}"

# 脚本可能被 cd 到其他目录后调用，先把 config 路径转为绝对路径
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$PWD/$CONFIG_FILE"
fi

# 输出目录同样转为绝对路径，避免 cd 后写入位置漂移
if [ "${OUTPUT_DIR:0:1}" != "/" ]; then
    OUTPUT_DIR="$PWD/$OUTPUT_DIR"
fi

cd "$OPENWRT_DIR"

# 常量：与用户约定的默认设置保持一致
readonly LAN_IP="192.168.2.1"
readonly ROOT_PASSWORD="12345678"
readonly TIMEZONE="Asia/Shanghai"
readonly HOSTNAME="ImmortalWrt"

mkdir -p "$OUTPUT_DIR"

# -----------------------------------------------------------------------------
# 1. 定位固件镜像
#    x86_64 目标在 CONFIG_GRUB_IMAGES 开启时产出 squashfs-combined.img
# -----------------------------------------------------------------------------
IMAGE_DIR="bin/targets/x86/64"
COMBINED_IMG="$IMAGE_DIR/squashfs-combined.img"

if [ ! -f "$COMBINED_IMG" ]; then
    echo "=============================================================="
    echo "[致命错误] 未找到固件镜像 $COMBINED_IMG"
    echo "  可能原因 : CONFIG_GRUB_IMAGES 未开启，或编译失败"
    echo "  镜像目录 : $(ls -1 "$IMAGE_DIR" 2>/dev/null || echo '目录不存在')"
    echo "=============================================================="
    exit 1
fi

# 镜像文件名与大小（MB）
IMAGE_NAME="$(basename "$COMBINED_IMG")"
IMAGE_SIZE_RAW="$(stat -c %s "$COMBINED_IMG")"
IMAGE_SIZE_MB="$(awk -v b="$IMAGE_SIZE_RAW" 'BEGIN {printf "%.1f", b/1024/1024}')"
echo "[1/5] 已定位固件: $IMAGE_NAME (${IMAGE_SIZE_MB} MB)"

# -----------------------------------------------------------------------------
# 2. 提取版本信息
#    ImmortalWrt 版本号来自 include/version.mk 的 VERSION_NUMBER
#    内核版本来自 target/linux/generic 的 KERNEL_PATCHVER 或构建日志
# -----------------------------------------------------------------------------
IMMORTALWRT_VERSION="未知"
if [ -f "include/version.mk" ]; then
    IMMORTALWRT_VERSION="$(grep -oP 'VERSION_NUMBER:=\s*\K[^\s]+' include/version.mk || echo '未知')"
    [ -z "$IMMORTALWRT_VERSION" ] && IMMORTALWRT_VERSION="未知"
fi

KERNEL_VERSION="未知"
if [ -f "include/kernel-version.mk" ]; then
    KERNEL_VERSION="$(grep -oP 'LINUX_VERSION-6\.6\s*=\s*\K[0-9.]+' include/kernel-version.mk \
        || grep -oP 'LINUX_VERSION-6\.6 =\s*\K[0-9.]+' include/kernel-version.mk \
        || echo '6.6')"
fi
echo "[2/5] 版本信息: ImmortalWrt $IMMORTALWRT_VERSION / Linux $KERNEL_VERSION"

# -----------------------------------------------------------------------------
# 3. 从 config 文件提取构建摘要
# -----------------------------------------------------------------------------
get_config_value() {
    grep -oP "^\s*$1=\K.*" "$CONFIG_FILE" 2>/dev/null | tail -1 || true
}

ROOTFS_PARTSIZE="$(get_config_value 'CONFIG_TARGET_ROOTFS_PARTSIZE')"
KERNEL_PARTSIZE="$(get_config_value 'CONFIG_TARGET_KERNEL_PARTSIZE')"
[ -z "$ROOTFS_PARTSIZE" ] && ROOTFS_PARTSIZE="160"
[ -z "$KERNEL_PARTSIZE" ] && KERNEL_PARTSIZE="64"

# -----------------------------------------------------------------------------
# 4. 汇总插件清单
#    从 config 中提取 CONFIG_PACKAGE_<name>=y，剔除内核模块/驱动/基础工具
# -----------------------------------------------------------------------------
ALL_PACKAGES="$(grep -oP '^\s*CONFIG_PACKAGE_\K[a-zA-Z0-9_-]+(?==y)' "$CONFIG_FILE" 2>/dev/null | sort -u || true)"

# 需要展示的应用插件白名单（与 config 中的插件清单一一对应）
APP_PLUGINS=(
    "luci-app-smartdns"
    "luci-app-ddnsto"
    "luci-app-adguardhome"
    "luci-app-oaf"
    "luci-app-turboacc"
    "luci-app-mwan3"
    "luci-app-argon-config"
    "luci-app-nlbwmon"
    "luci-app-easytier"
    "luci-app-openclash"
)

# 插件中文名映射（用于 Release 说明展示）
plugin_display_name() {
    case "$1" in
        luci-app-smartdns)    echo "SmartDNS（DNS 加速/防污染）" ;;
        luci-app-ddnsto)      echo "DDNSTO（内网穿透）" ;;
        luci-app-adguardhome) echo "AdGuardHome（广告过滤 DNS）" ;;
        luci-app-oaf)         echo "OAF / OpenAppFilter（应用过滤）" ;;
        luci-app-turboacc)    echo "TurboAcc（网络加速：BBR/FullCone/Offload）" ;;
        luci-app-mwan3)       echo "Mwan3（多线负载均衡）" ;;
        luci-app-argon-config) echo "Argon 主题配置" ;;
        luci-app-nlbwmon)     echo "nlbwmon（带宽监控）" ;;
        luci-app-easytier)    echo "EasyTier（异地组网）" ;;
        luci-app-openclash)   echo "OpenClash（代理网关）" ;;
        *)                    echo "$1" ;;
    esac
}

PLUGIN_ROWS=""
PLUGIN_COUNT=0
for pkg in "${APP_PLUGINS[@]}"; do
    if echo "$ALL_PACKAGES" | grep -qx "$pkg"; then
        PLUGIN_ROWS="${PLUGIN_ROWS}| $(plugin_display_name "$pkg") | 已内置 |"$'\n'
        PLUGIN_COUNT=$((PLUGIN_COUNT + 1))
    else
        PLUGIN_ROWS="${PLUGIN_ROWS}| $(plugin_display_name "$pkg") | 未启用 |"$'\n'
    fi
done
echo "[3/5] 插件清单: 共 $PLUGIN_COUNT 个应用插件"

# -----------------------------------------------------------------------------
# 5. 生成 release_info.md
# -----------------------------------------------------------------------------
BUILD_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"
GIT_COMMIT="${GITHUB_SHA:-本地构建}"

cat > "$OUTPUT_DIR/release_info.md" <<EOF
# ImmortalWrt X86_64 固件信息

- **构建时间**: $BUILD_DATE
- **源码提交**: \`$GIT_COMMIT\`
- **ImmortalWrt 版本**: $IMMORTALWRT_VERSION
- **内核版本**: Linux $KERNEL_VERSION
- **固件文件**: \`$IMAGE_NAME\`
- **固件大小**: ${IMAGE_SIZE_MB} MB
- **镜像格式**: squashfs（combined，含 GRUB 引导）

## 默认设置

| 项目 | 值 |
|------|-----|
| 管理地址 | \`$LAN_IP\` |
| 登录用户 | \`root\` |
| 登录密码 | \`$ROOT_PASSWORD\` |
| 时区 | $TIMEZONE |
| 默认主题 | Argon |
| 默认语言 | 简体中文 |
| 主机名 | $HOSTNAME |
| kernel 分区 | ${KERNEL_PARTSIZE} MB |
| rootfs + overlay | ${ROOTFS_PARTSIZE} MB |

## 内置插件（$PLUGIN_COUNT 个）

| 插件 | 状态 |
|------|------|
$PLUGIN_ROWS
## 网络加速特性

- TCP BBR 拥塞控制
- Shortcut-FE（连接跟踪快速路径）
- NFT FullCone NAT（TurboAcc）
- Flow Offloading（硬件/软件卸载）

## 刷写说明

1. 使用 \`dd\` 或 balenaEtcher 将 \`$IMAGE_NAME\` 写入硬盘/U 盘：
   \`\`\`bash
   dd if=$IMAGE_NAME of=/dev/sdX bs=4M status=progress
   \`\`\`
2. 首次启动后访问 \`http://$LAN_IP\` 进入 LuCI 管理界面。
3. AdGuardHome 首次启用时，面板会自动从 AdGuard 官方源下载预编译核心二进制，请保持网络连通。

EOF

echo "[4/5] 已生成: $OUTPUT_DIR/release_info.md"

# -----------------------------------------------------------------------------
# 6. 同步生成固件 sha256 校验文件
# -----------------------------------------------------------------------------
CHECKSUM_FILE="$OUTPUT_DIR/$IMAGE_NAME.sha256"
( cd "$IMAGE_DIR" && sha256sum "$IMAGE_NAME" > "$OUTPUT_DIR/$IMAGE_NAME.sha256" )
echo "[5/5] 已生成校验文件: $CHECKSUM_FILE"

echo "=============================================================="
echo "firmware-info.sh 执行完毕"
echo "=============================================================="
