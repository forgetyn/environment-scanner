#!/usr/bin/env python3
"""只读采集已安装应用名单。只收名字，不读任何应用内容和数据。

平台差异（macOS 的 .app 目录 / Windows 的注册表卸载表）在
platform_mac / platform_win 适配器里实现，本模块只负责配置、
环境变量覆盖、去重和上限。多路径环境变量的分隔符来自适配器
（macOS 用 ':'，Windows 用 ';'）。
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

from platforms import get_platform

DEFAULT_MAX_APPS = 400


def config_path():
    return Path(__file__).resolve().parents[2] / "config.json"


def load_inventory_config():
    config = {
        "max_apps": DEFAULT_MAX_APPS,
        "mac_dirs": ["/Applications", "~/Applications"],
        "windows_program_dirs": [
            r"C:\Program Files",
            r"C:\Program Files (x86)",
        ],
    }
    path = config_path()
    if not path.is_file():
        return config
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return config
    block = raw.get("features", {}).get("app_inventory", {})
    if block.get("max_apps"):
        config["max_apps"] = int(block["max_apps"])
    if block.get("mac_dirs"):
        config["mac_dirs"] = [str(item) for item in block["mac_dirs"]]
    if block.get("windows_program_dirs"):
        config["windows_program_dirs"] = [str(item) for item in block["windows_program_dirs"]]
    return config


def names_from_dirs(dirs, warnings):
    """列出目录下的一级目录名（兼容 .app 包与普通目录），用于环境变量覆盖的测试根。"""
    names = []
    for raw_dir in dirs:
        root = Path(raw_dir).expanduser()
        if not root.is_dir():
            continue
        try:
            entries = sorted(root.iterdir(), key=lambda item: item.name)
        except (PermissionError, OSError):
            warnings.append(f"unreadable:{root}")
            continue
        for entry in entries:
            if entry.name.startswith("."):
                continue
            try:
                if entry.is_symlink() or not entry.is_dir():
                    continue
            except OSError:
                continue
            name = entry.name
            if name.endswith(".app"):
                name = name[: -len(".app")]
            names.append(name)
    return names


def collect():
    adapter = get_platform()
    config = load_inventory_config()
    warnings = []
    env_roots = os.environ.get("ENV_SCANNER_APPLICATIONS", "")
    if env_roots:
        sources = [part for part in env_roots.split(adapter.env_path_sep()) if part]
        names = names_from_dirs(sources, warnings)
    else:
        sources = adapter.app_roots(config)
        names = adapter.collect_app_names(warnings, config)

    unique = []
    seen = set()
    for name in names:
        key = name.casefold()
        if not name or key in seen:
            continue
        seen.add(key)
        unique.append(name)
    unique.sort()
    truncated = len(unique) > config["max_apps"]
    apps = unique[: config["max_apps"]]
    if truncated:
        warnings.append("app_list_truncated")
    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "platform": adapter.name(),
        "apps": apps,
        "app_count": len(apps),
        "sources": sources,
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
    print(f"应用清单: {output}")
    print(f"应用数量: {payload['app_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
