#!/bin/bash

# Environment Scanner v3.0.0 - 最终报告
# 先校验 AI 判断（防编造文件），通过后渲染最终报告。

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

PYTHON_BIN="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON_BIN" ]; then
    echo "❌ 需要 python3 才能生成最终报告"
    exit 1
fi

"$PYTHON_BIN" "$SCRIPT_DIR/lib/judgment.py" validate "$EVIDENCE_FILE" "$JUDGMENT_FILE"
"$PYTHON_BIN" "$SCRIPT_DIR/lib/judgment.py" render "$EVIDENCE_FILE" "$JUDGMENT_FILE" "$TEMPLATE_FILE" "$OUTPUT_FILE"
