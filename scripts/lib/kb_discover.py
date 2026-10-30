#!/usr/bin/env python3
"""自动发现本机知识库（Obsidian/Logseq），统计写作习惯并深读自述类文档。只读。

一级：确定性的 vault 标记检测（Obsidian 为目录 .obsidian/，Logseq 为文件 logseq/config.edn）。
二级：在已发现 vault 内匹配自述文档（个人总结/个人画像等）做有限深读，
      并按该库自己的日记配置统计习惯。不看文件名像不像日期。敏感正文照旧被拒绝。
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
from platforms import get_platform
from scan_collect import load_skip_rules, skip_dir, skip_file

def is_obsidian_vault(path):
    try:
        return (Path(path) / ".obsidian").is_dir()
    except OSError:
        return False


def is_logseq_graph(path):
    """Logseq 文件图的标记是文件 logseq/config.edn，不是子目录 .logseq/。"""
    try:
        return (Path(path) / "logseq" / "config.edn").is_file()
    except OSError:
        return False


SELF_DOC_KEYWORDS = ("个人总结", "个人画像", "自我介绍", "关于我", "个人情况", "简历")
SELF_DOC_SUFFIXES = {".md", ".markdown", ".txt"}
# 「关于我们」「如何写简历」「简历模板」不是这个人的自述。
SELF_DOC_REJECT_MARKERS = ("关于我们", "如何", "怎么", "怎样", "教程", "模板", "范文", "示例")

DEFAULT_CONFIG = {
    "max_depth": 5,
    "dir_budget": 6000,
    "time_budget_sec": 20,
    "max_vaults": 3,
    "max_deep_reads": 3,
    "deep_read_lines": 500,
    "journal_min_files": 10,
}
BUILD_TOOL_DIRS = {"node_modules", "venv", ".venv", "dist", "build", "target", "vendor"}


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
    """在主目录可见树上找 vault 标记。点开头的目录先跳过，再看标记。"""
    adapter = get_platform()
    platform_skip = adapter.home_discover_skip_dirs() | BUILD_TOOL_DIRS
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
        return name in platform_skip or name.lower() in platform_skip

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
            if is_obsidian_vault(entry):
                app = "obsidian"
            elif is_logseq_graph(entry):
                app = "logseq"
            else:
                app = None
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


PERIODIC_KINDS = ("daily", "weekly", "monthly", "quarterly")
NOTE_SUFFIXES = {".md", ".markdown"}


def _strip_edn_comments(text):
    lines = []
    for line in text.splitlines():
        if ";" in line:
            line = line.split(";", 1)[0]
        lines.append(line)
    return "\n".join(lines)


def _read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return None


def _folder_inside(vault, folder):
    """配置里的日记目录必须落在库内。绝对路径和 .. 不接受。"""
    text = str(folder or "").strip().replace("\\", "/")
    if not text or text.startswith("/") or text.startswith("~"):
        return None
    if ".." in Path(text).parts:
        return None
    target = (vault / text).resolve()
    try:
        target.relative_to(vault.resolve())
    except ValueError:
        return None
    return target


def _journal_spec(vault, folder, kind, fmt):
    path = _folder_inside(vault, folder)
    if path is None:
        return None
    return {
        "path": path,
        "kind": kind,
        "format": str(fmt or ""),
        "dir": str(folder).strip().replace("\\", "/"),
    }


def _dedupe_specs(specs):
    seen = set()
    result = []
    for spec in specs:
        key = (str(spec["path"]), spec["kind"])
        if key in seen:
            continue
        seen.add(key)
        result.append(spec)
    return result


def obsidian_journal_specs(vault):
    """日记目录只来自 Obsidian 自己写的配置，不看文件名像不像日期。"""
    specs = []
    daily = _read_json(vault / ".obsidian" / "daily-notes.json")
    if isinstance(daily, dict):
        spec = _journal_spec(vault, daily.get("folder"), "daily", daily.get("format"))
        if spec:
            specs.append(spec)
    periodic = _read_json(vault / ".obsidian" / "plugins" / "periodic-notes" / "data.json")
    if isinstance(periodic, dict):
        for kind in PERIODIC_KINDS:
            block = periodic.get(kind)
            if not isinstance(block, dict) or not block.get("enabled"):
                continue
            spec = _journal_spec(vault, block.get("folder"), kind, block.get("format"))
            if spec:
                specs.append(spec)
    return _dedupe_specs(specs)


def logseq_journal_specs(vault):
    """Logseq 的日记目录写在 config.edn。没写时用它自己的默认目录 journals。"""
    warnings = []
    config_path = vault / "logseq" / "config.edn"
    directory = None
    fmt = ""
    saw_directory_key = False
    if config_path.is_file():
        try:
            raw = config_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            raw = ""
        cleaned = _strip_edn_comments(raw)
        if ":journals-directory" in cleaned:
            saw_directory_key = True
            match = re.search(r':journals-directory\s+"([^"]*)"', cleaned)
            if not match:
                # 只接受裸目录名。`(str "journals")` 这种写不成路径，不猜。
                match = re.search(
                    r":journals-directory\s+([A-Za-z0-9_./\\-]+)",
                    cleaned,
                )
            if match:
                directory = match.group(1)
            else:
                warnings.append(f"journal_config_unparsed:{config_path}")
                return [], warnings
        fmt_match = re.search(r':journal/page-title-format\s+"([^"]*)"', cleaned)
        if fmt_match:
            fmt = fmt_match.group(1)
    if directory is None:
        directory = "journals"
        if saw_directory_key or not (vault / directory).is_dir():
            return [], warnings
    spec = _journal_spec(vault, directory, "daily", fmt)
    if spec is None:
        warnings.append(f"journal_config_unparsed:{config_path}")
        return [], warnings
    return [spec], warnings


def journal_specs(vault):
    """返回 (目录说明, 警告)。目录说明含 path、kind、format、dir。"""
    vault = Path(vault)
    specs = []
    warnings = []
    if is_obsidian_vault(vault):
        specs.extend(obsidian_journal_specs(vault))
    if is_logseq_graph(vault):
        found, found_warnings = logseq_journal_specs(vault)
        specs.extend(found)
        warnings.extend(found_warnings)
    return _dedupe_specs(specs), warnings


def find_vaults(root, rules, max_depth):
    """在有限深度内找 Obsidian 或 Logseq 图。找到后不再往库里嵌套找。"""
    found = []
    root = Path(root)
    if not root.exists() or not root.is_dir():
        return found

    def rec(path, depth):
        try:
            if is_obsidian_vault(path) or is_logseq_graph(path):
                found.append(path)
                return
        except OSError:
            return
        if depth >= max_depth:
            return
        try:
            entries = list(path.iterdir())
        except OSError:
            return
        for entry in entries:
            try:
                if entry.is_symlink() or not entry.is_dir():
                    continue
            except OSError:
                continue
            if entry.name.startswith(".") or skip_dir(entry.name, rules):
                continue
            rec(entry, depth + 1)

    rec(root, 0)
    return found


def markdown_files(root, rules):
    found = []
    root = Path(root)
    if not root.is_dir():
        return found

    def walk(path):
        try:
            entries = list(path.iterdir())
        except (PermissionError, OSError):
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
                if (
                    entry.is_file()
                    and not skip_file(entry.name, rules)
                    and entry.suffix.lower() in NOTE_SUFFIXES
                ):
                    found.append((entry, entry.stat().st_mtime))
            except (PermissionError, OSError):
                continue

    walk(root)
    return found


def vault_stats(vault, rules, warnings, config):
    """统计 vault 内的笔记数、近 7 天活跃、顶层目录分布和日记习惯。"""
    root = Path(vault["path"])
    md_files = []

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
    specs, spec_warnings = journal_specs(root)
    warnings.extend(spec_warnings)
    min_files = int(config.get("journal_min_files", DEFAULT_CONFIG["journal_min_files"]))
    ranked = []
    for spec in specs:
        items = markdown_files(spec["path"], rules)
        if len(items) < min_files:
            continue
        span_days = max(
            (max(mtime for _, mtime in items) - min(mtime for _, mtime in items)) / 86400,
            1.0,
        )
        ranked.append((len(items), {
            "dir": spec["dir"],
            "kind": spec["kind"],
            "format": spec["format"],
            "files": len(items),
            "span_days": round(span_days),
            "weekly_freq": round(len(items) / (span_days / 7), 2),
        }))
    journals = [item for _, item in sorted(ranked, key=lambda pair: pair[0], reverse=True)[:3]]
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
            if not stem_matches_self_doc(entry.stem):
                continue
            try:
                hits.append((entry, entry.stat().st_mtime))
            except OSError:
                continue

    walk(root)
    hits.sort(key=lambda item: item[1], reverse=True)
    return [path_obj for path_obj, _ in hits]


def stem_matches_self_doc(stem):
    """关键词要独占文件名，或位于文件名末尾。子串不再算。"""
    if any(marker in stem for marker in SELF_DOC_REJECT_MARKERS):
        return False
    return any(stem == keyword or stem.endswith(keyword) for keyword in SELF_DOC_KEYWORDS)


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
    pending = []
    for vault in vaults:
        vault_stats(vault, rules, warnings, config)
        pending.extend(find_self_docs(vault, rules, config, warnings))
    def newest(path_obj):
        try:
            return path_obj.stat().st_mtime
        except OSError:
            return 0

    pending.sort(key=newest, reverse=True)
    for path_obj in pending[: config["max_deep_reads"]]:
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
