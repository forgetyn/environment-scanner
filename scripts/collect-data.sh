#!/bin/bash

# Environment Scanner v2.1.0 - 数据采集包装
# 计数和跳过规则在 scripts/lib/scan_collect.py

set -euo pipefail

OUTPUT_FILE="${1:-$HOME/.environment-scanner/reports/environment-scanner-data.json}"
SCAN_MODE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.json"

if [ -z "$SCAN_MODE" ]; then
    if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
        SCAN_MODE="$(jq -r '.default_config.scan_depth // "deep"' "$CONFIG_FILE")"
    else
        SCAN_MODE="deep"
    fi
fi

echo "🦞 Environment Scanner - 数据收集中..."
echo "输出文件: $OUTPUT_FILE"
echo "扫描模式: ${SCAN_MODE} (计数为真实总量)"
python3 "$SCRIPT_DIR/lib/scan_collect.py" --output "$OUTPUT_FILE" --mode "$SCAN_MODE"
cat "$OUTPUT_FILE"
