#!/bin/bash

# Environment Scanner Skill - 完整测试脚本（v3.0.0：证据收集 + AI 判断校验 + 最终报告）

set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

test_pass() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASS++))
}

test_fail() {
    echo -e "${RED}❌ $1${NC}"
    ((FAIL++))
}

test_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARN++))
}

echo "🦞 Environment Scanner Skill - 完整测试"
echo "=================================="
echo ""

echo "1️⃣  文件完整性测试"
echo "-----------------------------------"

files=(
    "SKILL.md"
    "AGENTS.md"
    "CHANGELOG.md"
    "config.json"
    "scripts/collect-data.sh"
    "scripts/collect-data.ps1"
    "scripts/run-scan.sh"
    "scripts/generate-final-report.sh"
    "scripts/lib/common.py"
    "scripts/lib/scan_collect.py"
    "scripts/lib/sample_content.py"
    "scripts/lib/app_inventory.py"
    "scripts/lib/kb_discover.py"
    "scripts/lib/evidence_pack.py"
    "scripts/lib/judgment.py"
    "templates/final-report.html"
    "tests/test-skill.sh"
    "tests/test-skill-behavior.sh"
)

for file in "${files[@]}"; do
    if [ -f "$SKILL_DIR/$file" ]; then
        test_pass "文件存在: $file"
    else
        test_fail "文件缺失: $file"
    fi
done

echo ""
echo "2️⃣  配置与脚本语法测试"
echo "-----------------------------------"

if command -v jq >/dev/null 2>&1; then
    if jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        test_pass "config.json 是合法 JSON"
    else
        test_fail "config.json 非法 JSON"
    fi
else
    test_warn "未安装 jq，跳过 config.json 语法校验"
fi

for script in \
    scripts/collect-data.sh \
    scripts/run-scan.sh \
    scripts/generate-final-report.sh; do
    if bash -n "$SKILL_DIR/$script"; then
        test_pass "脚本语法通过: $script"
    else
        test_fail "脚本语法失败: $script"
    fi
done

PY_OK=1
for lib in common scan_collect sample_content app_inventory kb_discover evidence_pack judgment; do
    if ! python3 -m py_compile "$SKILL_DIR/scripts/lib/$lib.py" 2>/dev/null; then
        PY_OK=0
        test_fail "Python 语法失败: scripts/lib/$lib.py"
    fi
done
if [ "$PY_OK" -eq 1 ]; then
    test_pass "全部 lib 模块 Python 语法通过"
fi
rm -rf "$SKILL_DIR/scripts/lib/__pycache__"

echo ""
echo "3️⃣  采集与证据链集成测试"
echo "-----------------------------------"

TMP_ROOT=$(mktemp -d /tmp/environment-scanner-full-XXXXXX)
INTEG_HOME="$TMP_ROOT/home"
INTEG_DOCS="$TMP_ROOT/docs/市集"
INTEG_APPS="$TMP_ROOT/apps"
mkdir -p "$INTEG_HOME" "$INTEG_DOCS" "$TMP_ROOT/desk" "$TMP_ROOT/down" "$INTEG_APPS/Keynote.app" "$INTEG_APPS/剪映.app"
printf '本周把摊位方案写完，列出还要确认的嘉宾和物料。\n' > "$INTEG_DOCS/活动方案.md"
printf '嘉宾名单已经有十二个人，还差主持人的到场时间。\n' > "$INTEG_DOCS/嘉宾名单.txt"

if env -u ENV_SCANNER_OUTPUT_DIR \
    HOME="$INTEG_HOME" \
    ENV_SCANNER_DOCUMENTS="$TMP_ROOT/docs" \
    ENV_SCANNER_DESKTOP="$TMP_ROOT/desk" \
    ENV_SCANNER_DOWNLOADS="$TMP_ROOT/down" \
    ENV_SCANNER_BOOKS="$TMP_ROOT/desk/missing-books" \
    ENV_SCANNER_HOME="$INTEG_HOME" \
    ENV_SCANNER_DISCOVER_HOME=0 \
    ENV_SCANNER_APPLICATIONS="$INTEG_APPS" \
    bash "$SKILL_DIR/scripts/run-scan.sh" >"$TMP_ROOT/scan.log" 2>&1 \
    && INTEG_EVIDENCE=$(ls "$INTEG_HOME/.environment-scanner/reports/" | grep 'environment-scanner-evidence-.*\.json' | awk 'NR==1{print}') \
    && python3 - "$INTEG_HOME/.environment-scanner/reports/$INTEG_EVIDENCE" <<'PY'
import json, sys
ev = json.load(open(sys.argv[1], encoding="utf-8"))
assert ev["version"] == "4.0.0"
assert ev["scan"]["scan_mode"] == "deep"
names = {item["name"] for item in ev["recent_files"]}
assert {"活动方案.md", "嘉宾名单.txt"} <= names
assert set(ev["apps"]) == {"Keynote", "剪映"}
assert ev["zero_signal"] is False
assert "rejected_documents" in ev and "scan_warnings" in ev
for key in ("structure", "activity_heat", "weekly_counts", "sample_extensions", "ai_usage_signals", "knowledge_bases", "deep_reads"):
    assert key in ev, key
PY
then
    test_pass "run-scan 证据链集成通过（计数+采样+应用+知识库+合并+结构信号）"
else
    test_fail "run-scan 证据链集成失败"
    sed -n '1,60p' "$TMP_ROOT/scan.log" >&2 || true
fi

INTEG_EVIDENCE_PATH="$INTEG_HOME/.environment-scanner/reports/$INTEG_EVIDENCE"

if python3 "$SKILL_DIR/scripts/lib/judgment.py" render "$INTEG_EVIDENCE_PATH" \
        "$SKILL_DIR/templates/final-report.html" "$TMP_ROOT/evidence-page.html" >/dev/null \
    && python3 - "$TMP_ROOT/evidence-page.html" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
for sid in ("profile", "understanding", "charts", "suggestions", "cadence", "priorities", "assets", "advice", "evidence"):
    assert f'id="{sid}"' in html, sid
assert len(re.findall(r"""class\s*=\s*["']suggestion-card["']""", html)) == 0
assert "等待 AI 判断" in html
PY
then
    test_pass "无判断时降级为证据报告（不凑建议）"
else
    test_fail "无判断时降级为证据报告失败"
fi

echo ""
echo "4️⃣  判断质量门禁与渲染合同测试"
echo "-----------------------------------"

python3 - "$TMP_ROOT" <<'PY'
import json, sys, time
tmp = sys.argv[1]
now = int(time.time())
evidence = {
    "version": "4.0.0",
    "scan": {"scan_time": "t", "scan_mode": "deep", "platform": "darwin"},
    "counts": {"obsidian_notes": 2, "ebooks": 40, "desktop_files": 1, "desktop_dirs": 1, "recent_notes_7d": 2},
    "structure": {"top_dirs": [{"name": "市集", "files": 9}], "extensions": [{"extension": ".md", "files": 3}]},
    "recent_files": [
        {"name": "活动方案.md", "parent": "桌面/市集", "parent_name": "市集", "mtime": "2026-10-25 10:00:00", "mtime_epoch": now,
         "extension": ".md", "heading": "周六市集", "excerpt": "本周把摊位方案写完。", "body_skipped": ""},
        {"name": "嘉宾名单.txt", "parent": "桌面/市集", "parent_name": "市集", "mtime": "2026-10-25 09:00:00", "mtime_epoch": now - 10,
         "extension": ".txt", "heading": "", "excerpt": "嘉宾名单已经有十二个人。", "body_skipped": ""},
    ],
    "rejected_documents": [],
    "apps": ["Keynote"],
    "app_count": 1,
    "activity_heat": [{"dir": "市集", "files": 2, "last_active_days": 0.0}],
    "weekly_counts": [{"weeks_ago": 0, "label": "近第1周", "files": 2}],
    "sample_extensions": [{"extension": ".md", "files": 1}],
    "ai_usage_signals": {"marker_files": 0, "file_ratio": 0.0, "markers": {}, "ai_apps": []},
    "knowledge_bases": [], "deep_reads": [], "rejected_deep_reads": [],
    "scan_warnings": [],
    "zero_signal": False,
}
json.dump(evidence, open(f"{tmp}/gate-evidence.json", "w"), ensure_ascii=False)
PY

for case_name in "空字段" "超上限" "坏优先级" "缺诊断" "坏指标"; do
    python3 - "$TMP_ROOT" "$case_name" <<'PY'
import json, sys
tmp, case = sys.argv[1:3]
base = {
    "persona": "novice",
    "diagnosis": {
        "summary": "最大机会是把市集筹备交给 AI。",
        "activities": [{"activity": "周六市集的摊位筹备", "ai_usage": "occasional", "time_note": "近 7 天改了 2 份文件"}],
    },
    "understanding": {
        "activities": [{"text": "正在筹备市集", "basis": [{"name": "活动方案.md"}]}, {"text": "清单手工维护"}],
        "domains": [{"text": "活动筹备"}, {"text": "本地生活"}],
        "work_style": [{"text": "按文件夹组织"}, {"text": "清单式记录"}],
        "structure": [{"text": "市集目录成组"}, {"text": "命名直白"}],
    },
    "suggestions": [{
        "id": "s1", "kind": "basic", "activity": "筹备周六市集", "ai_role": "把零散清单收成一张待办表",
        "first_step": "把《活动方案.md》发给 AI。", "expected_saving": "省时间",
        "quick_win": True, "effort": "low", "reason": "近 7 天有改动",
        "sources": [{"name": "活动方案.md"}], "app_refs": [], "evidence": "",
    }],
    "priorities": [{"id": "s1", "why": "十分钟见效", "how_to_start": ["今天交给 AI"], "long_term": ["清单不再手抄"]}],
    "cadence": {
        "daily": {"summary": "轻量", "items": ["随手记录"]},
        "weekly": {"summary": "对齐", "items": ["核对优先级"]},
        "monthly": {"summary": "复盘", "items": ["归档旧目录"]},
    },
    "assets": [], "structure_advice": [],
    "insufficient_evidence": False,
}
if case == "空字段":
    base["suggestions"][0]["ai_role"] = ""
elif case == "超上限":
    base["suggestions"] = [
        dict(base["suggestions"][0], id=f"s{i}", sources=[{"name": "活动方案.md"}],
             first_step=f"第 {i} 步，把《活动方案.md》发给 AI。")
        for i in range(1, 12)
    ]
    base["priorities"] = [{"id": "s1", "why": "x", "how_to_start": ["y"], "long_term": ["z"]}]
elif case == "坏优先级":
    base["priorities"] = [{"id": "missing", "why": "x", "how_to_start": ["y"], "long_term": ["z"]}]
elif case == "缺诊断":
    del base["diagnosis"]
elif case == "坏指标":
    base["suggestions"][0]["sources"] = [{"type": "metric", "ref": "counts.no_such_metric"}]
json.dump(base, open(f"{tmp}/gate-{case}.json", "w"), ensure_ascii=False)
PY
done

GATE_OK=1
for case_name in "空字段" "超上限" "坏优先级" "缺诊断" "坏指标"; do
    if python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/gate-evidence.json" "$TMP_ROOT/gate-$case_name.json" >/dev/null 2>&1; then
        GATE_OK=0
    fi
done
if [ "$GATE_OK" -eq 1 ]; then
    test_pass "判断门禁拒绝空字段/超上限/坏优先级/缺诊断/坏指标"
else
    test_fail "判断门禁放过了非法判断"
fi

python3 - "$TMP_ROOT/gate-good.json" <<'PY'
import json, sys
json.dump({
    "persona": "novice",
    "diagnosis": {
        "summary": "你还没把市集筹备交给 AI，这是当前最省力的切入点。",
        "activities": [
            {"activity": "周六市集的摊位筹备", "ai_usage": "none", "time_note": "近 7 天改了 2 份文件", "note": "清单还在手工维护"},
        ],
    },
    "understanding": {
        "activities": [{"text": "正在筹备周六市集", "basis": [{"name": "活动方案.md"}]}, {"text": "清单手工维护"}],
        "domains": [{"text": "活动筹备"}, {"text": "本地生活"}],
        "work_style": [{"text": "按文件夹组织"}, {"text": "清单式记录"}],
        "structure": [{"text": "市集目录文件成组"}, {"text": "命名直白"}],
    },
    "suggestions": [
        {"id": "s1", "kind": "basic", "activity": "筹备周六市集的摊位", "ai_role": "把零散清单收成一张待办表",
         "first_step": "把《活动方案.md》和《嘉宾名单.txt》发给 AI，说：请收成一张市集待办表。不要补充文件里没有的事实。",
         "expected_saving": "省掉手工抄清单的半小时", "quick_win": True, "effort": "low",
         "reason": "近 7 天有 2 份文件在改", "sources": [
             {"name": "活动方案.md", "parent": "桌面/市集"},
             {"name": "嘉宾名单.txt", "parent": "桌面/市集"},
         ], "app_refs": ["Keynote"], "evidence": "活动方案.md：周六市集"},
        {"id": "s2", "kind": "basic", "activity": "沉睡书库激活", "ai_role": "按主题归类生成书单",
         "first_step": "跟 AI 说：我有 40 本电子书，请按主题归类出书单。",
         "expected_saving": "激活沉睡资源", "quick_win": False, "effort": "medium",
         "reason": "量大未激活", "sources": [{"type": "metric", "ref": "counts.ebooks"}],
         "app_refs": [], "evidence": ""},
    ],
    "priorities": [
        {"id": "s1", "why": "十分钟就能看到结果",
         "how_to_start": ["今天把两份文件交给 AI 收成待办表", "本周照着待办表推进"],
         "long_term": ["清单不再手工抄", "筹备模板沉淀下来"]},
    ],
    "cadence": {
        "daily": {"summary": "轻量", "items": ["改完文件随手交一次 AI"]},
        "weekly": {"summary": "对齐", "items": ["核对优先级仍成立"]},
        "monthly": {"summary": "复盘", "items": ["归档不再活跃的目录"]},
    },
    "assets": [{"title": "书库", "what": "40 本电子书", "why_valuable": "体量可观",
                "how_to_use": ["按主题出书单"], "basis": [{"type": "metric", "ref": "counts.ebooks"}]}],
    "structure_advice": [{"title": "桌面归档", "detail": "完成的物料按月归档"}],
    "insufficient_evidence": False,
}, open(sys.argv[1], "w"), ensure_ascii=False)
PY

if bash "$SKILL_DIR/scripts/generate-final-report.sh" \
        "$TMP_ROOT/gate-evidence.json" "$TMP_ROOT/gate-good.json" "$TMP_ROOT/gate-final.html" >/dev/null \
    && python3 - "$TMP_ROOT/gate-final.html" "$TMP_ROOT/gate-evidence.json" <<'PY'
import json, re, sys
html = open(sys.argv[1], encoding="utf-8").read()
for sid in ("profile", "understanding", "charts", "suggestions", "cadence", "priorities", "assets", "advice", "evidence"):
    assert f'id="{sid}"' in html, sid
for canvas in ("fileDistChart", "focusRadarChart", "activityTrendChart", "timeAllocationChart"):
    assert canvas in html, canvas
assert 'const CHART_DATA = {"fileDist"' in html
cards = re.findall(r"""class\s*=\s*["']suggestion-card["']""", html)
assert len(cards) == 8, len(cards)  # 2 建议 + 4 理解卡 + 1 资产卡 + 1 结构建议卡
for label in ("AI 能替你做", "第一步", "能省掉", "快见效", "周六市集的摊位筹备", "整体结论", "还没用 AI", "基础用法",
              "为什么最有价值", "如何开始", "长期帮助", "每周协作", "指标 counts.ebooks"):
    assert label in html, label
PY
then
    test_pass "最终报告渲染合同满足（八大区块+图表注入+诊断层+三段式优先级）"
else
    test_fail "最终报告渲染合同失败"
fi

python3 - "$TMP_ROOT/zero-evidence.json" <<'PY'
import json, sys
json.dump({"version": "4.0.0",
           "scan": {"scan_time": "t", "scan_mode": "deep", "platform": "darwin"},
           "counts": {"obsidian_notes": 0, "ebooks": 0, "desktop_files": 0, "desktop_dirs": 0, "recent_notes_7d": 0},
           "recent_files": [], "rejected_documents": [], "apps": [], "app_count": 0,
           "ai_usage_signals": {"marker_files": 0, "file_ratio": 0.0, "markers": {}, "ai_apps": []},
           "knowledge_bases": [], "deep_reads": [], "rejected_deep_reads": [],
           "scan_warnings": [], "zero_signal": True},
          open(sys.argv[1], "w"), ensure_ascii=False)
json.dump({"persona": "novice",
           "diagnosis": {"summary": "证据不足，无法判断你在做什么。", "activities": []},
           "suggestions": [], "priorities": [], "insufficient_evidence": True},
          open(sys.argv[1].replace("zero-evidence", "zero-judgment"), "w"))
PY
if bash "$SKILL_DIR/scripts/generate-final-report.sh" \
        "$TMP_ROOT/zero-evidence.json" "$TMP_ROOT/zero-judgment.json" "$TMP_ROOT/zero-final.html" >/dev/null \
    && python3 - "$TMP_ROOT/zero-final.html" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
assert len(re.findall(r"""class\s*=\s*["']suggestion-card["']""", html)) == 0
assert "证据不足" in html
PY
then
    test_pass "零信号端到端：空判断通过校验且页面写明证据不足"
else
    test_fail "零信号端到端失败"
fi

rm -rf "$TMP_ROOT"

echo ""
echo "5️⃣  行为回归"
echo "-----------------------------------"
if bash "$SKILL_DIR/tests/test-skill-behavior.sh"; then
    test_pass "行为测试脚本通过"
else
    test_fail "行为测试脚本失败"
fi

echo ""
echo "=================================="
echo "📊 测试结果汇总"
echo "=================================="
echo -e "${GREEN}通过: $PASS${NC}"
echo -e "${RED}失败: $FAIL${NC}"
echo -e "${YELLOW}警告: $WARN${NC}"

if [ "$FAIL" -eq 0 ]; then
    echo -e "\n${GREEN}✅ 完整测试通过${NC}"
    exit 0
else
    echo -e "\n${RED}❌ 有 $FAIL 个测试失败${NC}"
    exit 1
fi
