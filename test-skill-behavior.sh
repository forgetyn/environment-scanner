#!/bin/bash

# Environment Scanner - 行为回归（v3.0.0）
# 夹具都在临时目录，不扫描开发者的真实主目录。

set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0
TMP_ROOT="$(mktemp -d /tmp/environment-scanner-behavior-XXXXXX)"

cleanup() {
    chmod -R u+rwx "$TMP_ROOT" 2>/dev/null || true
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    echo "✅ $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "❌ $1"
    FAIL=$((FAIL + 1))
}

scan_env() {
    local docs="$1"
    local desktop="$2"
    local downloads="$3"
    local books="$4"
    local output="$5"
    local mode="$6"
    local hostname="${7:-}"
    env \
        ENV_SCANNER_DOCUMENTS="$docs" \
        ENV_SCANNER_DESKTOP="$desktop" \
        ENV_SCANNER_DOWNLOADS="$downloads" \
        ENV_SCANNER_BOOKS="$books" \
        ENV_SCANNER_HOSTNAME_OVERRIDE="$hostname" \
        ENV_SCANNER_HOME="$TMP_ROOT" \
        ENV_SCANNER_DISCOVER_HOME=0 \
        bash "$SKILL_DIR/scripts/collect-data.sh" "$output" "$mode"
}

echo "行为回归"
echo "-----------------------------------"

# 行为 01 计数不被扫描模式截断
COUNT_DOCS="$TMP_ROOT/count-docs"
COUNT_DESK="$TMP_ROOT/count-desk"
COUNT_DOWN="$TMP_ROOT/count-down"
mkdir -p "$COUNT_DOCS" "$COUNT_DESK" "$COUNT_DOWN"
for i in $(seq 1 60); do
    echo "note $i" > "$COUNT_DOCS/note-$i.md"
done
QUICK_JSON="$TMP_ROOT/quick.json"
DEEP_JSON="$TMP_ROOT/deep.json"
if scan_env "$COUNT_DOCS" "$COUNT_DESK" "$COUNT_DOWN" "$COUNT_DESK/missing-books" "$QUICK_JSON" quick >/dev/null \
    && scan_env "$COUNT_DOCS" "$COUNT_DESK" "$COUNT_DOWN" "$COUNT_DESK/missing-books" "$DEEP_JSON" deep >/dev/null \
    && python3 - "$QUICK_JSON" "$DEEP_JSON" <<'PY'
import json, sys
quick, deep = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:]]
assert quick["files"]["obsidian_notes"] == 60
assert deep["files"]["obsidian_notes"] == 60
assert quick["files"] == deep["files"]
assert quick["scan_mode"] == "quick"
assert deep["scan_mode"] == "deep"
PY
then
    pass "行为01 计数不被扫描模式截断"
else
    fail "行为01 计数不被扫描模式截断"
fi

# 行为 02 敏感路径
SENS_DOCS="$TMP_ROOT/sens-docs"
mkdir -p "$SENS_DOCS/Keyboard" "$SENS_DOCS/wallet" "$COUNT_DESK"
printf 'k' > "$SENS_DOCS/Keyboard/a.md"
printf 'p' > "$SENS_DOCS/plain.md"
python3 -c 'open("'"$SENS_DOCS"'/wallet/secret.bin","wb").write(b"x"*4096)'
printf 'hidden' > "$SENS_DOCS/wallet/hidden.md"
printf 'env' > "$SENS_DOCS/.env"
printf 'key' > "$SENS_DOCS/id_rsa"
SENS_JSON="$TMP_ROOT/sens.json"
if scan_env "$SENS_DOCS" "$COUNT_DESK" "$COUNT_DOWN" "$COUNT_DESK/missing-books" "$SENS_JSON" standard >/dev/null \
    && python3 - "$SENS_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["files"]["obsidian_notes"] == 2
assert data["storage_bytes"]["documents"] == 2
assert not any("wallet" in item for item in data.get("scan_warnings", []))
PY
then
    pass "行为02 敏感路径不计入，Keyboard 下的 Markdown 计入"
else
    fail "行为02 敏感路径不计入，Keyboard 下的 Markdown 计入"
fi

# 行为 03 根目录不可读
LOCKED_ROOT="$TMP_ROOT/locked-root"
mkdir -p "$LOCKED_ROOT" "$COUNT_DESK" "$COUNT_DOWN"
echo x > "$LOCKED_ROOT/a.md"
LOCKED_OUT="$TMP_ROOT/locked-root.json"
LOCKED_LOG="$TMP_ROOT/locked-root.log"
chmod 000 "$LOCKED_ROOT"
set +e
scan_env "$LOCKED_ROOT" "$COUNT_DESK" "$COUNT_DOWN" "$COUNT_DESK/missing-books" "$LOCKED_OUT" standard >"$LOCKED_LOG" 2>&1
LOCKED_CODE=$?
set -e
chmod 755 "$LOCKED_ROOT" 2>/dev/null || true
if [ "$LOCKED_CODE" -ne 0 ] && [ ! -f "$LOCKED_OUT" ] && grep -q "不可读" "$LOCKED_LOG"; then
    pass "行为03 根目录不可读时失败且不写输出"
else
    fail "行为03 根目录不可读时失败且不写输出"
fi

# 行为 04 子目录不可读
NESTED="$TMP_ROOT/nested-docs"
mkdir -p "$NESTED/locked" "$NESTED/visible"
echo visible > "$NESTED/visible/ok.md"
echo secret > "$NESTED/locked/secret.md"
chmod 000 "$NESTED/locked"
NESTED_OUT="$TMP_ROOT/nested.json"
set +e
scan_env "$NESTED" "$COUNT_DESK" "$COUNT_DOWN" "$COUNT_DESK/missing-books" "$NESTED_OUT" standard >/dev/null 2>&1
NESTED_CODE=$?
set -e
chmod 755 "$NESTED/locked" 2>/dev/null || true
if [ "$NESTED_CODE" -eq 0 ] && python3 - "$NESTED_OUT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["files"]["obsidian_notes"] == 1
assert any("locked" in item for item in data.get("scan_warnings", []))
PY
then
    pass "行为04 子目录不可读时跳过并记录警告"
else
    fail "行为04 子目录不可读时跳过并记录警告"
fi

# 行为 05 JSON 注入
HOST_OUT="$TMP_ROOT/host.json"
if scan_env "$COUNT_DOCS" "$COUNT_DESK" "$COUNT_DOWN" "$COUNT_DESK/missing-books" "$HOST_OUT" standard 'a"b' >/dev/null \
    && python3 - "$HOST_OUT" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["system"]["hostname"] == 'a"b'
assert data["system"]["username"] == os.environ["USER"]
PY
then
    pass "行为05 主机名引号不会写坏 JSON"
else
    fail "行为05 主机名引号不会写坏 JSON"
fi

# 行为 06 不读死个人文档
if ! grep -rq "个人情况总结" "$SKILL_DIR/scripts/run-scan.sh" "$SKILL_DIR/scripts/lib/" \
    && ! grep -rqE "\"/Users/|'/Users/" "$SKILL_DIR/scripts/run-scan.sh" "$SKILL_DIR/scripts/lib/"; then
    pass "行为06 不读取写死的个人文档"
else
    fail "行为06 不读取写死的个人文档"
fi

# 行为 07 证据包合并
EV_DATA="$TMP_ROOT/ev-data.json"
EV_SAMPLES="$TMP_ROOT/ev-samples.json"
EV_APPS="$TMP_ROOT/ev-apps.json"
EV_KB="$TMP_ROOT/ev-kb.json"
EV_EMPTY_SAMPLES="$TMP_ROOT/ev-empty-samples.json"
EV_EMPTY_APPS="$TMP_ROOT/ev-empty-apps.json"
EV_OUT="$TMP_ROOT/ev-evidence.json"
EV_ZERO_OUT="$TMP_ROOT/ev-zero.json"
python3 - "$EV_DATA" "$EV_SAMPLES" "$EV_APPS" "$EV_KB" "$EV_EMPTY_SAMPLES" "$EV_EMPTY_APPS" <<'PY'
import json, sys, time
data_path, samples_path, apps_path, kb_path, empty_samples, empty_apps = sys.argv[1:7]
now = int(time.time())
json.dump({"scan_time": "t", "scan_mode": "standard", "platform": "darwin",
           "files": {"obsidian_notes": 3, "ebooks": 1, "desktop_dirs": 1, "desktop_files": 2, "recent_notes_7d": 2},
           "storage": {"documents": "1K"}, "scan_warnings": ["w1"],
           "structure": {"top_dirs": [{"name": "市集", "files": 5}], "extensions": [{"extension": ".md", "files": 3}]}},
          open(data_path, "w"))
json.dump({"recent_days": 30,
           "files": [
               {"name": "活动方案.md", "parent": "桌面/市集", "parent_name": "市集", "mtime": "2026-10-25 10:00:00",
                "mtime_epoch": now, "extension": ".md", "heading": "AI 周报", "excerpt": "本周用 AI 把摊位方案写完。", "body_skipped": ""},
               {"name": "嘉宾名单.txt", "parent": "桌面/市集", "parent_name": "市集", "mtime": "2026-10-25 09:00:00",
                "mtime_epoch": now - 3600, "extension": ".txt", "heading": "", "excerpt": "嘉宾名单已经有十二个人。", "body_skipped": ""},
           ],
           "rejected_documents": [{"path": "/tmp/secret.md", "reason": "private_key"}],
           "scan_warnings": ["w2"]},
          open(samples_path, "w"), ensure_ascii=False)
json.dump({"apps": ["Keynote", "ChatGPT"], "app_count": 2, "sources": ["/Applications"], "scan_warnings": []},
          open(apps_path, "w"), ensure_ascii=False)
json.dump({"knowledge_bases": [{"app": "obsidian", "path": "/tmp/Vault", "notes": 10, "recent_notes_7d": 2,
                                "top_dirs": [], "journals": []}],
           "deep_reads": [{"name": "个人画像.md", "path": "/tmp/Vault/个人画像.md", "vault": "Vault",
                           "mtime": "2026-10-25 08:00:00", "line_count": 20, "text": "画像内容。"}],
           "rejected_deep_reads": [], "scan_warnings": ["w3"]},
          open(kb_path, "w"), ensure_ascii=False)
json.dump({"recent_days": 30, "files": [], "rejected_documents": [], "scan_warnings": []},
          open(empty_samples, "w"))
json.dump({"apps": [], "app_count": 0, "sources": [], "scan_warnings": []},
          open(empty_apps, "w"))
PY
if python3 "$SKILL_DIR/scripts/lib/evidence_pack.py" --data "$EV_DATA" --samples "$EV_SAMPLES" --apps "$EV_APPS" --kb "$EV_KB" --output "$EV_OUT" >/dev/null \
    && python3 "$SKILL_DIR/scripts/lib/evidence_pack.py" --data "$EV_DATA" --samples "$EV_EMPTY_SAMPLES" --apps "$EV_EMPTY_APPS" --output "$EV_ZERO_OUT" >/dev/null \
    && python3 - "$EV_OUT" "$EV_ZERO_OUT" <<'PY'
import json, sys
ev, zero = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:3]]
assert ev["counts"]["obsidian_notes"] == 3
assert [f["name"] for f in ev["recent_files"]] == ["活动方案.md", "嘉宾名单.txt"]
assert ev["apps"] == ["Keynote", "ChatGPT"]
assert ev["zero_signal"] is False
assert ev["scan_warnings"] == ["w1", "w2", "w3"]
assert ev["rejected_documents"] == [{"path": "/tmp/secret.md", "reason": "private_key"}]
assert zero["zero_signal"] is True
assert ev["structure"]["top_dirs"] == [{"name": "市集", "files": 5}]
heat = {item["dir"]: item for item in ev["activity_heat"]}
assert heat["市集"]["files"] == 2
assert ev["weekly_counts"] and ev["weekly_counts"][0]["weeks_ago"] == 0
assert len(ev["weekly_counts"]) <= 26
signals = ev["ai_usage_signals"]
assert signals["marker_files"] == 1
assert signals["file_ratio"] > 0
assert "AI" in signals["markers"]
assert signals["ai_apps"] == ["ChatGPT"]
assert zero["ai_usage_signals"]["marker_files"] == 0
assert ev["knowledge_bases"][0]["app"] == "obsidian"
assert ev["deep_reads"][0]["name"] == "个人画像.md"
assert zero["knowledge_bases"] == [] and zero["deep_reads"] == []
PY
then
    pass "行为07 证据包正确合并计数、样本、应用、知识库、结构信号与零信号"
else
    fail "行为07 证据包正确合并计数、样本、应用、知识库、结构信号与零信号"
fi

# 行为 08 零信号不允许生成建议
python3 - "$TMP_ROOT" <<'PY'
import json, sys
tmp = sys.argv[1]
json.dump({"zero_signal": True, "recent_files": [], "apps": []},
          open(f"{tmp}/zero-evidence.json", "w"))
json.dump({"persona": "novice",
           "diagnosis": {"summary": "证据不足，无法判断你在做什么。", "activities": []},
           "suggestions": [], "priorities": [], "insufficient_evidence": True},
          open(f"{tmp}/zero-good.json", "w"))
json.dump({"suggestions": [{"id": "s1", "activity": "x", "ai_role": "x", "first_step": "x.md",
                            "expected_saving": "x", "quick_win": True, "effort": "low", "reason": "x",
                            "sources": [{"name": "x.md"}]}],
           "priorities": [{"id": "s1", "why": "x"}], "insufficient_evidence": False},
          open(f"{tmp}/zero-bad.json", "w"))
PY
if python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/zero-evidence.json" "$TMP_ROOT/zero-good.json" >/dev/null \
    && { python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/zero-evidence.json" "$TMP_ROOT/zero-bad.json" >/dev/null 2>&1; [ $? -eq 1 ]; }; then
    pass "行为08 零信号时强制空建议，硬凑建议被拒绝"
else
    fail "行为08 零信号时强制空建议，硬凑建议被拒绝"
fi

# 行为 09 判断校验矩阵：引用必须真实、落地、可排序
python3 - "$TMP_ROOT" <<'PY'
import json, sys, time
tmp = sys.argv[1]
now = int(time.time())
evidence = {
    "version": "3.0.0",
    "scan": {"scan_time": "t", "scan_mode": "deep", "platform": "darwin"},
    "counts": {"obsidian_notes": 2, "ebooks": 0, "desktop_files": 1, "desktop_dirs": 1, "recent_notes_7d": 2},
    "recent_files": [
        {"name": "活动方案.md", "parent": "桌面/市集", "mtime": "2026-10-25 10:00:00", "mtime_epoch": now,
         "extension": ".md", "heading": "周六市集", "excerpt": "本周把摊位方案写完。", "body_skipped": ""},
        {"name": "嘉宾名单.txt", "parent": "桌面/市集", "mtime": "2026-10-25 09:00:00", "mtime_epoch": now - 10,
         "extension": ".txt", "heading": "", "excerpt": "嘉宾名单已经有十二个人。", "body_skipped": ""},
    ],
    "rejected_documents": [],
    "apps": ["Keynote"],
    "app_count": 1,
    "scan_warnings": [],
    "zero_signal": False,
}
def judgment(sources, first_step="把《活动方案.md》交给 AI。", priorities=None, quick_win=True, kind="basic"):
    return {
        "persona": "novice",
        "diagnosis": {
            "summary": "最大机会是把市集筹备清单交给 AI。",
            "activities": [{"activity": "周六市集的摊位筹备", "ai_usage": "occasional",
                            "time_note": "近 7 天改了 2 份文件"}],
        },
        "understanding": {
            "activities": [{"text": "正在筹备周六市集", "basis": [{"name": "活动方案.md"}]},
                           {"text": "清单还在手工维护"}],
            "domains": [{"text": "活动筹备"}, {"text": "本地生活"}],
            "work_style": [{"text": "按文件夹组织事务"}, {"text": "偏好清单式记录"}],
            "structure": [{"text": "市集目录文件成组"}, {"text": "命名直白"}],
        },
        "suggestions": [{
            "id": "s1", "kind": kind, "activity": "筹备周六市集", "ai_role": "把零散清单收成一张待办表",
            "first_step": first_step, "expected_saving": "省掉手工整理", "quick_win": quick_win,
            "effort": "low", "reason": "近 7 天有改动", "sources": sources,
            "app_refs": [], "evidence": "活动方案.md：周六市集",
        }],
        "priorities": priorities if priorities is not None else [
            {"id": "s1", "why": "十分钟见效", "how_to_start": ["今天把文件交给 AI"], "long_term": ["清单不再手工抄"]},
        ],
        "cadence": {
            "daily": {"summary": "轻量", "items": ["改完文件随手交一次 AI"]},
            "weekly": {"summary": "对齐", "items": ["核对优先级仍成立"]},
            "monthly": {"summary": "复盘", "items": ["清理不再活跃的目录"]},
        },
        "assets": [],
        "structure_advice": [],
        "insufficient_evidence": False,
    }
json.dump(evidence, open(f"{tmp}/mx-evidence.json", "w"), ensure_ascii=False)
json.dump(judgment([{"name": "活动方案.md"}]), open(f"{tmp}/mx-good.json", "w"), ensure_ascii=False)
json.dump(judgment([{"name": "不存在.md"}]), open(f"{tmp}/mx-bad-source.json", "w"), ensure_ascii=False)
json.dump(judgment([{"name": "活动方案.md"}], first_step="随便做点什么。"), open(f"{tmp}/mx-bad-step.json", "w"), ensure_ascii=False)
json.dump(judgment([{"name": "活动方案.md"}], priorities=[{"id": "sX", "why": "x"}]), open(f"{tmp}/mx-bad-prio.json", "w"), ensure_ascii=False)
json.dump(judgment([{"name": "活动方案.md"}], quick_win=False), open(f"{tmp}/mx-good-slow.json", "w"), ensure_ascii=False)
PY
MX_OK=0
python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/mx-evidence.json" "$TMP_ROOT/mx-good.json" >/dev/null || MX_OK=1
for bad in mx-bad-source mx-bad-step mx-bad-prio; do
    if python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/mx-evidence.json" "$TMP_ROOT/$bad.json" >/dev/null 2>&1; then
        MX_OK=1
    fi
done
python3 - "$TMP_ROOT/mx-bad-source.json" <<'PY'
import json, sys
bad = json.load(open(sys.argv[1], encoding="utf-8"))
bad["suggestions"][0]["app_refs"] = ["剪映"]
json.dump(bad, open(sys.argv[1], "w"), ensure_ascii=False)
PY
if python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/mx-evidence.json" "$TMP_ROOT/mx-bad-source.json" >/dev/null 2>&1; then
    MX_OK=1
fi
if [ "$MX_OK" -eq 0 ]; then
    pass "行为09 判断必须引用真实文件且提示词落地，坏引用全部被拒"
else
    fail "行为09 判断必须引用真实文件且提示词落地，坏引用全部被拒"
fi

# 行为 10 quick 不读正文且 standard 读到摘录
QUICK_SAMPLES="$TMP_ROOT/quick-samples.json"
STANDARD_SAMPLES="$TMP_ROOT/standard-samples.json"
if env ENV_SCANNER_DOCUMENTS="$COUNT_DOCS" ENV_SCANNER_DESKTOP="$COUNT_DESK" \
    ENV_SCANNER_DOWNLOADS="$COUNT_DOWN" ENV_SCANNER_BOOKS="$COUNT_DESK/missing-books" \
    ENV_SCANNER_HOME="$TMP_ROOT" ENV_SCANNER_DISCOVER_HOME=0 \
    python3 "$SKILL_DIR/scripts/lib/sample_content.py" --output "$QUICK_SAMPLES" --mode quick >/dev/null \
    && env ENV_SCANNER_DOCUMENTS="$COUNT_DOCS" ENV_SCANNER_DESKTOP="$COUNT_DESK" \
    ENV_SCANNER_DOWNLOADS="$COUNT_DOWN" ENV_SCANNER_BOOKS="$COUNT_DESK/missing-books" \
    ENV_SCANNER_HOME="$TMP_ROOT" ENV_SCANNER_DISCOVER_HOME=0 \
    python3 "$SKILL_DIR/scripts/lib/sample_content.py" --output "$STANDARD_SAMPLES" --mode standard >/dev/null \
    && python3 - "$QUICK_SAMPLES" "$STANDARD_SAMPLES" <<'PY'
import json, sys
quick, standard = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:3]]
assert quick["files"] and standard["files"]
assert all(not item.get("excerpt") for item in quick["files"])
assert any("note " in item.get("excerpt", "") for item in standard["files"])
PY
then
    pass "行为10 quick 不读正文且 standard 读到摘录"
else
    fail "行为10 quick 不读正文且 standard 读到摘录"
fi

# 行为 11 私钥正文在采样层被拒绝
SECRET_ROOT="$TMP_ROOT/secret-docs"
mkdir -p "$SECRET_ROOT/周报" "$TMP_ROOT/secret-empty-desk" "$TMP_ROOT/secret-empty-down" "$TMP_ROOT/secret-empty-books"
printf 'BEGIN OPENSSH PRIVATE KEY\n正常句子不应该留下来。\n' > "$SECRET_ROOT/周报/secret.md"
printf '这是一份可以交给别人看的周报，里面写了这周要完成的三件具体事情，还要确认谁来收尾。\n' > "$SECRET_ROOT/周报/normal.md"
SECRET_SAMPLES="$TMP_ROOT/secret-samples.json"
if env ENV_SCANNER_DOCUMENTS="$SECRET_ROOT" ENV_SCANNER_DESKTOP="$TMP_ROOT/secret-empty-desk" \
    ENV_SCANNER_DOWNLOADS="$TMP_ROOT/secret-empty-down" ENV_SCANNER_BOOKS="$TMP_ROOT/secret-empty-books" \
    ENV_SCANNER_HOME="$TMP_ROOT" ENV_SCANNER_DISCOVER_HOME=0 \
    python3 "$SKILL_DIR/scripts/lib/sample_content.py" --output "$SECRET_SAMPLES" --mode standard >/dev/null \
    && python3 - "$SECRET_SAMPLES" <<'PY'
import json, sys
samples = json.load(open(sys.argv[1], encoding="utf-8"))
blob = json.dumps(samples, ensure_ascii=False)
assert "BEGIN OPENSSH PRIVATE KEY" not in blob
assert any(item["reason"] == "private_key" for item in samples["rejected_documents"])
names = [item["name"] for item in samples["files"]]
assert "normal.md" in names and "secret.md" not in names
PY
then
    pass "行为11 私钥文档被拒绝且正文不进入样本"
else
    fail "行为11 私钥文档被拒绝且正文不进入样本"
fi

# 行为 12 主目录发现能看到四个根以外的文件，并跳过 .ssh
DISCOVER_HOME="$TMP_ROOT/discover-home"
mkdir -p "$DISCOVER_HOME/work" "$DISCOVER_HOME/.ssh" \
    "$TMP_ROOT/discover-docs" "$TMP_ROOT/discover-desk" "$TMP_ROOT/discover-down"
printf '活动签到表已经发给摊主，还要确认晚上的收摊时间。\n' > "$DISCOVER_HOME/work/outside.txt"
printf '不应该被读到\n' > "$DISCOVER_HOME/.ssh/hidden.txt"
DISCOVER_SAMPLES="$TMP_ROOT/discover-samples.json"
if env ENV_SCANNER_DOCUMENTS="$TMP_ROOT/discover-docs" ENV_SCANNER_DESKTOP="$TMP_ROOT/discover-desk" \
    ENV_SCANNER_DOWNLOADS="$TMP_ROOT/discover-down" ENV_SCANNER_BOOKS="$TMP_ROOT/discover-desk/missing-books" \
    ENV_SCANNER_HOME="$DISCOVER_HOME" ENV_SCANNER_DISCOVER_HOME=1 \
    python3 "$SKILL_DIR/scripts/lib/sample_content.py" --output "$DISCOVER_SAMPLES" --mode standard >/dev/null \
    && python3 - "$DISCOVER_SAMPLES" <<'PY'
import json, sys
samples = json.load(open(sys.argv[1], encoding="utf-8"))
names = [item["name"] for item in samples["files"]]
blob = json.dumps(samples, ensure_ascii=False)
assert "outside.txt" in names
assert "hidden.txt" not in names
assert ".ssh" not in blob
PY
then
    pass "行为12 主目录发现跳过 .ssh"
else
    fail "行为12 主目录发现跳过 .ssh"
fi

# 行为 13 旧书籍目录不会变成活动信号
OLD_BOOKS="$TMP_ROOT/old-books"
mkdir -p "$OLD_BOOKS" "$TMP_ROOT/old-docs" "$TMP_ROOT/old-desk" "$TMP_ROOT/old-down" "$TMP_ROOT/old-empty-apps"
python3 - "$OLD_BOOKS" <<'PY'
import os, sys, time
from pathlib import Path
root = Path(sys.argv[1])
old = time.time() - 400 * 86400
for index in range(198):
    path = root / f"book-{index}.pdf"
    path.write_bytes(b"%PDF-1.1")
    os.utime(path, (old, old))
PY
OLD_SAMPLES="$TMP_ROOT/old-samples.json"
if env ENV_SCANNER_DOCUMENTS="$TMP_ROOT/old-docs" ENV_SCANNER_DESKTOP="$TMP_ROOT/old-desk" \
    ENV_SCANNER_DOWNLOADS="$TMP_ROOT/old-down" ENV_SCANNER_BOOKS="$OLD_BOOKS" \
    ENV_SCANNER_HOME="$TMP_ROOT" ENV_SCANNER_DISCOVER_HOME=0 \
    python3 "$SKILL_DIR/scripts/lib/sample_content.py" --output "$OLD_SAMPLES" --mode standard >/dev/null \
    && python3 - "$OLD_SAMPLES" <<'PY'
import json, sys
samples = json.load(open(sys.argv[1], encoding="utf-8"))
assert samples["files"] == []
PY
then
    pass "行为13 旧书籍不会进入近期样本"
else
    fail "行为13 旧书籍不会进入近期样本"
fi

# 行为 14 发现预算到顶后仍保留已采样文件
BUDGET_HOME="$TMP_ROOT/budget-home"
mkdir -p "$BUDGET_HOME/a" "$BUDGET_HOME/m/d1/d2/d3" \
    "$TMP_ROOT/budget-docs" "$TMP_ROOT/budget-desk" "$TMP_ROOT/budget-down"
printf '已经写好的签到说明，内容足够单独留下来。\n' > "$BUDGET_HOME/a/note.txt"
printf '太深\n' > "$BUDGET_HOME/m/d1/d2/d3/deep.txt"
BUDGET_SAMPLES="$TMP_ROOT/budget-samples.json"
if env ENV_SCANNER_DOCUMENTS="$TMP_ROOT/budget-docs" ENV_SCANNER_DESKTOP="$TMP_ROOT/budget-desk" \
    ENV_SCANNER_DOWNLOADS="$TMP_ROOT/budget-down" ENV_SCANNER_BOOKS="$TMP_ROOT/budget-desk/missing-books" \
    ENV_SCANNER_HOME="$BUDGET_HOME" ENV_SCANNER_DISCOVER_HOME=1 ENV_SCANNER_SAMPLE_DIR_BUDGET=2 \
    python3 "$SKILL_DIR/scripts/lib/sample_content.py" --output "$BUDGET_SAMPLES" --mode standard >/dev/null \
    && python3 - "$BUDGET_SAMPLES" <<'PY'
import json, sys
samples = json.load(open(sys.argv[1], encoding="utf-8"))
names = [item["name"] for item in samples["files"]]
assert "note.txt" in names
assert "deep.txt" not in names
assert "sample_budget_reached" in samples["scan_warnings"]
PY
then
    pass "行为14 发现预算到顶仍写出已采样文件"
else
    fail "行为14 发现预算到顶仍写出已采样文件"
fi

# 行为 15 应用清单只收一级名字
APPS_F1="$TMP_ROOT/apps-f1"
APPS_F2="$TMP_ROOT/apps-f2"
mkdir -p "$APPS_F1/Keynote.app/Contents" "$APPS_F1/剪映.app" "$APPS_F1/Microsoft Excel" "$APPS_F1/.Hidden.app" "$APPS_F2/keynote.app"
echo x > "$APPS_F1/README.txt"
APPS_OUT="$TMP_ROOT/apps-out.json"
if env ENV_SCANNER_APPLICATIONS="$APPS_F1:$APPS_F2" \
    python3 "$SKILL_DIR/scripts/lib/app_inventory.py" --output "$APPS_OUT" >/dev/null \
    && python3 - "$APPS_OUT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["apps"] == ["Keynote", "Microsoft Excel", "剪映"], data["apps"]
assert data["app_count"] == 3
blob = json.dumps(data, ensure_ascii=False)
assert "Contents" not in blob and "README" not in blob
assert "keynote.app" not in blob
PY
then
    pass "行为15 应用清单只收一级名字并去重"
else
    fail "行为15 应用清单只收一级名字并去重"
fi

# 行为 16 全链路产物完整且默认深度为 deep
STAMP="$TMP_ROOT/stamp"
touch "$STAMP"
HOME_DIR="$TMP_ROOT/home"
RUN_DOCS="$TMP_ROOT/run-docs"
RUN_DESK="$TMP_ROOT/run-desk"
RUN_DOWN="$TMP_ROOT/run-down"
RUN_APPS="$TMP_ROOT/run-apps"
mkdir -p "$HOME_DIR" "$RUN_DOCS/市集" "$RUN_DESK" "$RUN_DOWN" "$RUN_APPS/Keynote.app"
printf '本周把摊位方案写完，列出还要确认的嘉宾和物料。\n' > "$RUN_DOCS/市集/活动方案.md"
RUN_LOG="$TMP_ROOT/run.log"
if env -u ENV_SCANNER_OUTPUT_DIR \
    HOME="$HOME_DIR" \
    ENV_SCANNER_DOCUMENTS="$RUN_DOCS" \
    ENV_SCANNER_DESKTOP="$RUN_DESK" \
    ENV_SCANNER_DOWNLOADS="$RUN_DOWN" \
    ENV_SCANNER_BOOKS="$RUN_DESK/missing-books" \
    ENV_SCANNER_HOME="$HOME_DIR" \
    ENV_SCANNER_DISCOVER_HOME=0 \
    ENV_SCANNER_APPLICATIONS="$RUN_APPS" \
    bash "$SKILL_DIR/scripts/run-scan.sh" >"$RUN_LOG" 2>&1 \
    && [ -d "$HOME_DIR/.environment-scanner/reports" ] \
    && ls "$HOME_DIR/.environment-scanner/reports/" | grep -q 'environment-scanner-evidence-report-.*\.html' \
    && ls "$HOME_DIR/.environment-scanner/reports/" | grep -q 'environment-scanner-evidence-.*\.json' \
    && ls "$HOME_DIR/.environment-scanner/reports/" | grep -q 'environment-scanner-apps-.*\.json' \
    && ls "$HOME_DIR/.environment-scanner/reports/" | grep -q 'environment-scanner-kb-.*\.json' \
    && [ -z "$(find "$SKILL_DIR/examples/report" -type f -newer "$STAMP" 2>/dev/null)" ] \
    && grep -q "扫描模式: deep" "$RUN_LOG"; then
    pass "行为16 新扫描写入用户目录、产物完整且默认 deep"
else
    fail "行为16 新扫描写入用户目录、产物完整且默认 deep"
    sed -n '1,80p' "$RUN_LOG" >&2 || true
fi

# 行为 17 判断→校验→最终报告链路与渲染合同
RUN_EVIDENCE=$(ls "$HOME_DIR/.environment-scanner/reports/" | grep 'environment-scanner-evidence-.*\.json' | awk 'NR==1{print}')
RUN_EVIDENCE_PATH="$HOME_DIR/.environment-scanner/reports/$RUN_EVIDENCE"
RUN_JUDGMENT="$HOME_DIR/.environment-scanner/reports/environment-scanner-judgment-test.json"
RUN_FINAL="$HOME_DIR/.environment-scanner/reports/environment-scanner-final-test.html"
python3 - "$RUN_EVIDENCE_PATH" "$RUN_JUDGMENT" <<'PY'
import json, sys
evidence_name, judgment_path = sys.argv[1:]
evidence = json.load(open(evidence_name, encoding="utf-8"))
names = [item["name"] for item in evidence["recent_files"]]
assert "活动方案.md" in names
json.dump({
    "persona": "novice",
    "diagnosis": {
        "summary": "最大机会是把市集筹备清单交给 AI 整理。",
        "activities": [{"activity": "周六市集的摊位筹备", "ai_usage": "none",
                        "time_note": "近 7 天改了 1 份文件", "note": "名单还在手工维护"}],
    },
    "understanding": {
        "activities": [{"text": "正在筹备周六市集", "basis": [{"name": "活动方案.md"}]},
                       {"text": "物料与嘉宾分散在两份文件里"}],
        "domains": [{"text": "活动筹备"}, {"text": "本地市集"}],
        "work_style": [{"text": "按文件夹组织事务"}, {"text": "清单式记录"}],
        "structure": [{"text": "市集目录文件成组"}, {"text": "命名直白"}],
    },
    "suggestions": [{
        "id": "s1", "kind": "basic", "activity": "筹备周六市集的摊位",
        "ai_role": "把零散清单收成一张待办表",
        "first_step": "把《活动方案.md》发给 AI，说：请把它收成一张待办表。不要补充文件里没有的事实。",
        "expected_saving": "省掉手工抄清单的半小时", "quick_win": True, "effort": "low",
        "reason": "近 7 天有改动", "sources": [{"name": "活动方案.md", "parent": "市集"}],
        "app_refs": ["Keynote"], "evidence": "活动方案.md",
    }],
    "priorities": [{"id": "s1", "why": "十分钟就能看到结果",
                    "how_to_start": ["今天把《活动方案.md》交给 AI 收成待办表"],
                    "long_term": ["清单不再手工抄"]}],
    "cadence": {
        "daily": {"summary": "轻量", "items": ["改完文件随手交一次 AI"]},
        "weekly": {"summary": "对齐", "items": ["核对优先级仍成立"]},
        "monthly": {"summary": "复盘", "items": ["归档不再活跃的目录"]},
    },
    "assets": [],
    "structure_advice": [],
    "insufficient_evidence": False,
}, open(judgment_path, "w"), ensure_ascii=False)
PY
if bash "$SKILL_DIR/scripts/generate-final-report.sh" \
        "$RUN_EVIDENCE_PATH" "$RUN_JUDGMENT" "$RUN_FINAL" >/dev/null \
    && python3 - "$RUN_FINAL" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
for sid in ("profile", "understanding", "charts", "suggestions", "cadence", "priorities", "assets", "advice", "evidence"):
    assert f'id="{sid}"' in html, sid
for canvas in ("fileDistChart", "focusRadarChart", "activityTrendChart", "timeAllocationChart"):
    assert canvas in html, canvas
assert 'const CHART_DATA = {"fileDist"' in html
cards = re.findall(r"""class\s*=\s*["']suggestion-card["']""", html)
assert len(cards) == 5, len(cards)  # 1 建议卡 + 4 整体理解卡
for label in ("AI 能替你做", "第一步", "能省掉", "快见效", "Keynote", "为什么最有价值", "如何开始", "长期帮助", "每周协作"):
    assert label in html, label
PY
then
    pass "行为17 判断校验通过后渲染完整结构报告"
else
    fail "行为17 判断校验通过后渲染完整结构报告"
fi

# 行为 18 全流程不出站
OUTBOUND=0
for target in "$SKILL_DIR/scripts/run-scan.sh" "$SKILL_DIR/scripts/generate-final-report.sh" "$SKILL_DIR/scripts/collect-data.sh" "$SKILL_DIR/scripts/lib/"*.py; do
    if grep -Eq "install-skill-from-github|openai/skills|codex |curl |wget " "$target"; then
        OUTBOUND=1
    fi
done
if [ "$OUTBOUND" -eq 0 ]; then
    pass "行为18 采集与渲染链路不出站、不安装远程 skill"
else
    fail "行为18 采集与渲染链路不出站、不安装远程 skill"
fi

# 行为 19 判断分层合同：画像/诊断/建议类型
python3 - "$TMP_ROOT" <<'PY'
import json, sys, time
tmp = sys.argv[1]
now = int(time.time())
evidence = {
    "version": "3.1.0",
    "scan": {"scan_time": "t", "scan_mode": "deep", "platform": "darwin"},
    "counts": {"obsidian_notes": 2, "ebooks": 0, "desktop_files": 1, "desktop_dirs": 1, "recent_notes_7d": 2},
    "recent_files": [
        {"name": "周报.md", "parent": "work", "parent_name": "work", "mtime": "2026-10-25 10:00:00",
         "mtime_epoch": now, "extension": ".md", "heading": "", "excerpt": "本周用 AI 写了周报。", "body_skipped": ""},
    ],
    "rejected_documents": [], "apps": ["ZCode"], "app_count": 1,
    "ai_usage_signals": {"marker_files": 1, "file_ratio": 1.0, "markers": {"AI": 1}, "ai_apps": ["ZCode"]},
    "scan_warnings": [], "zero_signal": False,
}
def suggestion(kind="basic", ai_role="把周报压成三句话"):
    return {"id": "s1", "kind": kind, "activity": "写周报", "ai_role": ai_role,
            "first_step": "把《周报.md》发给 AI。", "expected_saving": "省时间",
            "quick_win": True, "effort": "low", "reason": "每周都在写",
            "sources": [{"name": "周报.md"}], "app_refs": [], "evidence": ""}
def diagnosis(usage="occasional"):
    return {"summary": "周报已经半自动化，差最后一步归档。",
            "activities": [{"activity": "写周报", "ai_usage": usage, "time_note": "每周约 1 小时"}]}
def judgment(persona="novice", diag=None, sugg=None, prio=True):
    return {"persona": persona,
            "diagnosis": diag if diag is not None else diagnosis(),
            "understanding": {
                "activities": [{"text": "每周写周报"}, {"text": "格式固定"}],
                "domains": [{"text": "职场记录"}, {"text": "自我复盘"}],
                "work_style": [{"text": "固定节奏"}, {"text": "文档驱动"}],
                "structure": [{"text": "周报按目录归档"}, {"text": "命名规范"}],
            },
            "suggestions": sugg if sugg is not None else [suggestion()],
            "priorities": [{"id": "s1", "why": "十分钟见效",
                            "how_to_start": ["本周试一次"], "long_term": ["周报不再手写"]}] if prio else [],
            "cadence": {
                "daily": {"summary": "轻量", "items": ["写完随手交 AI"]},
                "weekly": {"summary": "对齐", "items": ["周五核对"]},
                "monthly": {"summary": "复盘", "items": ["归档旧周报"]},
            },
            "assets": [], "structure_advice": [],
            "insufficient_evidence": False}
json.dump(evidence, open(f"{tmp}/tier-evidence.json", "w"), ensure_ascii=False)
json.dump(judgment(), open(f"{tmp}/tier-good.json", "w"), ensure_ascii=False)
json.dump(judgment(persona="power", sugg=[suggestion(kind="upgrade")]),
          open(f"{tmp}/tier-power-good.json", "w"), ensure_ascii=False)
json.dump(judgment(persona="bad"), open(f"{tmp}/tier-bad-persona.json", "w"), ensure_ascii=False)
no_diag = judgment(); del no_diag["diagnosis"]
json.dump(no_diag, open(f"{tmp}/tier-no-diagnosis.json", "w"), ensure_ascii=False)
bad_diag = judgment(diag={"summary": "", "activities": []})
json.dump(bad_diag, open(f"{tmp}/tier-bad-diagnosis.json", "w"), ensure_ascii=False)
no_kind = judgment(); del no_kind["suggestions"][0]["kind"]
json.dump(no_kind, open(f"{tmp}/tier-no-kind.json", "w"), ensure_ascii=False)
json.dump(judgment(persona="power"), open(f"{tmp}/tier-power-no-upgrade.json", "w"), ensure_ascii=False)
plain_evidence = dict(evidence, ai_usage_signals={"marker_files": 0, "file_ratio": 0.0, "markers": {}, "ai_apps": []},
                      apps=[], app_count=0)
json.dump(plain_evidence, open(f"{tmp}/tier-plain-evidence.json", "w"), ensure_ascii=False)
json.dump(judgment(diag=diagnosis(usage="none"), sugg=[suggestion(kind="upgrade")]),
          open(f"{tmp}/tier-upgrade-no-basis.json", "w"), ensure_ascii=False)
PY
TIER_OK=1
python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/tier-evidence.json" "$TMP_ROOT/tier-good.json" >/dev/null && TIER_OK=0
python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/tier-evidence.json" "$TMP_ROOT/tier-power-good.json" >/dev/null && TIER_OK=0
for bad in tier-bad-persona tier-no-diagnosis tier-bad-diagnosis tier-no-kind tier-power-no-upgrade; do
    python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/tier-evidence.json" "$TMP_ROOT/$bad.json" >/dev/null 2>&1 || continue
    TIER_OK=1
done
if python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/tier-plain-evidence.json" "$TMP_ROOT/tier-upgrade-no-basis.json" >/dev/null 2>&1; then
    TIER_OK=1
fi
if [ "$TIER_OK" -eq 0 ]; then
    pass "行为19 判断分层合同：画像/诊断/建议类型缺失或无据都被拒"
else
    fail "行为19 判断分层合同：画像/诊断/建议类型缺失或无据都被拒"
fi

# 行为 20 指标双通道引用：聚合洞察合法且可验证
python3 - "$TMP_ROOT" <<'PY'
import json, sys, time
tmp = sys.argv[1]
now = int(time.time())
evidence = {
    "version": "4.0.0",
    "scan": {"scan_time": "t", "scan_mode": "deep", "platform": "darwin"},
    "counts": {"obsidian_notes": 2, "ebooks": 435, "desktop_files": 87, "desktop_dirs": 10, "recent_notes_7d": 5},
    "structure": {"top_dirs": [], "extensions": []},
    "recent_files": [
        {"name": "选题.md", "parent": "自媒体", "parent_name": "自媒体", "mtime": "2026-10-25 10:00:00",
         "mtime_epoch": now, "extension": ".md", "heading": "", "excerpt": "本周用 AI 挖了选题。", "body_skipped": ""},
    ],
    "rejected_documents": [], "apps": [], "app_count": 0,
    "ai_usage_signals": {"marker_files": 1, "file_ratio": 1.0, "markers": {"AI": 1}, "ai_apps": []},
    "knowledge_bases": [], "deep_reads": [], "rejected_deep_reads": [],
    "scan_warnings": [], "zero_signal": False,
}
def base(sources):
    return {
        "persona": "power",
        "diagnosis": {"summary": "沉睡资源是最大机会。",
                      "activities": [{"activity": "自媒体", "ai_usage": "occasional", "time_note": "每周更新"}]},
        "understanding": {
            "activities": [{"text": "在经营自媒体"}, {"text": "有大量沉睡资料"}],
            "domains": [{"text": "内容创作"}, {"text": "阅读积累"}],
            "work_style": [{"text": "产出节奏稳定"}, {"text": "喜欢成体系"}],
            "structure": [{"text": "按主题分库"}, {"text": "书库独立目录"}],
        },
        "suggestions": [{
            "id": "s1", "kind": "upgrade", "activity": "激活沉睡书库", "ai_role": "生成主题书单与选题",
            "first_step": "跟 AI 说：我有 435 本电子书，请按主题归类并给我 10 个选题。",
            "expected_saving": "激活沉睡资源", "quick_win": True, "effort": "low",
            "reason": "量大未用", "sources": sources, "app_refs": [], "evidence": "",
        }],
        "priorities": [{"id": "s1", "why": "十分钟见效", "how_to_start": ["先跑一次归类"], "long_term": ["选题不缺素材"]}],
        "cadence": {
            "daily": {"summary": "轻量", "items": ["随手记录"]},
            "weekly": {"summary": "对齐", "items": ["出 2 个选题"]},
            "monthly": {"summary": "复盘", "items": ["看书单消耗"]},
        },
        "assets": [{"title": "书库", "what": "435 本电子书", "why_valuable": "体量大",
                    "how_to_use": ["按主题出书单"], "basis": [{"type": "metric", "ref": "counts.ebooks"}]}],
        "structure_advice": [],
        "insufficient_evidence": False,
    }
json.dump(evidence, open(f"{tmp}/met-evidence.json", "w"), ensure_ascii=False)
json.dump(base([{"type": "metric", "ref": "counts.ebooks"}]), open(f"{tmp}/met-good.json", "w"), ensure_ascii=False)
bad = base([{"type": "metric", "ref": "counts.not_exist"}])
json.dump(bad, open(f"{tmp}/met-bad-ref.json", "w"), ensure_ascii=False)
PY
MET_OK=1
if python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/met-evidence.json" "$TMP_ROOT/met-good.json" >/dev/null; then
    MET_OK=0
fi
if python3 "$SKILL_DIR/scripts/lib/judgment.py" validate "$TMP_ROOT/met-evidence.json" "$TMP_ROOT/met-bad-ref.json" >/dev/null 2>&1; then
    MET_OK=1
fi
if [ "$MET_OK" -eq 0 ]; then
    pass "行为20 聚合指标引用合法且可验证，坏引用被拒"
else
    fail "行为20 聚合指标引用合法且可验证，坏引用被拒"
fi

# 行为 21 知识库发现：vault 标记、日记统计、自述深读、私钥拒绝
KB_HOME="$TMP_ROOT/kb-home"
mkdir -p "$KB_HOME/Vault/.obsidian" "$KB_HOME/Vault/07-Daily Note" "$KB_HOME/Vault/03-Resources" "$KB_HOME/Vault/Work" "$KB_HOME/logseq/.logseq"
printf '# 个人画像\n我是做内容的技术人。\n' > "$KB_HOME/Vault/03-Resources/个人画像.md"
printf 'BEGIN OPENSSH PRIVATE KEY\n不该被读\n' > "$KB_HOME/Vault/个人总结.md"
python3 - "$KB_HOME/Vault/07-Daily Note" <<'PY'
import datetime, os, sys, time
from pathlib import Path
root = Path(sys.argv[1])
now = time.time()
for i in range(12):
    day = now - i * 86400
    stamp = datetime.datetime.fromtimestamp(day).strftime("%Y-%m-%d")
    p = root / f"{stamp}.md"
    p.write_text("日记\n", encoding="utf-8")
    os.utime(p, (day, day))
PY
for i in 1 2 3 4; do echo "work $i" > "$KB_HOME/Vault/Work/n$i.md"; done
KB_OUT="$TMP_ROOT/kb-out.json"
if env ENV_SCANNER_HOME="$KB_HOME" \
    python3 "$SKILL_DIR/scripts/lib/kb_discover.py" --output "$KB_OUT" >/dev/null \
    && python3 - "$KB_OUT" <<'PY'
import json, sys
kb = json.load(open(sys.argv[1], encoding="utf-8"))
apps = {v["app"] for v in kb["knowledge_bases"]}
assert apps == {"obsidian", "logseq"}, apps
obs = next(v for v in kb["knowledge_bases"] if v["app"] == "obsidian")
assert obs["notes"] >= 18
assert obs["recent_notes_7d"] >= 7
journal = obs["journals"][0]
assert journal["dir"] == "07-Daily Note" and journal["files"] >= 10
assert any(d["dir"] == "Work" for d in obs["top_dirs"])
deep = kb["deep_reads"]
assert len(deep) == 1 and deep[0]["name"] == "个人画像.md"
assert "做内容的技术人" in deep[0]["text"]
assert any(r["reason"] == "private_key" for r in kb["rejected_deep_reads"])
assert "BEGIN OPENSSH PRIVATE KEY" not in json.dumps(kb, ensure_ascii=False)
PY
then
    pass "行为21 知识库发现 vault/日记/自述深读且拒绝私钥"
else
    fail "行为21 知识库发现 vault/日记/自述深读且拒绝私钥"
fi

echo "-----------------------------------"
echo "行为通过: $PASS"
echo "行为失败: $FAIL"
if [ "$FAIL" -eq 0 ] && [ "$PASS" -eq 21 ]; then
    exit 0
fi
exit 1
