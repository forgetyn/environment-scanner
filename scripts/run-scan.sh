#!/bin/bash

# Environment Scanner v4.3.0 - 证据收集入口
# 只读扫描：计数（含结构聚合）+ 近期文档采样 + 应用清单 + 知识库发现 → 证据文件 + 证据报告。
# 建议由会话 AI 基于证据判断（含全局诊断与综合层），再由 generate-final-report.sh 校验后渲染。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.json"
SCAN_MODE="${1:-}"

if [ -z "$SCAN_MODE" ]; then
    if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
        SCAN_MODE="$(jq -r '.default_config.scan_depth // "deep"' "$CONFIG_FILE")"
    else
        SCAN_MODE="deep"
    fi
fi

case "$SCAN_MODE" in
    quick|standard|deep) ;;
    *)
        echo "⚠️ 未知扫描模式: $SCAN_MODE，回退到 deep"
        SCAN_MODE="deep"
        ;;
esac

if ! PYTHON_BIN="$("$SCRIPT_DIR/find-python.sh")"; then
    exit 1
fi

OUTPUT_DIR="${ENV_SCANNER_OUTPUT_DIR:-$HOME/.environment-scanner/reports}"
TIMESTAMP=$(date '+%Y-%m-%d-%H%M%S')
DATA_FILE="$OUTPUT_DIR/environment-scanner-data-$TIMESTAMP.json"
SAMPLES_FILE="$OUTPUT_DIR/environment-scanner-samples-$TIMESTAMP.json"
APPS_FILE="$OUTPUT_DIR/environment-scanner-apps-$TIMESTAMP.json"
KB_FILE="$OUTPUT_DIR/environment-scanner-kb-$TIMESTAMP.json"
EVIDENCE_FILE="$OUTPUT_DIR/environment-scanner-evidence-$TIMESTAMP.json"
EVIDENCE_REPORT_FILE="$OUTPUT_DIR/environment-scanner-evidence-report-$TIMESTAMP.html"

mkdir -p "$OUTPUT_DIR"

echo "🦞 Environment Scanner v4.3.0"
echo "================================"
echo "扫描模式: $SCAN_MODE"
echo "输出目录: $OUTPUT_DIR"
echo ""

echo "📊 阶段 1/5: 收集计数和体积..."
bash "$SCRIPT_DIR/collect-data.sh" "$DATA_FILE" "$SCAN_MODE"

echo ""
DOC_ARGS=()
if [ -n "${ENV_SCANNER_INSIGHT_DOCS:-}" ]; then
    # 多路径用分号：冒号会切开 Windows 盘符（C:\…）。macOS 路径不含分号。
    IFS=';' read -r -a ENV_DOCS <<< "$ENV_SCANNER_INSIGHT_DOCS"
    DOC_ARGS+=("${ENV_DOCS[@]}")
fi
if [ "$#" -gt 1 ]; then
    DOC_ARGS+=("${@:2}")
fi

echo "📄 阶段 2/5: 采样近期文档..."
if [ "${#DOC_ARGS[@]}" -gt 0 ]; then
    "$PYTHON_BIN" "$SCRIPT_DIR/lib/sample_content.py" --output "$SAMPLES_FILE" --mode "$SCAN_MODE" --explicit "${DOC_ARGS[@]}"
else
    "$PYTHON_BIN" "$SCRIPT_DIR/lib/sample_content.py" --output "$SAMPLES_FILE" --mode "$SCAN_MODE"
fi

echo ""
echo "📱 阶段 3/5: 收集应用清单（只读名字）..."
"$PYTHON_BIN" "$SCRIPT_DIR/lib/app_inventory.py" --output "$APPS_FILE"

KB_ARGS=()
echo ""
echo "📚 阶段 4/5: 发现知识库与自述文档（只读，可用 ENV_SCANNER_KB_DISCOVER=0 关闭）..."
if [ "${ENV_SCANNER_KB_DISCOVER:-1}" != "0" ]; then
    "$PYTHON_BIN" "$SCRIPT_DIR/lib/kb_discover.py" --output "$KB_FILE"
    KB_ARGS=(--kb "$KB_FILE")
else
    echo "ℹ️ 知识库发现已关闭。"
fi

echo ""
echo "🧾 阶段 5/5: 汇总证据并生成证据报告..."
"$PYTHON_BIN" "$SCRIPT_DIR/lib/evidence_pack.py" \
    --data "$DATA_FILE" --samples "$SAMPLES_FILE" --apps "$APPS_FILE" \
    ${KB_ARGS[@]+"${KB_ARGS[@]}"} --output "$EVIDENCE_FILE"
"$PYTHON_BIN" "$SCRIPT_DIR/lib/judgment.py" render "$EVIDENCE_FILE" \
    "$SCRIPT_DIR/../templates/final-report.html" "$EVIDENCE_REPORT_FILE"

for artifact in "$DATA_FILE" "$SAMPLES_FILE" "$APPS_FILE" "$EVIDENCE_FILE" "$EVIDENCE_REPORT_FILE"; do
    if [ ! -s "$artifact" ]; then
        echo "❌ 错误: 产物生成不完整: $artifact"
        exit 1
    fi
done

echo ""
echo "✅ 证据文件: $EVIDENCE_FILE"
echo "✅ 证据报告: $EVIDENCE_REPORT_FILE"
echo "ℹ️ 下一步: 由会话 AI 只读上面的证据文件，按 SKILL.md 的判断准则写"
echo "   $OUTPUT_DIR/environment-scanner-judgment-$TIMESTAMP.json"
echo "   再运行 bash scripts/generate-final-report.sh <evidence> <judgment> <output.html>"
echo "   Windows 运行: powershell -File scripts/generate-final-report.ps1 <evidence> <judgment> <output.html>"
echo "ℹ️ 扫描根目录中的用户文件不会被修改。"
