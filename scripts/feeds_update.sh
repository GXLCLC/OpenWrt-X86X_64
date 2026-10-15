#!/usr/bin/env bash
# =============================================================================
# feeds_update.sh
# 职责：第三方插件仓库浅克隆 + feeds 源更新
# 说明：ImmortalWrt 24.10 源码仅内置 4 个 feeds（packages/luci/routing/telephony），
#       用户所需的第三方插件需放入 openwrt/package/ 目录后再参与编译。
#       所有仓库均采用浅克隆 + 仅下载所需目录的方式，不拉取整仓，节省编译耗时。
#       任一仓库/分支/路径拉取失败时立即退出，并输出明确的缺失项与来源仓库信息。
# =============================================================================

set -euo pipefail

OPENWRT_DIR="${1:-openwrt}"
cd "$OPENWRT_DIR"

# 临时目录：存放各仓库浅克隆内容
TMPDIR_FEEDS="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FEEDS"' EXIT

# 浅克隆深度：仅取最新提交，减少下载量
SHALLOW="--depth=1"

# -----------------------------------------------------------------------------
# 通用函数：浅克隆指定仓库的指定分支，失败立即终止并输出来源信息
# 参数: $1=仓库地址 $2=分支名 $3=本地目录名
# -----------------------------------------------------------------------------
shallow_clone() {
    local repo="$1" branch="$2" name="$3" dest="$TMPDIR_FEEDS/$name"
    echo "==> 正在浅克隆: $repo (分支: $branch)"
    if ! git clone --quiet $SHALLOW --single-branch --branch "$branch" "$repo" "$dest"; then
        echo "=============================================================="
        echo "[致命错误] 第三方仓库拉取失败"
        echo "  缺失项   : $name"
        echo "  来源仓库 : $repo"
        echo "  指定分支 : $branch"
        echo "  可能原因 : 分支被删除/改名、仓库地址变更、网络异常"
        echo "=============================================================="
        exit 1
    fi
    echo "    克隆完成: $dest"
}

# -----------------------------------------------------------------------------
# 通用函数：从已克隆仓库复制所需目录到 openwrt/package/，失败立即终止
# 参数: $1=仓库目录名 $2=仓库内相对路径 $3=目标包名
# -----------------------------------------------------------------------------
copy_package() {
    local repo_name="$1" src_rel="$2" dst_name="$3"
    local src="$TMPDIR_FEEDS/$repo_name/$src_rel"
    local dst="package/$dst_name"
    if [ ! -d "$src" ]; then
        echo "=============================================================="
        echo "[致命错误] 插件目录在仓库中不存在（可能路径被调整）"
        echo "  缺失项   : $src_rel"
        echo "  来源仓库 : $(git -C "$TMPDIR_FEEDS/$repo_name" remote get-url origin 2>/dev/null || echo '未知')"
        echo "  本地路径 : $src"
        echo "=============================================================="
        exit 1
    fi
    rm -rf "$dst"
    mkdir -p "$dst"
    cp -a "$src/." "$dst/"
    echo "    已安装: package/$dst_name"
}

echo "=============================================================="
echo "[1/6] 拉取 kenzok8/openwrt-packages（AdGuardHome LuCI 面板）"
echo "=============================================================="
shallow_clone "https://github.com/kenzok8/openwrt-packages" "master" "kenzok8"
# luci-app-adguardhome：LuCI 面板（自带 /etc/init.d/AdGuardHome 与
# update_core.sh，首次启动时从 AdGuard 官方源下载预编译二进制到
# /usr/bin/AdGuardHome，无需本地编译核心程序）
# 说明：不复制 kenzok8 的 adguardhome 源码包，理由：
#   1) kenzok8 0.107.79 的 go.mod 声明 go 1.26.6，且含 tool/ignore 块，
#      而 ImmortalWrt 24.10 内置 Go 1.23.12 且 GOTOOLCHAIN=local，无法编译；
#   2) 官方 24.10 feeds 的 adguardhome 0.107.57 虽可编译，但其 init 为小写
#      /etc/init.d/adguardhome，会被 luci-app 的 postinst 主动禁用，纯属冗余；
#   3) 面板默认 INCLUDE_binary=n，二进制改由运行时下载，体验一致。
copy_package "kenzok8" "luci-app-adguardhome" "luci-app-adguardhome"

echo "=============================================================="
echo "[2/6] 拉取 EasyTier/luci-app-easytier（默认 main 分支）"
echo "=============================================================="
shallow_clone "https://github.com/EasyTier/luci-app-easytier" "main" "easytier"
# easytier：下载预编译二进制后端，依赖 kmod-tun
copy_package "easytier" "easytier"           "easytier"
# luci-app-easytier：LuCI 前端
copy_package "easytier" "luci-app-easytier"  "luci-app-easytier"

echo "=============================================================="
echo "[3/6] 拉取 DDNSTO 双仓库（luci 前端 + 后端程序，缺一不可）"
echo "=============================================================="
# 前端：nas-packages-luci 的 main 分支
shallow_clone "https://github.com/linkease/nas-packages-luci" "main" "ddnsto-luci"
copy_package "ddnsto-luci" "luci/luci-app-ddnsto" "luci-app-ddnsto"
# 后端：nas-packages 的 master 分支
shallow_clone "https://github.com/linkease/nas-packages" "master" "ddnsto-backend"
copy_package "ddnsto-backend" "network/services/ddnsto" "ddnsto"

echo "=============================================================="
echo "[4/6] 拉取 destan19/OpenAppFilter（OAF：kmod-oaf + luci-app-oaf）"
echo "=============================================================="
shallow_clone "https://github.com/destan19/OpenAppFilter" "master" "oaf"
# open-app-filter：内核模块源码（kmod-oaf）
copy_package "oaf" "open-app-filter" "open-app-filter"
# oaf：用户态 appfilter 服务
copy_package "oaf" "oaf" "oaf"
# luci-app-oaf：LuCI 前端
copy_package "oaf" "luci-app-oaf" "luci-app-oaf"

echo "=============================================================="
echo "[5/6] 拉取 chenmozhijin/turboacc（luci 分支适配 firewall4 + package 分支依赖）"
echo "=============================================================="
# luci 分支：luci-app-turboacc 本体（适配 24.10 firewall4/nftables）
shallow_clone "https://github.com/chenmozhijin/turboacc" "luci" "turboacc-luci"
copy_package "turboacc-luci" "luci-app-turboacc" "luci-app-turboacc"
# package 分支：加速组件依赖（nft-fullcone / shortcut-fe / firewall4 / nftables / libnftnl / 内核补丁）
shallow_clone "https://github.com/chenmozhijin/turboacc" "package" "turboacc-pkg"

echo "  -- 安装 nft-fullcone / shortcut-fe 内核模块包 --"
copy_package "turboacc-pkg" "nft-fullcone" "nft-fullcone"
copy_package "turboacc-pkg" "shortcut-fe" "shortcut-fe"

echo "  -- 替换 firewall4 / nftables / libnftnl 为 turboacc 适配版本 --"
# 先读取源码内版本号，再从 package 分支取出对应目录
FIREWALL4_VERSION="$(grep -oP 'PKG_SOURCE_VERSION:=\s*\K[0-9a-f]{6,40}' package/network/config/firewall4/Makefile || true)"
NFTABLES_VERSION="$(grep -oP 'PKG_VERSION:=\s*\K[0-9.]+' package/network/utils/nftables/Makefile || true)"
LIBNFTNL_VERSION="$(grep -oP 'PKG_VERSION:=\s*\K[0-9.]+' package/libs/libnftnl/Makefile || true)"
echo "    源码版本: firewall4=$FIREWALL4_VERSION nftables=$NFTABLES_VERSION libnftnl=$LIBNFTNL_VERSION"

rm -rf package/network/config/firewall4 \
       package/network/utils/nftables \
       package/libs/libnftnl

copy_package "turboacc-pkg" "firewall4-$FIREWALL4_VERSION/firewall4" "network/config/firewall4"
copy_package "turboacc-pkg" "nftables-$NFTABLES_VERSION/nftables"   "network/utils/nftables"
copy_package "turboacc-pkg" "libnftnl-$LIBNFTNL_VERSION/libnftnl"   "libs/libnftnl"

echo "  -- 安装 TurboAcc 内核补丁（内核 6.6 已确认支持）--"
# x86_64 目标内核版本 6.6，补丁按 add_turboacc.sh 逻辑拷贝
KERNEL_VER="6.6"
for patch_dir in "hack-$KERNEL_VER" "pending-$KERNEL_VER"; do
    if [ -d "$TMPDIR_FEEDS/turboacc-pkg/$patch_dir" ]; then
        mkdir -p "target/linux/generic/$patch_dir"
        cp -af "$TMPDIR_FEEDS/turboacc-pkg/$patch_dir/." "target/linux/generic/$patch_dir/"
        echo "    已安装补丁目录: target/linux/generic/$patch_dir"
    else
        echo "=============================================================="
        echo "[致命错误] TurboAcc 内核补丁目录缺失"
        echo "  缺失项   : $patch_dir"
        echo "  来源仓库 : https://github.com/chenmozhijin/turboacc (分支: package)"
        echo "  内核版本 : $KERNEL_VER"
        echo "=============================================================="
        exit 1
    fi
done

# 追加内核 config（与 add_turboacc.sh 一致，防止与官方配置冲突）
KERNEL_CFG="target/linux/generic/config-$KERNEL_VER"
grep -q "CONFIG_NF_CONNTRACK_CHAIN_EVENTS" "$KERNEL_CFG" \
    || echo "# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set" >> "$KERNEL_CFG"
grep -q "CONFIG_SHORTCUT_FE" "$KERNEL_CFG" \
    || echo "# CONFIG_SHORTCUT_FE is not set" >> "$KERNEL_CFG"
echo "    已更新: $KERNEL_CFG"

echo "=============================================================="
echo "[6/6] 更新 ImmortalWrt 官方 feeds 并安装到 staging 目录"
echo "=============================================================="
# feeds.conf.default 已内置 4 个 feeds；此处重新拉取更新并安装
./scripts/feeds update -a
./scripts/feeds install -a

echo "=============================================================="
echo "feeds_update.sh 执行完毕"
echo "=============================================================="
