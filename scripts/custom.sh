#!/bin/bash
set -euo pipefail

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

# 6. i18n 自动配套：存在 luci-i18n-<short>-zh-cn 才追加到 .config
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
        echo ">>> 已配套中文包: $i18n"
    fi
done

# 7. 确保 TurboAcc 默认仅启用流量分载/全锥形NAT/BBR（写入默认 UCI，不影响编译）
mkdir -p package/lean/default-settings/files
cat > package/lean/default-settings/files/zzz-turboacc-defaults <<'EOF'
uci set turboacc.config.sw_flow='1'
uci set turboacc.config.fullcone='1'
uci set turboacc.config.bbr='1'
uci commit turboacc
EOF

echo ">>> custom.sh 执行完成"
