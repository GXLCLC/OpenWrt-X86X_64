#!/usr/bin/env bash
# =============================================================================
# system-config.sh
# 职责：修改 ImmortalWrt 源码，使编译产出的固件符合以下默认设置
#   1. 管理地址 LAN IP  : 192.168.2.1
#   2. 后台登录密码     : 12345678（用户名 root）
#   3. 时区            : Asia/Shanghai（UTC+8）
#   4. 默认主题        : argon
#   5. 默认语言        : 简体中文
#   6. 主机名          : ImmortalWrt
# 说明：所有修改均在 openwrt/ 源码内完成，写入 /etc/uci-defaults 首次启动脚本，
#       不影响后续手动配置。
# =============================================================================

set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
cd "$OPENWRT_DIR"

# -----------------------------------------------------------------------------
# 1. LAN IP 改为 192.168.2.1
#    源码位置：package/base-files/files/bin/config_generate
#    默认值  : 192.168.1.1
# -----------------------------------------------------------------------------
CONFIG_GENERATE="package/base-files/files/bin/config_generate"
if [ ! -f "$CONFIG_GENERATE" ]; then
    echo "=============================================================="
    echo "[致命错误] 未找到 config_generate，无法修改默认 LAN IP"
    echo "  缺失项 : $CONFIG_GENERATE"
    echo "  源码目录: $(pwd)"
    echo "=============================================================="
    exit 1
fi

sed -i "s/192\.168\.1\.1/192.168.2.1/g" "$CONFIG_GENERATE"
echo "[1/6] LAN 默认 IP 已改为 192.168.2.1"

# -----------------------------------------------------------------------------
# 2. 登录密码改为 12345678（sha512 加密）
#    源码位置：package/base-files/files/etc/shadow
#    默认值  : root:::0:99999:7:::  (空密码)
#    生成方式：openssl passwd -5 <明文>
# -----------------------------------------------------------------------------
SHADOW_FILE="package/base-files/files/etc/shadow"
if [ ! -f "$SHADOW_FILE" ]; then
    echo "=============================================================="
    echo "[致命错误] 未找到 shadow 文件，无法设置登录密码"
    echo "  缺失项 : $SHADOW_FILE"
    echo "=============================================================="
    exit 1
fi

# 生成 sha512 哈希；OpenWrt 默认使用 $5$ 格式
PASSWORD_HASH="$(openssl passwd -5 '12345678')"
# shadow 格式：root:<hash>:0:99999:7:::
sed -i "s|^root:::|root:${PASSWORD_HASH}:0:99999:7:::|123456" "$SHADOW_FILE"
echo "[2/6] root 登录密码已设置为 12345678（sha512）"

# -----------------------------------------------------------------------------
# 3~6. 时区 / 语言 / 主题 / 主机名
#      写入 /etc/uci-defaults/99-custom-settings，首次启动时自动生效
#      注意：uci-defaults 脚本执行后会自动删除自身，不重复执行
# -----------------------------------------------------------------------------
UCI_DEFAULTS="package/base-files/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS"

cat > "$UCI_DEFAULTS/99-custom-settings" <<'EOF'
#!/bin/sh
# 由 system-config.sh 生成：设置默认时区、语言、主题、主机名

# 3. 时区 Asia/Shanghai（CST-8 = UTC+8）
uci set system.@system[-1].timezone='CST-8'
uci set system.@system[-1].zonename='Asia/Shanghai'
uci commit system

# 4. 默认主题 argon
uci set luci.themes.Argon='/luci-static/argon'
uci delete luci.themes.Bootstrap 2>/dev/null || true
# 5. 默认语言简体中文
uci set luci.main.lang='zh_cn'
uci commit luci

# 6. 主机名
uci set system.@system[-1].hostname='ImmortalWrt'
uci commit system

exit 0
EOF

chmod 0755 "$UCI_DEFAULTS/99-custom-settings"
echo "[3/6] 时区已设置为 Asia/Shanghai"
echo "[4/6] 默认主题已设置为 argon"
echo "[5/6] 默认语言已设置为简体中文"
echo "[6/6] 主机名已设置为 ImmortalWrt"

echo "=============================================================="
echo "system-config.sh 执行完毕"
echo "=============================================================="
