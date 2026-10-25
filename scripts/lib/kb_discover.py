#!/usr/bin/env python3
"""自动发现本机知识库（Obsidian/Logseq），统计写作习惯并深读自述类文档。只读。

一级：确定性的 vault 标记检测（目录下存在 .obsidian/ 或 .logseq/）。
二级：在已发现 vault 内匹配自述文档（个人总结/个人画像等）做有限深读，
      以及按文件名日期模式识别日记/周记习惯。敏感正文照旧被拒绝。
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

from common import secret_reason
from scan_collect import load_skip_rules, skip_dir, skip_file

VAULT_MARKERS = {".obsidian": "obsidian", ".logseq": "logseq"}
SELF_DOC_KEYWORDS = ("个人总结", "个人画像", "自我介绍", "关于我", "个人情况", "简历")
SELF_DOC_SUFFIXES = {".md", ".markdown", ".txt"}
DATE_NAME_RE = re.compile(r"20\d{2}[-._年]\d{1,2}(?:[-._月]\d{1,2})?")
SHORT_DATE_RE = re.compile(r"^\d{1,2}[.．-]\d{1,2}(?:[、,，\s]|$)")

DEFAULT_CONFIG = {
    "max_depth": 5,
    "dir_budget": 6000,
    "time_budget_sec": 20,
    "max_vaults": 3,
    "max_deep_reads": 3,
    "deep_read_lines": 500,
    "journal_min_files": 10,
}
DISCOVER_SKIP_DIRS = {
    "Library", "Applications", "Movies", "Music", "Pictures", "Public",
    ".Trash", "Caches", "Containers", "Group Containers",
    "node_modules", "venv", ".venv", "dist", "build", "target", "vendor",
}


def config_path():
    return Path(__file__).resolve().parents[2] / "config.json"


def load_kb_config():
    config = dict(DEFAULT_CONFIG)
    path = config_path()
    if not path.is_file():
        return config
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return config
    block = raw.get("features", {}).get("kb_discover", {})
    for key in DEFAULT_CONFIG:
        if block.get(key):
            config[key] = int(block[key])
    return config


def env_int(name, default):
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def discover_vaults(home, rules, config, warnings):
    """在主目录可见树上找 vault 标记（不进入隐藏目录，标记作为子目录探测）。"""
    found = []
    dir_budget = env_int("ENV_SCANNER_KB_DIR_BUDGET", config["dir_budget"])
    time_budget = env_int("ENV_SCANNER_KB_TIME_BUDGET_SEC", config["time_budget_sec"])
    max_depth = config["max_depth"]
    started = time.monotonic()
    state = {"visited": 0, "stopped": False}

    def budget_hit():
        if state["visited"] >= dir_budget or (time.monotonic() - started) >= time_budget:
            if not state["stopped"]:
                warnings.append("kb_budget_reached")
            state["stopped"] = True
            return True
        return False

    def skip_dir_entry(name):
        if skip_dir(name, rules):
            return True
        return name in DISCOVER_SKIP_DIRS or name.lower() in DISCOVER_SKIP_DIRS

    def enter(path, depth):
        if state["stopped"] or budget_hit():
            return
        state["visited"] += 1
        try:
            entries = list(path.iterdir())
        except (PermissionError, OSError):
            warnings.append(f"unreadable:{path}")
            return
        for entry in entries:
            if len(found) >= config["max_vaults"]:
                return
            try:
                if entry.is_symlink() or not entry.is_dir():
                    continue
            except OSError:
                continue
            name = entry.name
            if name.startswith("."):
                continue
            app = None
            for marker, marker_app in VAULT_MARKERS.items():
                try:
                    if (entry / marker).is_dir():
                        app = marker_app
                        break
                except OSError:
                    continue
            if app:
                found.append({"app": app, "path": str(entry)})
                continue
            if skip_dir_entry(name):
                continue
            if depth >= max_depth:
                continue
            enter(entry, depth + 1)

    if home.is_dir():
        enter(home, 0)
    return found


def vault_stats(vault, rules, warnings):
    """统计 vault 内的笔记数、近 7 天活跃、顶层目录分布和日记习惯。"""
    root = Path(vault["path"])
    md_files = []
    dated = {}

    def walk(path):
        try:
            entries = list(path.iterdir())
        except (PermissionError, OSError):
            warnings.append(f"unreadable:{path}")
            return
        for entry in entries:
            try:
                if entry.is_symlink():
                    continue
                if entry.is_dir():
                    if skip_dir(entry.name, rules):
                        continue
                    walk(entry)
                    continue
                if not entry.is_file() or skip_file(entry.name, rules):
                    continue
            except (PermissionError, OSError):
                continue
            if entry.suffix.lower() in {".md", ".markdown"}:
                try:
                    mtime = entry.stat().st_mtime
                except OSError:
                    continue
                md_files.append((entry, mtime))
                is_dated = bool(DATE_NAME_RE.search(entry.stem)) or bool(SHORT_DATE_RE.match(entry.stem))
                if is_dated:
                    try:
                        rel = entry.relative_to(root)
                    except ValueError:
                        continue
                    key = rel.parts[0] if len(rel.parts) > 1 else "(vault 根目录)"
                    dated.setdefault(key, []).append((entry, mtime))

    walk(root)
    now = time.time()
    recent_7d = sum(1 for _, mtime in md_files if mtime >= now - 7 * 86400)
    top_counts = {}
    for path_obj, _ in md_files:
        name = path_obj.parent.name
        if name and name != root.name:
            top_counts[name] = top_counts.get(name, 0) + 1
    top_dirs = [
        {"dir": name, "notes": count}
        for name, count in sorted(top_counts.items(), key=lambda kv: kv[1], reverse=True)[:8]
        if count >= 3
    ]
    journals = []
    for dir_name, items in sorted(dated.items(), key=lambda kv: len(kv[1]), reverse=True)[:3]:
        if len(items) < DEFAULT_CONFIG["journal_min_files"]:
            continue
        span_days = max(
            (max(m for _, m in items) - min(m for _, m in items)) / 86400, 1.0
        )
        journals.append({
            "dir": dir_name,
            "files": len(items),
            "span_days": round(span_days),
            "weekly_freq": round(len(items) / (span_days / 7), 2),
        })
    vault.update({
        "notes": len(md_files),
        "recent_notes_7d": recent_7d,
        "top_dirs": top_dirs,
        "journals": journals,
    })
    return vault


def find_self_docs(vault, rules, config, warnings):
    """在 vault 内按词典找自述类文档，按修改时间取最近几份。"""
    root = Path(vault["path"])
    hits = []

    def walk(path):
        try:
            entries = list(path.iterdir())
        except (PermissionError, OSError):
            warnings.append(f"unreadable:{path}")
            return
        for entry in entries:
            try:
                if entry.is_symlink():
                    continue
                if entry.is_dir():
                    if skip_dir(entry.name, rules):
                        continue
                    walk(entry)
                    continue
                if not entry.is_file() or skip_file(entry.name, rules):
                    continue
            except (PermissionError, OSError):
                continue
            if entry.suffix.lower() not in SELF_DOC_SUFFIXES:
                continue
            if any(keyword in entry.stem for keyword in SELF_DOC_KEYWORDS):
                try:
                    hits.append((entry, entry.stat().st_mtime))
                except OSError:
                    continue

    walk(root)
    hits.sort(key=lambda item: item[1], reverse=True)
    return [path_obj for path_obj, _ in hits[: config["max_deep_reads"]]]


def deep_read(path_obj, config, rejected):
    try:
        with path_obj.open("r", encoding="utf-8", errors="ignore") as handle:
            lines = [line.rstrip("\n") for _, line in zip(range(config["deep_read_lines"]), handle)]
    except OSError:
        return None
    text = "\n".join(lines)
    reason = secret_reason(text)
    if reason:
        rejected.append({"path": str(path_obj), "reason": reason})
        return None
    try:
        mtime = datetime.fromtimestamp(path_obj.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
    except OSError:
        mtime = ""
    return {
        "name": path_obj.name,
        "path": str(path_obj),
        "vault": path_obj.parent.name,
        "mtime": mtime,
        "line_count": len(lines),
        "text": text,
    }


def collect():
    config = load_kb_config()
    rules = load_skip_rules()
    warnings = []
    home = Path(os.environ.get("ENV_SCANNER_HOME", str(Path.home())))
    vaults = discover_vaults(home, rules, config, warnings)
    deep_reads = []
    rejected = []
    for vault in vaults:
        vault_stats(vault, rules, warnings)
        for path_obj in find_self_docs(vault, rules, config, warnings):
            record = deep_read(path_obj, config, rejected)
            if record:
                deep_reads.append(record)
    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "knowledge_bases": vaults,
        "deep_reads": deep_reads,
        "rejected_deep_reads": rejected,
        "scan_warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    payload = collect()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"知识库发现: {output}")
    print(
        f"知识库: {len(payload['knowledge_bases'])}  深读自述: {len(payload['deep_reads'])}  "
        f"拒绝: {len(payload['rejected_deep_reads'])}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
