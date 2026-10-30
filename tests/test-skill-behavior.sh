#!/bin/bash

# Environment Scanner - 行为回归（v3.0.0）
# 夹具都在临时目录，不扫描开发者的真实主目录。

set -u
# 回归不要弹出浏览器。行为 22 会单独覆盖这个开关。
export ENV_SCANNER_OPEN_REPORT=0
unset ENV_SCANNER_PLATFORM || true
unset ENV_SCANNER_PYTHON || true
unset ENV_SCANNER_IGNORE_SYSTEM_PYTHON || true
unset ENV_SCANNER_RUNTIME_HOME || true
unset ENV_SCANNER_VENDOR_DIR || true

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
mkdir -p "$KB_HOME/Vault/.obsidian" "$KB_HOME/Vault/07-Daily Note" "$KB_HOME/Vault/03-Resources" "$KB_HOME/Vault/Work" "$KB_HOME/Vault/合同" "$KB_HOME/logseq/logseq"
: > "$KB_HOME/logseq/logseq/config.edn"
printf '%s\n' '{"folder":"07-Daily Note","format":"YYYY-MM-DD"}' > "$KB_HOME/Vault/.obsidian/daily-notes.json"
printf '# 个人画像\n我是做内容的技术人。\n' > "$KB_HOME/Vault/03-Resources/个人画像.md"
printf 'BEGIN OPENSSH PRIVATE KEY\n不该被读\n' > "$KB_HOME/Vault/个人总结.md"
python3 - "$KB_HOME/Vault/07-Daily Note" "$KB_HOME/Vault/合同" <<'PY'
import datetime, os, sys, time
from pathlib import Path
daily = Path(sys.argv[1])
other = Path(sys.argv[2])
now = time.time()
for i in range(12):
    day = now - i * 86400
    stamp = datetime.datetime.fromtimestamp(day).strftime("%Y-%m-%d")
    p = daily / f"{stamp}.md"
    p.write_text("日记\n", encoding="utf-8")
    os.utime(p, (day, day))
    extra = other / f"2024-01-{i + 1:02d}.md"
    extra.write_text("合同流水\n", encoding="utf-8")
    os.utime(extra, (day, day))
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
logseq = next(v for v in kb["knowledge_bases"] if v["app"] == "logseq")
assert logseq["journals"] == []
obs = next(v for v in kb["knowledge_bases"] if v["app"] == "obsidian")
assert obs["notes"] >= 18
assert obs["recent_notes_7d"] >= 7
assert len(obs["journals"]) == 1, obs["journals"]
journal = obs["journals"][0]
assert journal["dir"] == "07-Daily Note" and journal["files"] >= 10
assert journal["kind"] == "daily" and journal["format"] == "YYYY-MM-DD"
assert all(item["dir"] != "合同" for item in obs["journals"])
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

# 行为 22 最终报告写好后自动打开。macOS 走 open，Windows 走 os.startfile，可用开关关闭。
OPEN_BIN="$TMP_ROOT/fake-open-bin"
OPEN_LOG="$TMP_ROOT/open-log.txt"
mkdir -p "$OPEN_BIN"
cat > "$OPEN_BIN/open" << EOF
#!/bin/bash
printf '%s\n' "\$1" >> "$OPEN_LOG"
EOF
cat > "$OPEN_BIN/xdg-open" << EOF
#!/bin/bash
printf '%s\n' "\$1" >> "$OPEN_LOG"
EOF
chmod +x "$OPEN_BIN/open" "$OPEN_BIN/xdg-open"
AUTO_HTML="$TMP_ROOT/auto-open.html"
SKIP_HTML="$TMP_ROOT/skip-open.html"
rm -f "$OPEN_LOG" "$TMP_ROOT/skip-open.out" "$TMP_ROOT/auto-open.out" "$TMP_ROOT/linux-open.out"
if env ENV_SCANNER_OPEN_REPORT=0 PATH="$OPEN_BIN:$PATH" \
        bash "$SKILL_DIR/scripts/generate-final-report.sh" \
        "$RUN_EVIDENCE_PATH" "$RUN_JUDGMENT" "$SKIP_HTML" \
        >"$TMP_ROOT/skip-open.out" 2>&1 \
    && [ -s "$SKIP_HTML" ] \
    && [ ! -f "$OPEN_LOG" ] \
    && grep -q "已跳过自动打开" "$TMP_ROOT/skip-open.out" \
    && env ENV_SCANNER_OPEN_REPORT=1 PATH="$OPEN_BIN:$PATH" \
        bash "$SKILL_DIR/scripts/generate-final-report.sh" \
        "$RUN_EVIDENCE_PATH" "$RUN_JUDGMENT" "$AUTO_HTML" \
        >"$TMP_ROOT/auto-open.out" 2>&1 \
    && [ -s "$AUTO_HTML" ] \
    && grep -q "已打开报告" "$TMP_ROOT/auto-open.out" \
    && env ENV_SCANNER_OPEN_REPORT=1 ENV_SCANNER_PLATFORM=linux PATH="$OPEN_BIN:$PATH" \
        python3 "$SKILL_DIR/scripts/lib/open_report.py" "$SKIP_HTML" \
        >"$TMP_ROOT/linux-open.out" 2>&1 \
    && grep -q "已打开报告" "$TMP_ROOT/linux-open.out" \
    && python3 - "$SKILL_DIR/scripts/lib" "$OPEN_LOG" "$AUTO_HTML" "$SKIP_HTML" >"$TMP_ROOT/win-open.out" 2>&1 <<'PY'
import os
import sys
from pathlib import Path

lib, mac_log, auto_html, skip_html = sys.argv[1:]
sys.path.insert(0, lib)
lines = [line for line in Path(mac_log).read_text(encoding="utf-8").splitlines() if line.strip()]
assert lines == [str(Path(auto_html).resolve()), str(Path(skip_html).resolve())], lines
calls = []
os.startfile = lambda path: calls.append(os.fspath(path))
os.environ["ENV_SCANNER_PLATFORM"] = "windows"
os.environ["ENV_SCANNER_OPEN_REPORT"] = "1"
import open_report
rc = open_report.main(["open_report.py", skip_html])
assert rc == 0, rc
assert Path(calls[0]) == Path(skip_html).resolve(), calls
del os.startfile
rc = open_report.main(["open_report.py", skip_html])
assert rc == 1, rc
PY
then
    pass "行为22 最终报告按系统打开，且可用开关关闭"
else
    fail "行为22 最终报告按系统打开，且可用开关关闭"
    echo "----- skip-open -----" >&2
    cat "$TMP_ROOT/skip-open.out" >&2 || true
    echo "----- auto-open -----" >&2
    cat "$TMP_ROOT/auto-open.out" >&2 || true
    echo "----- linux-open -----" >&2
    cat "$TMP_ROOT/linux-open.out" >&2 || true
    echo "----- win-open -----" >&2
    cat "$TMP_ROOT/win-open.out" >&2 || true
fi

# 行为 23 样本名额按活动分配：下载、日记、书籍有上限，单目录工作文件仍可回填
SEL="$TMP_ROOT/select23"
mkdir -p "$TMP_ROOT/select-home" "$SEL/empty"
python3 - "$SEL" << 'PY'
import os
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
now = time.time()

def write(path, data, age_days, binary=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    if binary:
        path.write_bytes(data)
    else:
        path.write_text(data, encoding="utf-8")
    stamp = now - age_days * 86400
    os.utime(path, (stamp, stamp))

for index in range(40):
    write(root / "down-a" / f"dl-{index}.pdf", b"%PDF-1.4", 1, True)
write(root / "docs-a" / "项目" / "合同草案.md", "这是正在改的合同草案。\n", 5)
write(root / "docs-a" / "项目" / "报价.md", "报价还要再核一遍。\n", 6)
obsidian = root / "docs-b" / ".obsidian"
obsidian.mkdir(parents=True)
(obsidian / "daily-notes.json").write_text(
    '{"folder":"日记","format":"YYYY-MM-DD"}\n',
    encoding="utf-8",
)
for index in range(85):
    write(root / "docs-b" / "日记" / f"2024-01-{index + 1}.md", f"第{index}天的流水账。\n", 1)
write(root / "docs-b" / "市集" / "方案.md", "周六市集还要确认摊位。\n", 20)
for index in range(10):
    write(root / "docs-f" / "日期名" / f"2024-03-{index + 1:02d}.md", f"日期名但不是日记{index}。\n", 1)
for index in range(20):
    write(root / "desk-c" / "书籍" / f"book-{index}.pdf", b"%PDF-1.4", 1, True)
write(root / "desk-c" / "方案.md", "桌面上的方案还在改。\n", 3)
for index in range(30):
    write(root / "docs-d" / "唯一" / f"记录-{index}.md", f"记录{index}。\n", 1)
write(root / "docs-e" / "旧提纲.md", "这是去年的提纲。\n", 400)
write(root / "docs-e" / "新笔记.md", "今天的笔记。\n", 1)
PY
sample_sel() {
    env ENV_SCANNER_DOCUMENTS="$1" \
        ENV_SCANNER_DESKTOP="$2" \
        ENV_SCANNER_DOWNLOADS="$3" \
        ENV_SCANNER_BOOKS="$4" \
        ENV_SCANNER_HOME="$TMP_ROOT/select-home" \
        ENV_SCANNER_DISCOVER_HOME=0 \
        python3 "$SKILL_DIR/scripts/lib/sample_content.py" --output "$5" --mode deep "${@:6}" >/dev/null
}
if [ -f "$SEL/docs-a/项目/合同草案.md" ] \
    && sample_sel "$SEL/docs-a" "$SEL/empty" "$SEL/down-a" "$SEL/empty" "$SEL/a.json" \
    && sample_sel "$SEL/docs-b" "$SEL/empty" "$SEL/empty" "$SEL/empty" "$SEL/b.json" \
    && sample_sel "$SEL/empty" "$SEL/desk-c" "$SEL/empty" "$SEL/desk-c/书籍" "$SEL/c.json" \
    && sample_sel "$SEL/docs-d" "$SEL/empty" "$SEL/empty" "$SEL/empty" "$SEL/d.json" \
    && sample_sel "$SEL/docs-e" "$SEL/empty" "$SEL/empty" "$SEL/empty" "$SEL/e.json" \
        --explicit "$SEL/docs-e/旧提纲.md" \
    && sample_sel "$SEL/docs-f" "$SEL/empty" "$SEL/empty" "$SEL/empty" "$SEL/f.json" \
    && python3 - "$SEL/a.json" "$SEL/b.json" "$SEL/c.json" "$SEL/d.json" "$SEL/e.json" "$SEL/f.json" << 'PY'
import json
import sys

def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)["files"]

downloaded, journals, books, single, explicit, plain_dates = [load(path) for path in sys.argv[1:]]
names = [item["name"] for item in downloaded]
assert "合同草案.md" in names and "报价.md" in names
download_items = [item for item in downloaded if item["name"].startswith("dl-")]
assert len(download_items) == 12, len(download_items)
first_download = min(names.index(item["name"]) for item in download_items)
for work_name in ("合同草案.md", "报价.md"):
    assert names.index(work_name) < first_download
    assert next(item["excerpt"] for item in downloaded if item["name"] == work_name)

journal_names = [item["name"] for item in journals]
assert "方案.md" in journal_names
assert next(item["excerpt"] for item in journals if item["name"] == "方案.md")
dated = [item for item in journals if item["name"].startswith("2024-01-")]
assert len(dated) == 3, len(dated)
assert journal_names.index("方案.md") < min(journal_names.index(item["name"]) for item in dated)

book_names = [item["name"] for item in books]
assert "方案.md" in book_names
book_items = [item for item in books if item["name"].startswith("book-")]
assert len(book_items) == 4, len(book_items)

assert len(single) == 30, len(single)
explicit_names = [item["name"] for item in explicit]
assert "旧提纲.md" in explicit_names and "新笔记.md" in explicit_names
plain_names = [item["name"] for item in plain_dates]
assert len(plain_names) == 10, plain_names
assert all(name.startswith("2024-03-") for name in plain_names)
PY
then
    pass "行为23 样本名额按目录、下载、日记、书籍分配"
else
    fail "行为23 样本名额按目录、下载、日记、书籍分配"
fi

# 行为 24 平台适配器：mac 实路径 + ENV_SCANNER_PLATFORM=windows 强制
# 计划里写的「行为 22」已被「报告自动打开」占用，适配器测试顺延为 24。
OD_HOME="$TMP_ROOT/onedrive-home"
WIN_A="$TMP_ROOT/win-apps-a"
WIN_B="$TMP_ROOT/win-apps-b"
mkdir -p "$OD_HOME/OneDrive/Documents" "$OD_HOME/OneDrive/Desktop" "$WIN_A/Notepad++" "$WIN_B/VS Code"
WIN_APPS_OUT="$TMP_ROOT/win-apps.json"
python3 - "$SKILL_DIR/scripts/lib" "$OD_HOME" >"$TMP_ROOT/b24-adapter.out" 2>"$TMP_ROOT/b24-adapter.err" <<'PY'
import os
import sys
from pathlib import Path

lib, home = sys.argv[1:]
sys.path.insert(0, lib)
os.environ.pop("ENV_SCANNER_PLATFORM", None)

import platforms

mac = platforms.get_platform()
assert mac.name() == "mac", mac.name()
assert mac.env_path_sep() == ":"
assert "Library" in mac.home_discover_skip_dirs()

os.environ["ENV_SCANNER_PLATFORM"] = "windows"
win = platforms.get_platform()
assert win.name() == "windows", win.name()
assert win.env_path_sep() == ";"
skip = win.home_discover_skip_dirs()
assert "AppData" in skip and "Application Data" in skip
home_path = Path(home)
roots = win.default_user_roots(home_path)
assert roots["documents"] == home_path / "Documents", roots["documents"]
note = home_path / "OneDrive" / "Documents" / "笔记.md"
note.write_text("有文件", encoding="utf-8")
roots = win.default_user_roots(home_path)
assert roots["documents"] == note.parent, roots["documents"]
note.unlink()
contoso = home_path / "OneDrive - Contoso" / "Documents"
contoso.mkdir(parents=True)
(contoso / "方案.md").write_text("后来的库", encoding="utf-8")
roots = win.default_user_roots(home_path)
assert roots["documents"] == contoso, roots["documents"]
warnings = []
win.collect_app_names(warnings, {})
assert "windows_registry_unavailable" in warnings, warnings
PY
adapter_rc=$?
env ENV_SCANNER_PLATFORM=windows ENV_SCANNER_APPLICATIONS="$WIN_A;$WIN_B" \
    python3 "$SKILL_DIR/scripts/lib/app_inventory.py" --output "$WIN_APPS_OUT" \
    >"$TMP_ROOT/b24-apps.out" 2>"$TMP_ROOT/b24-apps.err"
apps_rc=$?
python3 - "$WIN_APPS_OUT" >"$TMP_ROOT/b24-check.out" 2>"$TMP_ROOT/b24-check.err" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["platform"] == "windows", data["platform"]
assert data["apps"] == ["Notepad++", "VS Code"], data["apps"]
PY
check_rc=$?
if [ "$adapter_rc" -eq 0 ] && [ "$apps_rc" -eq 0 ] && [ "$check_rc" -eq 0 ] \
    && grep -q "IFS=';'" "$SKILL_DIR/scripts/run-scan.sh" \
    && grep -q "eol=lf" "$SKILL_DIR/.gitattributes" \
    && grep -q "eol=crlf" "$SKILL_DIR/.gitattributes" \
    && grep -q "未实机验证" "$SKILL_DIR/scripts/run-scan.ps1" \
    && grep -q -- "-split ';'" "$SKILL_DIR/scripts/run-scan.ps1"
then
    pass "行为24 平台适配器：mac 分隔符与跳过名单，Windows 强制路径覆盖 OneDrive 与注册表降级"
else
    fail "行为24 平台适配器：mac 分隔符与跳过名单，Windows 强制路径覆盖 OneDrive 与注册表降级"
    echo "----- adapter rc=$adapter_rc -----" >&2
    cat "$TMP_ROOT/b24-adapter.err" >&2 || true
    echo "----- apps rc=$apps_rc -----" >&2
    cat "$TMP_ROOT/b24-apps.err" >&2 || true
    echo "----- check rc=$check_rc -----" >&2
    cat "$TMP_ROOT/b24-check.err" >&2 || true
fi

# 行为 25 锁住自述边界、知识库日记配置、整词与办公文件名、
# 安装包/软件目录跳过、缺失根、OneDrive 其余根、密钥样例、深读摘录不进报告。
B25="$TMP_ROOT/b25"
mkdir -p "$B25"
if python3 - "$B25" "$SKILL_DIR" >"$TMP_ROOT/b25.out" 2>"$TMP_ROOT/b25.err" <<'PY'
import json
import os
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
skill = Path(sys.argv[2])
sys.path.insert(0, str(skill / "scripts" / "lib"))
os.environ["ENV_SCANNER_DISCOVER_HOME"] = "0"
os.environ.pop("ENV_SCANNER_PLATFORM", None)

from evidence_pack import build_evidence
from kb_discover import collect as collect_kb
from judgment import kb_html, render
from platform_win import WindowsAdapter
from sample_content import collect_samples
from scan_collect import collect as collect_counts
from scan_collect import load_skip_rules, walk

def write_docx(path, inner_xml):
    path.parent.mkdir(parents=True, exist_ok=True)
    document = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        f"<w:body><w:p>{inner_xml}</w:p></w:body></w:document>"
    )
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("word/document.xml", document)

def stamp(path, when):
    os.utime(path, (when, when))

def vault(home, name):
    path = home / name
    (path / ".obsidian").mkdir(parents=True)
    return path

def kb_at(home):
    os.environ["ENV_SCANNER_HOME"] = str(home)
    return collect_kb()

# 1. 自述命中与拒绝标记。docx / pdf 即使更新也不占深读。
match_home = root / "match"
match_vault = vault(match_home, "Vault")
bodies = {
    "关于我们.md": "公司介绍句子甲",
    "如何写简历.md": "教程句子乙",
    "简历模板.md": "模板句子丙",
    "个人画像.md": "画像句子丁",
    "简历.md": "简历句子戊",
    "我的简历.md": "我的简历句子己",
}
base = 1_700_000_000
for index, (name, text) in enumerate(bodies.items()):
    path = match_vault / name
    path.write_text(text + "\n", encoding="utf-8")
    stamp(path, base + index)
write_docx(match_vault / "简历.docx", "<w:r><w:t>二进制句子庚</w:t></w:r>")
(match_vault / "简历.pdf").write_bytes("二进制句子庚".encode("utf-8"))
stamp(match_vault / "简历.docx", base + 100)
stamp(match_vault / "简历.pdf", base + 101)
match_kb = kb_at(match_home)
match_names = {item["name"] for item in match_kb["deep_reads"]}
assert match_names == {"个人画像.md", "简历.md", "我的简历.md"}, match_names
match_blob = json.dumps(match_kb, ensure_ascii=False)
for sentence in ("画像句子丁", "简历句子戊", "我的简历句子己"):
    assert sentence in match_blob
for sentence in ("公司介绍句子甲", "教程句子乙", "模板句子丙", "二进制句子庚"):
    assert sentence not in match_blob

# 2. 四个库仍只发现 3 个，深读全局最多 3 份。
cap_home = root / "cap"
for name in ("va", "vb", "vc", "vd"):
    place = vault(cap_home, name)
    (place / "个人画像.md").write_text(f"画像 {name}\n", encoding="utf-8")
    (place / "简历.md").write_text(f"简历 {name}\n", encoding="utf-8")
cap_kb = kb_at(cap_home)
assert len(cap_kb["knowledge_bases"]) == 3, cap_kb["knowledge_bases"]
assert len(cap_kb["deep_reads"]) == 3, [item["name"] for item in cap_kb["deep_reads"]]

# 3. 私钥丢掉后不回填更旧的简历。关于我们更新也不占名额。
secret_home = root / "secret-kb"
secret_vault = vault(secret_home, "Vault")
secret_files = {
    "关于我们.md": (50, "公司介绍句子甲"),
    "个人总结.md": (40, "BEGIN EC PRIVATE KEY\n密钥句子不应出现\n"),
    "个人画像.md": (30, "画像句子丁"),
    "我的简历.md": (20, "我的简历句子己"),
    "简历.md": (10, "简历句子戊"),
}
for name, (offset, text) in secret_files.items():
    path = secret_vault / name
    path.write_text(text, encoding="utf-8")
    stamp(path, base + offset)
secret_kb = kb_at(secret_home)
secret_names = {item["name"] for item in secret_kb["deep_reads"]}
assert secret_names == {"个人画像.md", "我的简历.md"}, secret_names
assert any(
    Path(item["path"]).name == "个人总结.md" and item["reason"] == "private_key"
    for item in secret_kb["rejected_deep_reads"]
)
secret_blob = json.dumps(secret_kb, ensure_ascii=False)
assert "密钥句子不应出现" not in secret_blob
assert "BEGIN EC PRIVATE KEY" not in secret_blob
assert "简历句子戊" not in secret_blob

# 4. 日记只认知识库配置目录。daily 里任意文件名算，旁边的日期文件名不算。
journal_home = root / "journal"
journal_vault = vault(journal_home, "Vault")
(journal_vault / ".obsidian" / "daily-notes.json").write_text(
    json.dumps({"folder": "daily", "format": "YYYY-MM-DD"}),
    encoding="utf-8",
)
for index in range(1, 13):
    daily = journal_vault / "daily" / f"记事-{index}.md"
    daily.parent.mkdir(parents=True, exist_ok=True)
    daily.write_text("日记\n", encoding="utf-8")
    weekly = journal_vault / "weekly" / f"2024-01-{index:02d}.md"
    weekly.parent.mkdir(parents=True, exist_ok=True)
    weekly.write_text("不是配置里的日记\n", encoding="utf-8")
journal_kb = kb_at(journal_home)
journals = journal_kb["knowledge_bases"][0]["journals"]
assert len(journals) == 1, journals
assert journals[0]["dir"] == "daily" and journals[0]["files"] == 12
assert journals[0]["kind"] == "daily" and journals[0]["format"] == "YYYY-MM-DD"
label_html = kb_html({
    "knowledge_bases": [{
        "app": "obsidian",
        "path": "/vault",
        "notes": 12,
        "recent_notes_7d": 1,
        "journals": [journals[0]],
    }],
    "deep_reads": [],
})
assert "日记习惯" in label_html
assert f"「daily」每日{journals[0]['files']} 篇" in label_html

# Logseq 没写 journals-directory 时，只用默认目录 journals。pages 里的日期名不算。
logseq_home = root / "logseq-default"
graph = logseq_home / "graph"
(graph / "logseq").mkdir(parents=True)
(graph / "logseq" / "config.edn").write_text(
    '{:journal/page-title-format "yyyy-MM-dd"}\n',
    encoding="utf-8",
)
for index in range(1, 13):
    page = graph / "journals" / f"周一记事-{index}.md"
    page.parent.mkdir(parents=True, exist_ok=True)
    page.write_text("记事\n", encoding="utf-8")
    other = graph / "pages" / f"2024-02-{index:02d}.md"
    other.parent.mkdir(parents=True, exist_ok=True)
    other.write_text("页面\n", encoding="utf-8")
logseq_kb = kb_at(logseq_home)
logseq_journals = logseq_kb["knowledge_bases"][0]["journals"]
assert len(logseq_journals) == 1, logseq_journals
assert logseq_journals[0]["dir"] == "journals"
assert logseq_journals[0]["files"] == 12 and logseq_journals[0]["kind"] == "daily"

# 写不成目录名的 edn 不猜，也不把默认 journals 目录当成日记。
broken_home = root / "logseq-broken"
broken = broken_home / "graph"
(broken / "logseq").mkdir(parents=True)
(broken / "logseq" / "config.edn").write_text(
    '{:journals-directory (str "journals")}\n',
    encoding="utf-8",
)
(broken / "journals").mkdir()
for index in range(1, 13):
    (broken / "journals" / f"记事-{index}.md").write_text("不该算\n", encoding="utf-8")
broken_kb = kb_at(broken_home)
assert broken_kb["knowledge_bases"][0]["journals"] == []
assert any(
    item.startswith("journal_config_unparsed:")
    for item in broken_kb["scan_warnings"]
), broken_kb["scan_warnings"]

# 只有 .logseq/ 和 journals/、没有 logseq/config.edn，不是 Logseq 图。
fake_home = root / "logseq-fake-marker"
fake = fake_home / "graph"
(fake / ".logseq").mkdir(parents=True)
(fake / "journals").mkdir()
fake_kb = kb_at(fake_home)
assert fake_kb["knowledge_bases"] == [], fake_kb["knowledge_bases"]

# periodic-notes：没启用的 daily 不算。启用的 weekly 不看文件名。
periodic_home = root / "periodic"
periodic = vault(periodic_home, "Vault")
plugin = periodic / ".obsidian" / "plugins" / "periodic-notes"
plugin.mkdir(parents=True)
(plugin / "data.json").write_text(
    json.dumps({
        "daily": {"enabled": False, "folder": "daily", "format": "YYYY-MM-DD"},
        "weekly": {"enabled": True, "folder": "周记", "format": "YYYY-[W]ww"},
    }, ensure_ascii=False),
    encoding="utf-8",
)
for index in range(1, 13):
    note = periodic / "周记" / f"随便{index}.md"
    note.parent.mkdir(parents=True, exist_ok=True)
    note.write_text("周记\n", encoding="utf-8")
    dated = periodic / "daily" / f"2024-03-{index:02d}.md"
    dated.parent.mkdir(parents=True, exist_ok=True)
    dated.write_text("未启用\n", encoding="utf-8")
periodic_kb = kb_at(periodic_home)
periodic_journals = periodic_kb["knowledge_bases"][0]["journals"]
assert len(periodic_journals) == 1, periodic_journals
assert periodic_journals[0]["kind"] == "weekly"
assert periodic_journals[0]["dir"] == "周记" and periodic_journals[0]["files"] == 12
assert periodic_journals[0]["format"] == "YYYY-[W]ww"

# 5、8. 采样：整词、办公文件名、日记名额、密钥拒绝。
sample_root = root / "sample"
docs = sample_root / "docs"
empty_desk = sample_root / "desktop"
empty_down = sample_root / "downloads"
missing_books = sample_root / "missing-books"
empty_desk.mkdir(parents=True)
empty_down.mkdir(parents=True)
for index in range(1, 11):
    path = docs / "weekly" / f"周报2026-10-{index:02d}.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("周报正文\n", encoding="utf-8")
for index in range(1, 7):
    path = docs / "chapters" / f"1.{index} 背景.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("章节正文\n", encoding="utf-8")
dated_names = [
    "2024-01-12.md",
    "2026-10-25-周记.md",
    "10.25、先.md",
    "2024-01-N.md",
    "2024-02-01.md",
    "2024-02-02.md",
    "2024-02-03.md",
]
for name in dated_names:
    path = docs / "diary" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("日记正文\n", encoding="utf-8")
(docs / "diary" / "周一记事.md").write_text("日记正文\n", encoding="utf-8")
(docs / ".obsidian").mkdir(parents=True)
(docs / ".obsidian" / "daily-notes.json").write_text(
    json.dumps({"folder": "diary", "format": "YYYY-MM-DD"}),
    encoding="utf-8",
)

write_docx(docs / "keep" / "seed-round.docx", "<w:r><w:t>种子轮材料还在</w:t></w:r>")
write_docx(docs / "keep" / "crypto-wallet.docx", "<w:r><w:t>普通对照句</w:t></w:r>")
(docs / "keep" / "Keyboard.md").write_text("键盘还在\n", encoding="utf-8")
(docs / "keep" / "Keyboard" / "a.md").parent.mkdir(parents=True, exist_ok=True)
(docs / "keep" / "Keyboard" / "a.md").write_text("键盘子目录还在\n", encoding="utf-8")
(docs / "keep" / "cryptocurrency.txt").write_text("长词还在\n", encoding="utf-8")
(docs / "keep" / "seeds.txt").write_text("复数还在\n", encoding="utf-8")
(docs / "keep" / "wallets" / "keep.md").parent.mkdir(parents=True, exist_ok=True)
(docs / "keep" / "wallets" / "keep.md").write_text("目录复数还在\n", encoding="utf-8")

skipped = {
    "seed.txt": "SKIP_SEED",
    "my_seed.txt": "SKIP_MY_SEED",
    "my seed.txt": "SKIP_MY_SPACE",
    "crypto.txt": "SKIP_CRYPTO",
}
for name, sentinel in skipped.items():
    (docs / "secret-names" / name).parent.mkdir(parents=True, exist_ok=True)
    (docs / "secret-names" / name).write_text(sentinel + "\n", encoding="utf-8")
(docs / "wallet" / "hidden.md").parent.mkdir(parents=True, exist_ok=True)
(docs / "wallet" / "hidden.md").write_text("SKIP_WALLET_DIR\n", encoding="utf-8")

office = {
    "周报.pages": ("pages", "OFFICE_PAGES"),
    "方案.doc": ("doc", "OFFICE_DOC"),
    "笔记.rtf": ("rtf", "OFFICE_RTF"),
    "演示.key": ("keynote", "OFFICE_KEY"),
    "表格.numbers": ("numbers", "OFFICE_NUM"),
}
for name, (_, sentinel) in office.items():
    (docs / "office" / name).parent.mkdir(parents=True, exist_ok=True)
    (docs / "office" / name).write_text(sentinel + "\n", encoding="utf-8")

secrets = {
    "ec.md": ("BEGIN EC PRIVATE KEY\nSENTINEL_EC\n", "private_key"),
    "enc.md": ("BEGIN ENCRYPTED PRIVATE KEY\nSENTINEL_ENC\n", "private_key"),
    "pgp.md": ("BEGIN PGP PRIVATE KEY BLOCK\nSENTINEL_PGP\n", "private_key"),
    "putty.md": ("PuTTY-User-Key-File-2\nSENTINEL_PUTTY\n", "private_key"),
    "json.md": ('{"password": "hunter2-fixture"}\nSENTINEL_JSON\n', "credential_assignment"),
    "db.md": ("DB_PASSWORD=fixture-db-value\nSENTINEL_DB\n", "credential_assignment"),
    "cn1.md": ("密码：fixture-cn-value\nSENTINEL_CN1\n", "credential_assignment"),
    "cn2.md": ("口令=fixture-kouling\nSENTINEL_CN2\n", "credential_assignment"),
    "rsa.md": ("BEGIN  RSA PRIVATE KEY\nSENTINEL_RSA\n", "private_key"),
}
for name, (text, _) in secrets.items():
    path = docs / "secrets" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
nul_path = docs / "secrets" / "nul.md"
nul_path.write_bytes("\x00".join("BEGIN EC PRIVATE KEY\nSENTINEL_NUL").encode("utf-8"))
write_docx(
    docs / "secrets" / "split.docx",
    "<w:r><w:t>BEGIN</w:t></w:r><w:r><w:t>RSA</w:t></w:r>"
    "<w:r><w:t>PRIVATE</w:t></w:r><w:r><w:t>KEY</w:t></w:r>"
    "<w:r><w:t>SENTINEL_DOCX</w:t></w:r>",
)
(docs / "secrets" / "普通口令.md").write_text(
    "这里只有密码两个字\nThe password is not assigned.\n",
    encoding="utf-8",
)

(docs / "安装包.dmg").write_bytes(b"dmg")
(docs / "安装.exe").write_bytes(b"exe")
(docs / "资料.zip").write_bytes(b"zip")
(docs / "运行.log").write_text("运行日志\n", encoding="utf-8")
(docs / "QQ" / "聊天.md").parent.mkdir(parents=True, exist_ok=True)
(docs / "QQ" / "聊天.md").write_text("QQ_CHAT\n", encoding="utf-8")
(docs / "Tencent Files" / "记录.md").parent.mkdir(parents=True, exist_ok=True)
(docs / "Tencent Files" / "记录.md").write_text("TENCENT_RECORD\n", encoding="utf-8")
(docs / "QQ笔记" / "方案.md").parent.mkdir(parents=True, exist_ok=True)
(docs / "QQ笔记" / "方案.md").write_text("用户自己的方案还在\n", encoding="utf-8")
(docs / "关于QQ.md").write_text("关于QQ的笔记还在\n", encoding="utf-8")
(docs / "keep" / "id_ecdsa").write_text("BEGIN EC PRIVATE KEY\nSENTINEL_ECDSA_FILE\n", encoding="utf-8")
(docs / "keep" / "key.ppk").write_text("PuTTY-User-Key-File-2\nSENTINEL_PPK\n", encoding="utf-8")
(docs / "Demo.app" / "笔记.md").parent.mkdir(parents=True, exist_ok=True)
(docs / "Demo.app" / "笔记.md").write_text("APP_INSIDE\n", encoding="utf-8")
(docs / "说明.pdf").write_bytes(b"%PDF-1.4")

rules = load_skip_rules()
warnings = []
walked = {path.name for path in walk(docs, rules, warnings)}
for name in (
    "seed-round.docx", "crypto-wallet.docx", "Keyboard.md", "a.md",
    "cryptocurrency.txt", "seeds.txt", "keep.md",
):
    assert name in walked, name
for name in list(skipped) + ["hidden.md"]:
    assert name not in walked, name
for name in office:
    assert name in walked, name
for name in ("安装包.dmg", "安装.exe", "资料.zip", "运行.log", "聊天.md", "记录.md", "id_ecdsa", "key.ppk", "笔记.md"):
    assert name not in walked, name
for name in ("方案.md", "关于QQ.md", "说明.pdf"):
    assert name in walked, name

samples = collect_samples(docs, empty_desk, empty_down, missing_books, "deep", [])
sample_blob = json.dumps(samples, ensure_ascii=False)
by_name = {item["name"]: item for item in samples["files"]}
for name in (f"周报2026-10-{index:02d}.md" for index in range(1, 11)):
    assert name in by_name, name
for index in range(1, 7):
    assert f"1.{index} 背景.md" in by_name
journal_candidates = dated_names + ["周一记事.md"]
picked_journal = [name for name in journal_candidates if name in by_name]
assert len(picked_journal) == 3, picked_journal
assert "用户自己的方案还在" in by_name["方案.md"]["excerpt"]
assert "关于QQ的笔记还在" in by_name["关于QQ.md"]["excerpt"]
assert "说明.pdf" in by_name
assert "种子轮材料还在" in by_name["seed-round.docx"]["excerpt"]
for name in ("crypto-wallet.docx", "Keyboard.md", "a.md", "cryptocurrency.txt", "seeds.txt", "keep.md"):
    assert name in by_name, name
for name, (expected, _) in office.items():
    item = by_name[name]
    assert item["body_skipped"] == expected, item
    assert item["excerpt"] == "" and item["heading"] == ""
plain = by_name["普通口令.md"]
assert "密码" in plain["excerpt"] and "password is not assigned" in plain["excerpt"]
rejected = {Path(item["path"]).name: item["reason"] for item in samples["rejected_documents"]}
for name, (_, reason) in secrets.items():
    assert rejected.get(name) == reason, (name, rejected.get(name))
assert rejected.get("nul.md") == "private_key", rejected.get("nul.md")
assert rejected.get("split.docx") == "private_key", rejected.get("split.docx")
for sentinel in (
    "SENTINEL_EC", "SENTINEL_ENC", "SENTINEL_PGP", "SENTINEL_PUTTY", "SENTINEL_JSON",
    "SENTINEL_DB", "SENTINEL_CN1", "SENTINEL_CN2", "SENTINEL_NUL", "SENTINEL_RSA",
    "SENTINEL_DOCX", "OFFICE_PAGES", "OFFICE_DOC", "OFFICE_RTF", "OFFICE_KEY",
    "OFFICE_NUM", "SKIP_SEED", "SKIP_MY_SEED", "SKIP_MY_SPACE", "SKIP_CRYPTO",
    "SKIP_WALLET_DIR", "hunter2-fixture", "BEGIN EC PRIVATE KEY",
    "BEGIN ENCRYPTED PRIVATE KEY", "PuTTY-User-Key-File",
    "SENTINEL_ECDSA_FILE", "SENTINEL_PPK", "QQ_CHAT", "TENCENT_RECORD", "APP_INSIDE",
):
    assert sentinel not in sample_blob, sentinel
config = json.loads((skill / "config.json").read_text(encoding="utf-8"))
assert config["features"]["smart_filtering"]["skip_file_substrings"] == ["wallet", "crypto", "seed"]

# 6. 根不存在只记警告，不失败。
missing = [root / "gone-docs", root / "gone-desk", root / "gone-down", root / "gone-books"]
gone = collect_counts(*missing, "deep")
assert gone["scan_warnings"] == [f"missing_root:{path}" for path in missing], gone["scan_warnings"]
assert gone["files"]["obsidian_notes"] == 0
assert gone["scan_limits"]["count_is_total"] is True
present = root / "present"
present_docs = present / "docs"
present_desk = present / "desktop"
present_down = present / "downloads"
for path in (present_docs, present_desk, present_down):
    path.mkdir(parents=True)
(present_docs / "note.md").write_text("有一篇\n", encoding="utf-8")
partial = collect_counts(present_docs, present_desk, present_down, present / "no-books", "deep")
assert partial["files"]["obsidian_notes"] == 1, partial["files"]
assert partial["scan_warnings"] == [f"missing_root:{present / 'no-books'}"], partial["scan_warnings"]

# 7. OneDrive 的桌面、下载和书籍跟文档根分开判断。
home = root / "winhome"
(home / "Documents").mkdir(parents=True)
(home / "Desktop").mkdir()
(home / "Downloads").mkdir()
(home / "OneDrive" / "Documents").mkdir(parents=True)
(home / "OneDrive" / "Desktop").mkdir()
(home / "OneDrive" / "Downloads").mkdir()
(home / "OneDrive" / "Downloads" / "已下载.txt").write_text("不改下载根", encoding="utf-8")
(home / "OneDrive" / "书籍").mkdir()
(home / "OneDrive" / "书籍" / "书.md").write_text("不单独探测", encoding="utf-8")
win = WindowsAdapter()
roots = win.default_user_roots(home)
assert roots["documents"] == home / "Documents"
assert roots["desktop"] == home / "Desktop"
assert roots["downloads"] == home / "Downloads"
assert roots["books"] == home / "Desktop" / "书籍"
(home / "OneDrive" / "Documents" / "笔记.md").write_text("有文件", encoding="utf-8")
roots = win.default_user_roots(home)
assert roots["documents"] == home / "OneDrive" / "Documents"
assert roots["desktop"] == home / "Desktop"
assert roots["books"] == home / "Desktop" / "书籍"
assert roots["downloads"] == home / "Downloads"
(home / "OneDrive" / "Desktop" / "桌面.md").write_text("有桌面", encoding="utf-8")
roots = win.default_user_roots(home)
assert roots["desktop"] == home / "OneDrive" / "Desktop"
assert roots["books"] == home / "OneDrive" / "Desktop" / "书籍"
assert roots["documents"] == home / "OneDrive" / "Documents"
(home / "OneDrive" / "Desktop" / "桌面.md").unlink()
(home / "OneDrive - A" / "Desktop").mkdir(parents=True)
contoso = home / "OneDrive - Contoso" / "Desktop"
contoso.mkdir(parents=True)
(contoso / "方案.md").write_text("后来的桌面", encoding="utf-8")
roots = win.default_user_roots(home)
assert roots["desktop"] == contoso
assert roots["books"] == contoso / "书籍"
assert roots["documents"] == home / "OneDrive" / "Documents"
assert roots["downloads"] == home / "Downloads"

# 只写「密码」的自述仍然深读。
plain_home = root / "plain-kb"
plain_vault = vault(plain_home, "Vault")
(plain_vault / "个人画像.md").write_text("密码\n", encoding="utf-8")
plain_kb = kb_at(plain_home)
assert len(plain_kb["deep_reads"]) == 1
assert plain_kb["deep_reads"][0]["name"] == "个人画像.md"
assert "密码" in plain_kb["deep_reads"][0]["text"]
assert plain_kb["rejected_deep_reads"] == []

# 9. 同一路径的简历摘录不进报告，证据 JSON 仍保留。
redact_home = root / "redact"
redact_vault = vault(redact_home, "Vault")
(redact_vault / "简历.md").write_text(
    "# 电话 13800138000\n邮箱 fixture-user@example.com\n夹具自述句子壬\n",
    encoding="utf-8",
)
(redact_vault / "普通笔记.md").write_text("对照句还在夹具里\n", encoding="utf-8")
redact_desk = redact_home / "desktop"
redact_down = redact_home / "downloads"
redact_desk.mkdir()
redact_down.mkdir()
os.environ["ENV_SCANNER_HOME"] = str(redact_home)
redact_kb = collect_kb()
redact_samples = collect_samples(
    redact_vault, redact_desk, redact_down, redact_home / "no-books", "deep", []
)
redact_data = collect_counts(
    redact_vault, redact_desk, redact_down, redact_home / "no-books", "deep"
)
evidence = build_evidence(redact_data, redact_samples, {"apps": [], "sources": []}, redact_kb)
deep = evidence["deep_reads"][0]
recent = next(item for item in evidence["recent_files"] if item["name"] == "简历.md")
assert recent["path"] == deep["path"]
evidence_blob = json.dumps(evidence, ensure_ascii=False)
assert "13800138000" in evidence_blob
assert "fixture-user@example.com" in evidence_blob
assert "夹具自述句子壬" in deep["text"]
template = (skill / "templates" / "final-report.html").read_text(encoding="utf-8")
html = render(evidence, None, template)
assert "13800138000" not in html
assert "fixture-user@example.com" not in html
assert "夹具自述句子壬" not in html
assert "仅判断 AI 可读" in html
assert "与深读为同一文件" in html
assert "对照句还在夹具里" in html
assert "夹具自述句子壬" in deep["text"]

note = {
    "name": "简历.md",
    "path": "/tmp/same-resume",
    "excerpt": "SENTINEL_SAME_PATH",
    "heading": "标题哨兵甲",
    "parent": "Vault",
    "mtime": "2026-10-25 10:00:00",
}
no_path = {
    "name": "简历.md",
    "path": "",
    "excerpt": "SENTINEL_NO_PATH",
    "heading": "标题哨兵乙",
    "parent": "Vault",
    "mtime": "2026-10-25 10:00:00",
}
other = {
    "name": "简历.md",
    "path": "/tmp/other-resume",
    "excerpt": "SENTINEL_OTHER_PATH",
    "heading": "标题哨兵丙",
    "parent": "别处",
    "mtime": "2026-10-25 10:00:00",
}
synthetic = {
    "scan": {"scan_time": "t", "scan_mode": "deep", "platform": "darwin"},
    "counts": {},
    "structure": {"extensions": []},
    "activity_heat": [],
    "weekly_counts": [],
    "recent_files": [note, no_path, other],
    "deep_reads": [{
        "name": "简历.md",
        "path": "/tmp/same-resume",
        "text": "深读全文不应出现丁",
        "line_count": 2,
        "mtime": "2026-10-25 10:00:00",
    }],
    "knowledge_bases": [],
    "apps": [],
    "app_count": 0,
}
synthetic_html = render(synthetic, None, template)
assert "SENTINEL_SAME_PATH" not in synthetic_html
assert "标题哨兵甲" not in synthetic_html
assert "SENTINEL_NO_PATH" not in synthetic_html
assert "深读全文不应出现丁" not in synthetic_html
assert "仅判断 AI 可读" in synthetic_html
assert "SENTINEL_OTHER_PATH" in synthetic_html
assert note["excerpt"] == "SENTINEL_SAME_PATH"
PY
then
    pass "行为25 自述边界、日记边界、整词与办公名、缺失根、OneDrive 其余根、密钥与报告打码"
else
    fail "行为25 自述边界、日记边界、整词与办公名、缺失根、OneDrive 其余根、密钥与报告打码"
    cat "$TMP_ROOT/b25.err" >&2 || true
fi

# 行为 26：解释器选择。夹具是会退出的 shell 脚本，不解压仓库里几十 MB 的真实解释器。
PYFIX="$TMP_ROOT/pyfix"
mkdir -p "$PYFIX/WindowsApps" "$PYFIX/bad" "$PYFIX/good" "$PYFIX/env-only" "$PYFIX/vendor" "$PYFIX/stage/python/bin"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$PYFIX/WindowsApps/python3"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$PYFIX/WindowsApps/python"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$PYFIX/bad/python3"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$PYFIX/bad/python"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$PYFIX/good/python3"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$PYFIX/good/python"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$PYFIX/env-only/python3"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$PYFIX/stage/python/bin/python3"
printf 'isolated\n' > "$PYFIX/stage/python/python312._pth"
chmod 755 "$PYFIX/WindowsApps/python3" "$PYFIX/WindowsApps/python" \
    "$PYFIX/bad/python3" "$PYFIX/bad/python" \
    "$PYFIX/good/python3" "$PYFIX/good/python" \
    "$PYFIX/env-only/python3" "$PYFIX/stage/python/bin/python3"
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) PY_PLAT="mac-arm64" ;;
    Darwin-x86_64) PY_PLAT="mac-x86_64" ;;
    *) PY_PLAT="" ;;
esac
B26_OK=1
B26_ERR="$TMP_ROOT/b26.err"
: > "$B26_ERR"
if [ -z "$PY_PLAT" ]; then
    echo "当前系统无法做解释器夹具: $(uname -s) $(uname -m)" >> "$B26_ERR"
    B26_OK=0
fi
PY_PATH="$PYFIX/WindowsApps:$PYFIX/bad:$PYFIX/good:/usr/bin:/bin"
PICKED="$(
    ENV_SCANNER_RUNTIME_HOME="$PYFIX/runtime-pick" \
    ENV_SCANNER_VENDOR_DIR="$PYFIX/vendor" \
    PATH="$PY_PATH" \
    bash "$SKILL_DIR/scripts/find-python.sh" 2>>"$B26_ERR" || true
)"
if [ "$PICKED" != "$PYFIX/good/python3" ]; then
    echo "应跳过商店替身和失败解释器，实际: ${PICKED:-<空>}" >> "$B26_ERR"
    B26_OK=0
fi
ENV_OUT="$TMP_ROOT/b26-env.out"
if ENV_SCANNER_PYTHON="$PYFIX/env-only/python3" \
    ENV_SCANNER_RUNTIME_HOME="$PYFIX/runtime-env" \
    ENV_SCANNER_VENDOR_DIR="$PYFIX/vendor" \
    PATH="$PY_PATH" \
    bash "$SKILL_DIR/scripts/find-python.sh" >"$ENV_OUT" 2>>"$B26_ERR" \
    && [ "$(tr -d '[:space:]' < "$ENV_OUT")" = "$PYFIX/env-only/python3" ]; then
    :
else
    echo "ENV_SCANNER_PYTHON 没有优先" >> "$B26_ERR"
    B26_OK=0
fi
BAD_OUT="$TMP_ROOT/b26-bad.out"
if ENV_SCANNER_PYTHON="$PYFIX/bad/python3" \
    ENV_SCANNER_RUNTIME_HOME="$PYFIX/runtime-bad" \
    ENV_SCANNER_VENDOR_DIR="$PYFIX/vendor" \
    PATH="$PY_PATH" \
    bash "$SKILL_DIR/scripts/find-python.sh" >"$BAD_OUT" 2>>"$B26_ERR"; then
    echo "坏的 ENV_SCANNER_PYTHON 不应回退到其他解释器" >> "$B26_ERR"
    B26_OK=0
fi
EMPTY_ERR="$TMP_ROOT/b26-empty.err"
if ENV_SCANNER_IGNORE_SYSTEM_PYTHON=1 \
    ENV_SCANNER_VENDOR_DIR="$PYFIX/empty-vendor" \
    ENV_SCANNER_RUNTIME_HOME="$PYFIX/runtime-empty" \
    PATH="$PYFIX/bad:/usr/bin:/bin" \
    bash "$SKILL_DIR/scripts/find-python.sh" >/dev/null 2>"$EMPTY_ERR"; then
    echo "没有清单时不应成功" >> "$B26_ERR"
    B26_OK=0
elif ! grep -q "没有可用的 Python" "$EMPTY_ERR"; then
    echo "缺少清单时的提示不对" >> "$B26_ERR"
    cat "$EMPTY_ERR" >> "$B26_ERR"
    B26_OK=0
fi
if [ -n "$PY_PLAT" ]; then
    mkdir -p "$PYFIX/empty-vendor" "$PYFIX/runtime-extract"
    tar -czf "$PYFIX/vendor/fake.tar.gz" -C "$PYFIX/stage" python
    PY_SHA="$(shasum -a 256 "$PYFIX/vendor/fake.tar.gz" | awk '{print tolower($1)}')"
    printf '%s\n' "# fixture" "version 9.9.9" "$PY_PLAT $PY_SHA fake.tar.gz bin/python3 1" > "$PYFIX/vendor/manifest.txt"
    EXTRACTED="$(
        ENV_SCANNER_IGNORE_SYSTEM_PYTHON=1 \
        ENV_SCANNER_VENDOR_DIR="$PYFIX/vendor" \
        ENV_SCANNER_RUNTIME_HOME="$PYFIX/runtime-extract" \
        PATH="/usr/bin:/bin" \
        bash "$SKILL_DIR/scripts/find-python.sh" 2>>"$B26_ERR" || true
    )"
    EXPECT_BIN="$PYFIX/runtime-extract/$PY_PLAT/bin/python3"
    if [ "$EXTRACTED" != "$EXPECT_BIN" ]; then
        echo "夹具解压后的解释器不对: ${EXTRACTED:-<空>}" >> "$B26_ERR"
        B26_OK=0
    fi
    if ! python3 - "$PYFIX/runtime-extract/$PY_PLAT/python312._pth" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
assert text == "python312.zip\n.\n\nimport site\n", repr(text)
PY
    then
        echo "._pth 没有改写成可导入当前目录" >> "$B26_ERR"
        B26_OK=0
    fi
    rm -f "$PYFIX/vendor/fake.tar.gz"
    AGAIN="$(
        ENV_SCANNER_IGNORE_SYSTEM_PYTHON=1 \
        ENV_SCANNER_VENDOR_DIR="$PYFIX/vendor" \
        ENV_SCANNER_RUNTIME_HOME="$PYFIX/runtime-extract" \
        PATH="/usr/bin:/bin" \
        bash "$SKILL_DIR/scripts/find-python.sh" 2>>"$B26_ERR" || true
    )"
    if [ "$AGAIN" != "$EXPECT_BIN" ]; then
        echo "压缩包删除后应继续用已解压的解释器: ${AGAIN:-<空>}" >> "$B26_ERR"
        B26_OK=0
    fi
fi
if [ "$B26_OK" -eq 1 ]; then
    pass "行为26 解释器选择：商店替身、失败解释器、指定解释器、夹具解压与 ._pth"
else
    fail "行为26 解释器选择：商店替身、失败解释器、指定解释器、夹具解压与 ._pth"
    cat "$B26_ERR" >&2 || true
fi

echo "-----------------------------------"
echo "行为通过: $PASS"
echo "行为失败: $FAIL"
if [ "$FAIL" -eq 0 ] && [ "$PASS" -eq 26 ]; then
    exit 0
fi
exit 1
