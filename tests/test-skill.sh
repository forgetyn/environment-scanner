#!/bin/bash

# Environment Scanner Skill - 快速测试脚本（v3.0.0）

set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

echo "🦞 Environment Scanner Skill - 快速测试"
echo ""

check_file() {
    local file="$1"
    if [ -f "$SKILL_DIR/$file" ]; then
        echo "   ✅ $file"
    else
        echo "   ❌ 缺失: $file"
        FAIL=$((FAIL + 1))
    fi
}

echo "1. 核心文件"
check_file "SKILL.md"
check_file "AGENTS.md"
check_file "CHANGELOG.md"
check_file "config.json"
check_file "scripts/run-scan.sh"
check_file "scripts/collect-data.sh"
check_file "scripts/collect-data.ps1"
check_file "scripts/generate-final-report.sh"
check_file "scripts/lib/scan_collect.py"
check_file "scripts/lib/sample_content.py"
check_file "scripts/lib/app_inventory.py"
check_file "scripts/lib/evidence_pack.py"
check_file "scripts/lib/judgment.py"
check_file "scripts/lib/common.py"
check_file "templates/final-report.html"
check_file "tests/test-skill-behavior.sh"

echo ""
echo "2. 配置合法性"
if command -v jq >/dev/null 2>&1; then
    if jq . "$SKILL_DIR/config.json" >/dev/null 2>&1; then
        echo "   ✅ config.json 合法"
    else
        echo "   ❌ config.json 非法"
        FAIL=$((FAIL + 1))
    fi
else
    echo "   ⚠️ 未检测到 jq，跳过"
fi

echo ""
echo "3. 脚本语法"
for script in scripts/run-scan.sh scripts/collect-data.sh scripts/generate-final-report.sh; do
    if bash -n "$SKILL_DIR/$script"; then
        echo "   ✅ $script"
    else
        echo "   ❌ $script"
        FAIL=$((FAIL + 1))
    fi
done
for lib in scan_collect sample_content app_inventory evidence_pack judgment common; do
    if python3 -m py_compile "$SKILL_DIR/scripts/lib/$lib.py" 2>/dev/null; then
        echo "   ✅ scripts/lib/$lib.py"
    else
        echo "   ❌ scripts/lib/$lib.py"
        FAIL=$((FAIL + 1))
    fi
done
rm -rf "$SKILL_DIR/scripts/lib/__pycache__"

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "✅ 快速测试通过"
    exit 0
else
    echo "❌ 快速测试失败: $FAIL 项"
    exit 1
fi
