#!/usr/bin/env python3
"""只读采集用来判断用户在做什么的文件。

计数不按扫描模式截断。安装包、压缩包、日志、私钥文件和软件数据目录不计入。
"""

import argparse
import json
import os
import platform
import re
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

from platforms import get_platform


DEFAULT_SKIP_DIR_NAMES = {
    ".ssh",
    ".gnupg",
    ".aws",
    ".kube",
    "Keychains",
    ".git",
    "node_modules",
    "__pycache__",
    "venv",
    ".venv",
    "dist",
    "build",
    "target",
    "vendor",
    "QQ",
    "Tencent Files",
    "WeChat",
    "WeChat Files",
    "xwechat_files",
    "微信",
    "DingTalk",
    "WXWork",
    "log",
    "logs",
    "crash",
    "crashes",
    "CrashReporter",
    "Crashpad",
    "cache",
    "Caches",
    "tmp",
    "temp",
    "__MACOSX",
}
DEFAULT_SKIP_FILE_NAMES = {
    ".env", "credentials.json", "id_rsa", "id_ed25519", "id_ecdsa", "id_dsa",
}
DEFAULT_SKIP_FILE_SUFFIXES = {
    ".pem", ".p12", ".kdbx", ".ppk", ".pfx", ".cer", ".crt", ".p8", ".keystore",
    ".dmg", ".pkg", ".exe", ".msi", ".msix", ".apk", ".deb", ".rpm", ".appimage",
    ".zip", ".rar", ".7z", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".iso", ".cab",
    ".log",
}
DEFAULT_SKIP_SUBSTRINGS = ("wallet", "crypto", "seed")
SENSITIVE_TOKEN_RE = re.compile(r"[\s_]+")


class RootUnreadable(Exception):
    def __init__(self, path):
        super().__init__(str(path))
        self.path = str(path)


def config_path():
    return Path(__file__).resolve().parents[2] / "config.json"


def load_skip_rules():
    rules = {
        "dir_names": set(DEFAULT_SKIP_DIR_NAMES),
        "file_names": set(DEFAULT_SKIP_FILE_NAMES),
        "suffixes": set(DEFAULT_SKIP_FILE_SUFFIXES),
        "substrings": DEFAULT_SKIP_SUBSTRINGS,
    }
    path = config_path()
    if path.is_file():
        try:
            config = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            config = {}
        filtering = config.get("features", {}).get("smart_filtering", {})
        if filtering.get("skip_dir_names"):
            rules["dir_names"] = set(filtering["skip_dir_names"])
        if filtering.get("skip_file_names"):
            rules["file_names"] = set(filtering["skip_file_names"])
        if filtering.get("skip_file_suffixes"):
            rules["suffixes"] = {s.lower() for s in filtering["skip_file_suffixes"]}
        if filtering.get("skip_file_substrings"):
            rules["substrings"] = tuple(s.lower() for s in filtering["skip_file_substrings"])
    rules["dir_names_folded"] = {name.casefold() for name in rules["dir_names"]}
    return rules


def name_has_sensitive_token(name, tokens):
    """wallet / crypto / seed 按整词匹配，避免吃掉 seed-round 这种普通文件名。

    整段文件名（去掉扩展名）相等，或被空格、下划线切开后有一段相等，才跳过。
    连字符不切开，所以种子轮材料还在。
    """
    lowered = name.lower()
    suffix = Path(lowered).suffix
    stem = lowered[: -len(suffix)] if suffix else lowered
    parts = [part for part in SENSITIVE_TOKEN_RE.split(stem) if part]
    token_set = {token.lower() for token in tokens}
    return any(part in token_set for part in parts)


def skip_dir(name, rules):
    """点开头、应用包、软件数据目录、日志和缓存目录不往下走。

    目录名整段相等，忽略大小写。QQ笔记 这种用户自己的目录不在名单里。
    """
    if name.startswith("."):
        return True
    if name.lower().endswith(".app"):
        return True
    folded = rules.get("dir_names_folded")
    if folded is None:
        folded = {item.casefold() for item in rules["dir_names"]}
    if name.casefold() in folded:
        return True
    return name_has_sensitive_token(name, rules["substrings"])


def skip_file(name, rules):
    if name in rules["file_names"] or name.lower() in {n.lower() for n in rules["file_names"]}:
        return True
    suffix = Path(name).suffix.lower()
    if suffix in rules["suffixes"]:
        return True
    return name_has_sensitive_token(name, rules["substrings"])


def assert_root_readable(root):
    if not root.exists():
        return
    if not root.is_dir():
        raise RootUnreadable(root)
    try:
        next(root.iterdir(), None)
    except PermissionError as exc:
        raise RootUnreadable(root) from exc


def human_size(num):
    size = float(num)
    units = ["B", "K", "M", "G", "T"]
    for unit in units:
        if size < 1024 or unit == "T":
            if unit == "B":
                return f"{int(size)}B"
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{int(num)}B"


def disk_usage():
    try:
        usage = shutil.disk_usage(str(Path.home()))
        total = usage.total
        used = usage.total - usage.free
        return {
            "total": human_size(total),
            "used": human_size(used),
            "available": human_size(usage.free),
            "percent": f"{round(used / total * 100)}%" if total else "0%",
        }
    except (OSError, ZeroDivisionError):
        return {"total": "0B", "used": "0B", "available": "0B", "percent": "0%"}


def system_info():
    if "ENV_SCANNER_HOSTNAME_OVERRIDE" in os.environ:
        hostname = os.environ["ENV_SCANNER_HOSTNAME_OVERRIDE"]
    else:
        hostname = platform.node()
    return {
        "os": platform.system(),
        "version": get_platform().os_version(),
        "kernel": platform.release(),
        "arch": platform.machine(),
        "hostname": hostname,
        "username": os.environ.get("USER") or os.environ.get("USERNAME") or "unknown",
    }


def walk(root, rules, warnings, max_depth=None):
    files = []
    if not root.exists():
        return files
    assert_root_readable(root)

    def rec(path, depth):
        try:
            entries = list(path.iterdir())
        except PermissionError:
            warnings.append(f"unreadable:{path}")
            return
        for entry in entries:
            try:
                if entry.is_symlink():
                    continue
                if entry.is_dir():
                    if skip_dir(entry.name, rules):
                        continue
                    if max_depth is not None and depth >= max_depth:
                        continue
                    rec(entry, depth + 1)
                    continue
                if entry.is_file() and not skip_file(entry.name, rules):
                    files.append(entry)
            except PermissionError:
                warnings.append(f"unreadable:{entry}")

    rec(root, 1)
    return files


def file_size(path, warnings):
    try:
        return path.stat().st_size
    except PermissionError:
        warnings.append(f"unreadable:{path}")
        return 0


def sum_sizes(paths, warnings):
    return sum(file_size(path, warnings) for path in paths)


def count_desktop_dirs(root, rules, warnings):
    if not root.exists():
        return 0
    assert_root_readable(root)
    try:
        entries = list(root.iterdir())
    except PermissionError:
        warnings.append(f"unreadable:{root}")
        return 0
    total = 0
    for entry in entries:
        try:
            if entry.is_symlink() or not entry.is_dir():
                continue
            if skip_dir(entry.name, rules):
                continue
            total += 1
        except PermissionError:
            warnings.append(f"unreadable:{entry}")
    return total


def rank_counts(counts, limit, min_count=1):
    ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
    return [{"name": name, "count": count} for name, count in ranked if count >= min_count][:limit]


def dir_counts(paths, limit=12, min_files=3):
    counts = {}
    for path in paths:
        name = path.parent.name
        if not name:
            continue
        counts[name] = counts.get(name, 0) + 1
    return [
        {"name": item["name"], "files": item["count"]}
        for item in rank_counts(counts, limit, min_files)
    ]


def extension_counts(paths, limit=10):
    counts = {}
    for path in paths:
        suffix = path.suffix.lower() or "(无扩展名)"
        counts[suffix] = counts.get(suffix, 0) + 1
    return [
        {"extension": item["name"], "files": item["count"]}
        for item in rank_counts(counts, limit)
    ]


def collect(documents, desktop, downloads, books, mode):
    rules = load_skip_rules()
    warnings = []
    for root in (documents, desktop, downloads, books):
        if not root.exists():
            warnings.append(f"missing_root:{root}")
            continue
        assert_root_readable(root)

    doc_files = walk(documents, rules, warnings)
    desktop_all = walk(desktop, rules, warnings)
    download_files = walk(downloads, rules, warnings)
    markdown = [path for path in doc_files if path.suffix.lower() == ".md"]
    cutoff = time.time() - 7 * 86400
    recent = []
    for path in markdown:
        try:
            if path.stat().st_mtime >= cutoff:
                recent.append(path)
        except PermissionError:
            warnings.append(f"unreadable:{path}")
    ebooks = walk(books, rules, warnings)
    desktop_files = walk(desktop, rules, warnings, max_depth=2)
    all_files = doc_files + desktop_all + download_files + ebooks
    structure = {
        "top_dirs": dir_counts(all_files),
        "extensions": extension_counts(all_files),
    }
    storage = {
        "documents": sum_sizes(doc_files, warnings),
        "desktop": sum_sizes(desktop_all, warnings),
        "downloads": sum_sizes(download_files, warnings),
    }
    return {
        "scan_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "scan_mode": mode,
        "platform": platform.system().lower(),
        "system": system_info(),
        "disk": disk_usage(),
        "files": {
            "obsidian_notes": len(markdown),
            "ebooks": len(ebooks),
            "desktop_dirs": count_desktop_dirs(desktop, rules, warnings),
            "desktop_files": len(desktop_files),
            "recent_notes_7d": len(recent),
        },
        "storage": {key: human_size(value) for key, value in storage.items()},
        "storage_bytes": storage,
        "structure": structure,
        "scan_limits": {
            "max_items_per_query": None,
            "count_is_total": True,
        },
        "scan_scope": {
            "type": "user_files_only",
            "excluded": [
                "system",
                "logs",
                "cache",
                "sensitive_dirs",
                "installers",
                "archives",
                "app_data_dirs",
            ],
            "app_names_read_separately": True,
        },
        "scan_warnings": warnings,
    }


def normalize_mode(mode):
    if mode in {"quick", "standard", "deep"}:
        return mode
    print(f"⚠️ 未知扫描模式: {mode}，回退到 deep", file=sys.stderr)
    return "deep"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--mode", default="deep")
    args = parser.parse_args()
    home = Path.home()
    roots = get_platform().default_user_roots(home)
    documents = Path(os.environ.get("ENV_SCANNER_DOCUMENTS") or roots["documents"])
    desktop = Path(os.environ.get("ENV_SCANNER_DESKTOP") or roots["desktop"])
    downloads = Path(os.environ.get("ENV_SCANNER_DOWNLOADS") or roots["downloads"])
    books = Path(os.environ.get("ENV_SCANNER_BOOKS") or roots["books"])
    mode = normalize_mode(args.mode)
    try:
        payload = collect(documents, desktop, downloads, books, mode)
    except RootUnreadable as exc:
        print(f"❌ 扫描根目录不可读，已停止且不写输出: {exc.path}", file=sys.stderr)
        return 1
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"✅ 数据收集完成: {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
