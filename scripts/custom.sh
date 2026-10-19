#!/bin/bash
set -euo pipefail

echo ">>> 开始执行自定义定制脚本..."

# 1. 默认后台 IP 192.168.2.1
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate 2>/dev/null || true

# 2. root 密码 12345678
ROOT_HASH=$(openssl passwd -1 -salt lede 12345678)
sed -i "s|^root::|root:${ROOT_HASH}:|" package/base-files/files/etc/shadow 2>/dev/null || true

# 3. 主机名
sed -i 's/OpenWrt/LEDE-X86/g' package/base-files/files/etc/config/system 2>/dev/null || true

# 4. 固定时区 Asia/Shanghai
sed -i "s/option timezone.*/option timezone 'CST-8'/" package/base-files/files/etc/config/system 2>/dev/null || true
sed -i "s/option zonename.*/option zonename 'Asia\/Shanghai'/" package/base-files/files/etc/config/system 2>/dev/null || true

# 5. 默认主题 Argon
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' package/lean/default-settings/files/zzz-default-settings 2>/dev/null || true

# 6. i18n 自动配套
PLUGINS="
luci-app-smartdns
luci-app-ddnsto
luci-app-adguardhome
luci-app-oaf
luci-app-turboacc
luci-app-mwan3
luci-app-nlbwmon
luci-app-easytier
luci-app-wol
luci-app-upnp
luci-app-ttyd
luci-app-autoreboot
luci-app-wechatpush
"
for pkg in $PLUGINS; do
    short="${pkg#luci-app-}"
    i18n="luci-i18n-${short}-zh-cn"
    if find package/feeds -maxdepth 4 -type d -name "$i18n" 2>/dev/null | grep -q .; then
        echo "CONFIG_PACKAGE_${i18n}=y" >> .config
    fi
done

# 7. 强制配置 TurboAcc（仅开启流量分载、全锥形 NAT、BBR，关闭 SFE 等）
TURBOACC_CONF="package/lean/luci-app-turboacc/root/etc/config/turboacc"
if [ -f "$TURBOACC_CONF" ]; then
cat > "$TURBOACC_CONF" <<'EOF'
config turboacc 'config'
	option sw_flow '1'
	option fullcone '1'
	option tcp_bbr '1'
	option sfe_ipv4 '0'
	option sfe_ipv6 '0'
	option dns_caching '0'
EOF
fi

# 8. 修复 OAF 在 Linux 6.15+ (当前内核 6.18) 的 Timer API 编译错误
echo ">>> 正在适配 Linux 6.18 内核 OAF Timer 接口..."
OAF_C_FILE=$(find package/feeds -type f -name "app_filter.c" 2>/dev/null | head -n 1)
if [ -n "$OAF_C_FILE" ]; then
    echo ">>> 找到 OAF 源文件: $OAF_C_FILE，正在替换废弃的 Timer API..."
    # 将 del_timer_sync 替换为 timer_delete_sync
    sed -i 's/del_timer_sync/timer_delete_sync/g' "$OAF_C_FILE"
    # 替换旧的 from_timer 宏以适配新内核
    sed -i 's/from_timer(/timer_container_of(/g' "$OAF_C_FILE"
else
    echo ">>> 警告: 未找到 app_filter.c，请检查 feeds 目录结构"
fi

echo ">>> custom.sh 执行完成"