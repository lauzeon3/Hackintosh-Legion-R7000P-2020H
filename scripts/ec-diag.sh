#!/usr/bin/env bash
# ec-diag.sh — EC 寄存器 & 电池状态诊断脚本（P0 用）
# 用法: ./scripts/ec-diag.sh [输出目录]
# 默认输出目录: ./diag-output/
#
# 输出: ./diag-output/ec-<时间戳>/  下五个文本文件
#   01-ioreg-ec.txt         EC 设备节点（PNP0C09）
#   02-ioreg-tree.txt       完整 IODeviceTree
#   03-ioreg-battery.txt    AppleSmartBattery 节点
#   04-kextstat.txt         SMC / Battery / EC 相关 kext
#   05-system-info.txt      系统版本 + pmset + 启动参数
#
# 把整个 ec-<时间戳>/ 目录发给 AI 即可分析。

set -euo pipefail

OUT_DIR="${1:-./diag-output}"
mkdir -p "$OUT_DIR"
TS=$(date +%Y%m%d-%H%M%S)
RUN_DIR="$OUT_DIR/ec-$TS"
mkdir -p "$RUN_DIR"

echo "==> EC 诊断输出目录: $RUN_DIR"
echo

# 1. EC 设备节点
echo "[1/5] 抓取 EC 设备节点 (PNP0C09)..."
if ioreg -lw0 | grep -B 2 -A 30 "EC (PNP0C09)" > "$RUN_DIR/01-ioreg-ec.txt" 2>/dev/null; then
    LINES=$(wc -l < "$RUN_DIR/01-ioreg-ec.txt" | tr -d ' ')
    echo "    -> 01-ioreg-ec.txt ($LINES 行)"
else
    echo "    -> 01-ioreg-ec.txt (空，未找到 EC 节点)"
    : > "$RUN_DIR/01-ioreg-ec.txt"
fi

# 2. 完整 IODeviceTree
echo "[2/5] 抓取完整 IODeviceTree..."
ioreg -lw0 -p IODeviceTree > "$RUN_DIR/02-ioreg-tree.txt" 2>/dev/null || true
LINES=$(wc -l < "$RUN_DIR/02-ioreg-tree.txt" | tr -d ' ')
echo "    -> 02-ioreg-tree.txt ($LINES 行)"

# 3. 电池节点
echo "[3/5] 抓取电池节点 (AppleSmartBattery)..."
if ioreg -lw0 -p IODeviceTree | grep -A 50 "AppleSmartBattery" > "$RUN_DIR/03-ioreg-battery.txt" 2>/dev/null; then
    LINES=$(wc -l < "$RUN_DIR/03-ioreg-battery.txt" | tr -d ' ')
    echo "    -> 03-ioreg-battery.txt ($LINES 行)"
else
    echo "    -> 03-ioreg-battery.txt (空，未找到电池节点)"
    : > "$RUN_DIR/03-ioreg-battery.txt"
fi

# 4. SMC/Battery/EC 相关 kext
echo "[4/5] 抓取 SMC/Battery/EC 相关 kext..."
kextstat 2>/dev/null | grep -iE "smc|battery|ec " > "$RUN_DIR/04-kextstat.txt" || true
LINES=$(wc -l < "$RUN_DIR/04-kextstat.txt" | tr -d ' ')
echo "    -> 04-kextstat.txt ($LINES 行)"

# 5. 系统基本信息
echo "[5/5] 抓取系统基本信息..."
{
    echo "=== sw_vers ==="
    sw_vers
    echo
    echo "=== macOS Build ==="
    uname -a
    echo
    echo "=== CPU ==="
    sysctl -n machdep.cpu.brand_string
    echo
    echo "=== pmset -g (电源管理基线) ==="
    pmset -g
    echo
    echo "=== 启动参数（与 EC / AMFI 相关） ==="
    printenv | grep -iE "ece|amfi|smc" || echo "(无相关启动参数)"
    echo
    echo "=== OpenCore 版本（若可读） ==="
    OC_PLIST="/Volumes/EFI/EFI/OC/config.plist"
    if [ -f "$OC_PLIST" ]; then
        plutil -extract NVRAM.Add.4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14.opencore-version raw "$OC_PLIST" 2>/dev/null \
            && echo " (来自 EFI/OC/config.plist)" \
            || echo "EFI/OC/config.plist 存在但未读取到 OC 版本"
    else
        echo "EFI/OC/config.plist 未挂载或不可读"
    fi
} > "$RUN_DIR/05-system-info.txt"
echo "    -> 05-system-info.txt"

echo
echo "==> 完成。所有输出已保存到："
echo "    $RUN_DIR/"
echo
echo "==> 下一步操作："
echo "    1. 查看输出:  ls -la \"$RUN_DIR/\""
echo "    2. 快速预览:  cat \"$RUN_DIR/05-system-info.txt\""
echo "    3. 整个目录发给 AI 分析"
echo
ls -la "$RUN_DIR/"