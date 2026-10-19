#!/bin/bash
set -euo pipefail

IMAGE_DIR="bin/targets/x86/64"

echo ">>> 检查 CONFIG_TARGET_ROOTFS_PARTSIZE"
PARTSIZE=$(grep -E '^CONFIG_TARGET_ROOTFS_PARTSIZE=' .config | cut -d= -f2)
if [ "$PARTSIZE" != "2048" ]; then
    echo "ERROR: 分区大小不是 2048MB，实际为: ${PARTSIZE:-未设置}"
    exit 1
fi

echo ">>> 检查 squashfs combined img.gz"
FILES=$(find "$IMAGE_DIR" -maxdepth 1 -name "*squashfs*combined*.img.gz")
if [ -z "$FILES" ]; then
    echo "ERROR: 未找到 squashfs combined img.gz 镜像"
    exit 1
fi

for f in $FILES; do
    echo ">>> 校验: $f"
    gzip -t "$f" || { echo "ERROR: gzip 完整性失败: $f"; exit 1; }
    MAGIC=$(gzip -dc "$f" | head -c 4)
    if [ "$MAGIC" != "hsqs" ]; then
        echo "ERROR: 不是 squashfs 文件系统: $f"
        exit 1
    fi
    SIZE=$(stat -c%s "$f")
    echo "    文件大小: $((SIZE / 1024 / 1024)) MB"
done

echo ">>> 固件校验全部通过"
