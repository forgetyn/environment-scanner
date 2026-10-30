#!/bin/bash

# Environment Scanner v4.3.0 - 最终报告
# 先校验 AI 判断（防编造文件），通过后渲染最终报告，再用系统默认程序打开。

set -euo pipefail

EVIDENCE_FILE="${1:-}"
JUDGMENT_FILE="${2:-}"
OUTPUT_FILE="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../templates/final-report.html"

if [ -z "$EVIDENCE_FILE" ] || [ -z "$JUDGMENT_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "用法: bash scripts/generate-final-report.sh <evidence.json> <judgment.json> <output.html>"
    exit 1
fi

for required in "$EVIDENCE_FILE" "$JUDGMENT_FILE" "$TEMPLATE_FILE"; do
    if [ ! -f "$required" ]; then
        echo "❌ 文件不存在: $required"
        exit 1
    fi
done

if ! PYTHON_BIN="$("$SCRIPT_DIR/find-python.sh")"; then
    exit 1
fi

"$PYTHON_BIN" "$SCRIPT_DIR/lib/judgment.py" validate "$EVIDENCE_FILE" "$JUDGMENT_FILE"
"$PYTHON_BIN" "$SCRIPT_DIR/lib/judgment.py" render "$EVIDENCE_FILE" "$JUDGMENT_FILE" "$TEMPLATE_FILE" "$OUTPUT_FILE"

# 报告已经落盘。打开失败只提示，避免把写好的报告判成失败。
if ! "$PYTHON_BIN" "$SCRIPT_DIR/lib/open_report.py" "$OUTPUT_FILE"; then
    echo "⚠️ 报告已生成，但没有自动打开。请手动打开: $OUTPUT_FILE"
fi
