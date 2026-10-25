#!/usr/bin/env python3
"""只读采集已安装应用名单。只收名字，不读任何应用内容和数据。"""

import argparse
import json
import os
import platform
import sys
from datetime import datetime
from pathlib import Path

DEFAULT_MAX_APPS = 400
DEFAULT_MAC_DIRS = ["/Applications", "~/Applications"]
DEFAULT_WINDOWS_PROGRAM_DIRS = [
    r"C:\Program Files",
    r"C:\Program Files (x86)",
]


def config_path():
    return Path(__file__).resolve().parents[2] / "config.json"


def load_inventory_config():
    config = {
        "max_apps": DEFAULT_MAX_APPS,
        "mac_dirs": list(DEFAULT_MAC_DIRS),
        "windows_program_dirs": list(DEFAULT_WINDOWS_PROGRAM_DIRS),
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


def clean_name(name):
    if name.endswith(".app"):
        return name[: -len(".app")]
    return name


def names_from_dirs(dirs, warnings, app_bundle_only):
    """列出目录下的一级条目名。app_bundle_only=True 时只收 *.app。"""
    names = []
    for raw_dir in dirs:
        root = Path(raw_dir).expanduser()
        if not root.is_dir():
            continue
        try:
            entries = sorted(root.iterdir(), key=lambda item: item.name)
        except PermissionError:
            warnings.append(f"unreadable:{root}")
            continue
        except OSError:
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
            if app_bundle_only and not entry.name.endswith(".app"):
                continue
            names.append(clean_name(entry.name))
    return names


def windows_registry_names(warnings):
    """Windows 卸载表里的 DisplayName。winreg 只在 Windows 存在。"""
    try:
        import winreg
    except ImportError:
        return []
    names = []
    roots = (
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
    )
    for hive, key_path in roots:
        try:
            key = winreg.OpenKey(hive, key_path)
        except OSError:
            continue
        index = 0
        while True:
            try:
                sub_name = winreg.EnumKey(key, index)
            except OSError:
                break
            index += 1
            try:
                with winreg.OpenKey(key, sub_name) as sub_key:
                    display, _ = winreg.QueryValueEx(sub_key, "DisplayName")
            except OSError:
                continue
            if isinstance(display, str) and display.strip():
                names.append(display.strip())
        winreg.CloseKey(key)
    if not names:
        warnings.append("windows_registry_unavailable")
    return names


def collect():
    config = load_inventory_config()
    warnings = []
    sources = []
    env_roots = os.environ.get("ENV_SCANNER_APPLICATIONS", "")
    if env_roots:
        dirs = [part for part in env_roots.split(":") if part]
        sources = dirs
        names = names_from_dirs(dirs, warnings, app_bundle_only=False)
    else:
        system = platform.system()
        if system == "Darwin":
            sources = list(config["mac_dirs"])
            names = names_from_dirs(sources, warnings, app_bundle_only=True)
        elif system == "Windows":
            program_dirs = [
                path
                for path in config["windows_program_dirs"]
                if Path(path).is_dir()
            ]
            sources = program_dirs
            names = windows_registry_names(warnings)
            names.extend(names_from_dirs(program_dirs, warnings, app_bundle_only=False))
        else:
            sources = []
            names = []
            warnings.append(f"app_inventory_unsupported_platform:{system}")

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
        "platform": platform.system().lower(),
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
