#!/bin/bash
# charge-mode 快速验证脚本
# 路径：features/charge-mode/tests/test-charge.sh
# 用法：bash tests/test-charge.sh

set -e
BIN="$(cd "$(dirname "$0")/.." && pwd)/bin/charge-mode"

if [[ ! -x "$BIN" ]]; then
    echo "✗ 找不到 $BIN"
    exit 1
fi

echo "===== 1. 当前状态 ====="
sudo "$BIN" status
echo ""

echo "===== 2. 切换到养护模式 ====="
sudo "$BIN" conservation
echo ""

echo "===== 3. 等待 2 秒 ====="
sleep 2
echo ""

echo "===== 4. 验证（应为 🛡️ 养护模式）====="
sudo "$BIN" status

echo ""
echo "===== 5. 切换回常规 ====="
sudo "$BIN" normal
sleep 2
sudo "$BIN" status
