#!/usr/bin/env python3
"""读取近期文档的有限正文。计数仍然只来自 scan_collect。"""

import argparse
import json
import os
import re
import sys
import time
import zipfile
from datetime import datetime
from html import unescape
from pathlib import Path

from common import is_noise, secret_reason
from scan_collect import RootUnreadable, load_skip_rules, skip_dir, skip_file, walk


DOCUMENT_EXTENSIONS = {".md", ".markdown", ".txt", ".csv", ".docx", ".pptx", ".pdf", ".xlsx"}
BODY_SKIPPED = {".pdf": "pdf", ".xlsx": "xlsx"}
MAX_TEXT_LINES = 200
DEFAULT_DISCOVER_SKIP = {
    "Library",
    "Applications",
    "Movies",
    "Music",
    "Pictures",
    "Public",
    ".Trash",
    "Caches",
    "Containers",
    "Group Containers",
    "node_modules",
    "venv",
    ".venv",
    "dist",
    "build",
    "target",
    "vendor",
}
DEFAULT_MODES = {
    "quick": {"recent_days": 30, "max_read_files": 0, "max_chars_per_file": 0, "max_total_chars": 0},
    "standard": {"recent_days": 30, "max_read_files": 40, "max_chars_per_file": 2000, "max_total_chars": 60000},
    "deep": {"recent_days": 90, "max_read_files": 80, "max_chars_per_file": 4000, "max_total_chars": 120000},
}


def config_path():
    return Path(__file__).resolve().parents[2] / "config.json"


def load_sample_config():
    sample = {
        "max_candidates": 120,
        "max_file_bytes": 2_000_000,
        "dir_budget": 8000,
        "time_budget_sec": 15,
        "home_depth": 4,
        "discover_skip_dir_names": set(DEFAULT_DISCOVER_SKIP),
        "modes": DEFAULT_MODES,
    }
    path = config_path()
    if not path.is_file():
        return sample
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return sample
    raw = config.get("features", {}).get("content_sample", {})
    if raw.get("max_candidates"):
        sample["max_candidates"] = int(raw["max_candidates"])
    if raw.get("max_file_bytes"):
        sample["max_file_bytes"] = int(raw["max_file_bytes"])
    if raw.get("dir_budget"):
        sample["dir_budget"] = int(raw["dir_budget"])
    if raw.get("time_budget_sec"):
        sample["time_budget_sec"] = int(raw["time_budget_sec"])
    if raw.get("home_depth"):
        sample["home_depth"] = int(raw["home_depth"])
    if raw.get("discover_skip_dir_names"):
        sample["discover_skip_dir_names"] = set(raw["discover_skip_dir_names"])
    modes = raw.get("modes") or {}
    for name, defaults in DEFAULT_MODES.items():
        override = modes.get(name) or {}
        sample["modes"][name] = {
            "recent_days": int(override.get("recent_days", defaults["recent_days"])),
            "max_read_files": int(override.get("max_read_files", defaults["max_read_files"])),
            "max_chars_per_file": int(override.get("max_chars_per_file", defaults["max_chars_per_file"])),
            "max_total_chars": int(override.get("max_total_chars", defaults["max_total_chars"])),
        }
    return sample


def env_int(name, default):
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def mode_limits(mode, sample_config):
    return sample_config["modes"].get(mode) or sample_config["modes"]["standard"]


def display_parent(path):
    parts = path.parent.parts
    if len(parts) >= 2:
        return "/".join(parts[-2:])
    return path.parent.name


def is_under(path, root):
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (OSError, ValueError):
        return False


def consider_file(path, rules, cutoff, max_bytes, explicit=False):
    name = path.name
    if skip_file(name, rules):
        return None
    suffix = path.suffix.lower()
    if suffix not in DOCUMENT_EXTENSIONS:
        return None
    try:
        stat = path.stat()
    except OSError:
        return None
    if not explicit and stat.st_mtime < cutoff:
        return None
    return {
        "path": path,
        "mtime": stat.st_mtime,
        "size": stat.st_size,
        "explicit": explicit,
        "too_large": stat.st_size > max_bytes,
    }


def discover_files(home, rules, warnings, roots, cutoff, limits, sample_config):
    found = []
    if not home.exists() or not home.is_dir():
        return found
    dir_budget = env_int("ENV_SCANNER_SAMPLE_DIR_BUDGET", sample_config["dir_budget"])
    time_budget = env_int("ENV_SCANNER_SAMPLE_TIME_BUDGET_SEC", sample_config["time_budget_sec"])
    max_depth = sample_config["home_depth"]
    extra_skip = {name.lower() for name in sample_config["discover_skip_dir_names"]}
    started = time.monotonic()
    state = {"visited": 0, "stopped": False}

    def budget_hit():
        if state["visited"] >= dir_budget or (time.monotonic() - started) >= time_budget:
            if not state["stopped"]:
                warnings.append("sample_budget_reached")
            state["stopped"] = True
            return True
        return False

    def skip_discover_dir(entry):
        if skip_dir(entry.name, rules):
            return True
        if entry.name.lower() in extra_skip:
            return True
        for root in roots:
            if root.exists() and is_under(entry, root):
                return True
        return False

    def enter(path, depth):
        if state["stopped"] or budget_hit():
            return
        state["visited"] += 1
        try:
            entries = sorted(path.iterdir(), key=lambda item: item.name)
        except PermissionError:
            warnings.append(f"unreadable:{path}")
            return
        except OSError:
            warnings.append(f"unreadable:{path}")
            return
        files = []
        dirs = []
        for entry in entries:
            try:
                if entry.is_symlink():
                    continue
                if entry.is_dir():
                    if skip_discover_dir(entry):
                        continue
                    dirs.append(entry)
                elif entry.is_file():
                    files.append(entry)
            except PermissionError:
                warnings.append(f"unreadable:{entry}")
        for entry in files:
            item = consider_file(entry, rules, cutoff, sample_config["max_file_bytes"])
            if item:
                found.append(item)
        if depth >= max_depth:
            return
        for entry in dirs:
            enter(entry, depth + 1)

    enter(home, 0)
    return found


def read_text_limited(path):
    lines = []
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            for _ in range(MAX_TEXT_LINES):
                line = handle.readline()
                if not line:
                    break
                lines.append(line)
    except OSError:
        return None
    return "".join(lines)


def office_xml_text(path, names):
    try:
        with zipfile.ZipFile(path) as archive:
            present = [name for name in names if name in archive.namelist()]
            if not present and names == ["pptx"]:
                present = sorted(
                    [name for name in archive.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", name)],
                    key=lambda name: int(re.search(r"(\d+)", name).group(1)),
                )[:3]
            chunks = []
            for name in present:
                raw = archive.read(name).decode("utf-8", errors="ignore")
                raw = re.sub(r"</w:p>", "\n", raw)
                raw = re.sub(r"<[^>]+>", " ", raw)
                chunks.append(unescape(raw))
            return "\n".join(chunks)
    except (OSError, zipfile.BadZipFile, KeyError):
        return None


def extract_body(path, suffix):
    if suffix in {".md", ".markdown", ".txt"}:
        return read_text_limited(path)
    if suffix == ".csv":
        text = read_text_limited(path)
        if text is None:
            return None
        return text.splitlines()[0] if text.splitlines() else ""
    if suffix == ".docx":
        return office_xml_text(path, ["word/document.xml"])
    if suffix == ".pptx":
        return office_xml_text(path, ["pptx"])
    return ""


def split_heading_excerpt(text, char_limit):
    heading = ""
    kept = []
    total = 0
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        match = re.match(r"^#{1,6}\s+(.*)$", stripped)
        if match and not heading:
            heading = match.group(1).strip()[:120]
            continue
        if is_noise(stripped):
            continue
        if total >= char_limit:
            break
        piece = stripped[: max(char_limit - total, 0)]
        if not piece:
            break
        kept.append(piece)
        total += len(piece)
    excerpt = "\n".join(kept)
    if char_limit <= 0:
        return heading, ""
    return heading, excerpt[:char_limit]


def build_record(item, char_limit, total_state):
    path = item["path"]
    suffix = path.suffix.lower()
    record = {
        "name": path.name,
        "parent": display_parent(path),
        "parent_name": path.parent.name,
        "path": str(path),
        "mtime": datetime.fromtimestamp(item["mtime"]).strftime("%Y-%m-%d %H:%M:%S"),
        "mtime_epoch": int(item["mtime"]),
        "extension": suffix,
        "heading": "",
        "excerpt": "",
        "body_skipped": "",
        "rejected": False,
        "explicit": bool(item["explicit"]),
    }
    if item["too_large"]:
        record["body_skipped"] = "too_large"
        return record, None
    if suffix in BODY_SKIPPED:
        record["body_skipped"] = BODY_SKIPPED[suffix]
        return record, None
    if char_limit <= 0 or total_state["remaining"] <= 0:
        record["body_skipped"] = "not_read"
        return record, None
    text = extract_body(path, suffix)
    if text is None:
        return None, f"unreadable:{path}"
    reason = secret_reason(text)
    if reason:
        return None, {"path": str(path), "reason": reason}
    limit = min(char_limit, total_state["remaining"])
    heading, excerpt = split_heading_excerpt(text, limit)
    record["heading"] = heading
    record["excerpt"] = excerpt
    total_state["remaining"] -= len(excerpt)
    return record, None


def collect_samples(documents, desktop, downloads, books, mode, explicit_paths):
    rules = load_skip_rules()
    sample_config = load_sample_config()
    limits = mode_limits(mode, sample_config)
    warnings = []
    roots = [documents, desktop, downloads, books]
    for root in roots:
        if root.exists():
            try:
                next(root.iterdir(), None)
            except PermissionError as exc:
                raise RootUnreadable(root) from exc
            if not root.is_dir():
                raise RootUnreadable(root)

    cutoff = time.time() - limits["recent_days"] * 86400
    candidates = []
    for root in roots:
        for path in walk(root, rules, warnings):
            item = consider_file(path, rules, cutoff, sample_config["max_file_bytes"])
            if item:
                candidates.append(item)

    discover = os.environ.get("ENV_SCANNER_DISCOVER_HOME", "1") != "0"
    if discover:
        home = Path(os.environ.get("ENV_SCANNER_HOME", str(Path.home())))
        candidates.extend(
            discover_files(home, rules, warnings, roots, cutoff, limits, sample_config)
        )

    seen = set()
    explicit_items = []
    for raw in explicit_paths:
        path = Path(raw).expanduser()
        if not path.is_file() or path.is_symlink():
            continue
        item = consider_file(path, rules, cutoff, sample_config["max_file_bytes"], explicit=True)
        if not item:
            continue
        key = str(path.resolve())
        if key in seen:
            continue
        seen.add(key)
        item["key"] = key
        explicit_items.append(item)

    unique = []
    ordered = explicit_items + sorted(candidates, key=lambda row: row["mtime"], reverse=True)
    for item in ordered:
        key = item.get("key") or str(item["path"].resolve())
        if key in seen and not item["explicit"]:
            continue
        if not item["explicit"]:
            seen.add(key)
        unique.append(item)
        if len(unique) >= sample_config["max_candidates"]:
            break

    read_budget = limits["max_read_files"]
    total_state = {"remaining": limits["max_total_chars"]}
    files = []
    rejected = []
    read_count = 0
    for item in unique:
        suffix = item["path"].suffix.lower()
        can_read = (
            read_count < read_budget
            and not item["too_large"]
            and suffix not in BODY_SKIPPED
        )
        char_limit = limits["max_chars_per_file"] if can_read else 0
        if can_read:
            read_count += 1
        record, problem = build_record(item, char_limit, total_state)
        if isinstance(problem, dict):
            rejected.append(problem)
            continue
        if isinstance(problem, str):
            warnings.append(problem)
            continue
        if record:
            files.append(record)

    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "scan_mode": mode,
        "recent_days": limits["recent_days"],
        "files": files,
        "rejected_documents": rejected,
        "scan_warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--mode", default="deep")
    parser.add_argument("--explicit", nargs="*", default=[])
    args = parser.parse_args()
    mode = args.mode if args.mode in {"quick", "standard", "deep"} else "deep"
    home = Path.home()
    documents = Path(os.environ.get("ENV_SCANNER_DOCUMENTS", home / "Documents"))
    desktop = Path(os.environ.get("ENV_SCANNER_DESKTOP", home / "Desktop"))
    downloads = Path(os.environ.get("ENV_SCANNER_DOWNLOADS", home / "Downloads"))
    books = Path(os.environ.get("ENV_SCANNER_BOOKS", desktop / "书籍"))
    output = Path(args.output)
    try:
        payload = collect_samples(documents, desktop, downloads, books, mode, args.explicit)
    except RootUnreadable as exc:
        print(f"扫描根不可读: {exc}", file=sys.stderr)
        return 1
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"样本文件: {output}")
    print(f"近期文档: {len(payload['files'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
