#!/usr/bin/env python3
"""Windows 平台适配器：注册表应用清单、AppData/junction 跳过、OneDrive 目录探测。

只依赖标准库。winreg 仅在 Windows 存在，此处做守卫导入。
本适配器的逻辑从未在真实 Windows 机器上执行过（本仓无 Windows 环境），
通过 ENV_SCANNER_PLATFORM=windows 可在 macOS 上单测除注册表外的全部分支。
"""

import platform as std_platform
from pathlib import Path


def _registry_names(warnings):
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


class WindowsAdapter:
    def name(self):
        return "windows"

    def env_path_sep(self):
        return ";"

    def app_roots(self, config):
        return [
            path
            for path in (config.get("windows_program_dirs") or [])
            if Path(path).is_dir()
        ]

    def collect_app_names(self, warnings, config):
        """注册表卸载项 + Program Files 一级目录名（只读名字）。"""
        names = _registry_names(warnings)
        for raw_dir in self.app_roots(config):
            root = Path(raw_dir)
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
                names.append(entry.name)
        return names

    def home_discover_skip_dirs(self):
        # AppData 体量巨大且不含用户文档，必须在发现预算内跳过；
        # 其余是历史 junction/系统目录名，pathlib 会穿透 junction，必须按名跳过。
        return {
            "AppData", "Application Data", "AppDataLocal", "AppDataRoaming",
            "Cookies", "NetHood", "PrintHood", "Recent", "SendTo",
            "Start Menu", "Templates", "My Documents", "My Pictures",
            "My Music", "My Videos", "OneDriveTemp", "MicrosoftEdgeBackups",
            "Saved Games", "Searches", "Links", "3D Objects",
            "Contact", "{31C248AC-742E-4EEE-A-DEL}",  # 占位，保持集合语义清晰
        }

    def default_user_roots(self, home):
        """探测 OneDrive 重定向：文档/桌面常被放进 OneDrive 目录。

        规则：若存在 OneDrive*/Documents（或 Desktop）则优先使用它，
        否则回落到主目录下的同名目录。
        """

        def resolve(kind, fallback):
            try:
                candidates = sorted(home.glob("OneDrive*"))
            except OSError:
                candidates = []
            for base in candidates:
                target = base / kind
                if target.is_dir():
                    return target
            return fallback

        documents = resolve("Documents", home / "Documents")
        desktop = resolve("Desktop", home / "Desktop")
        return {
            "documents": documents,
            "desktop": desktop,
            "downloads": home / "Downloads",
            "books": desktop / "书籍",
        }

    def os_version(self):
        try:
            version = std_platform.win32_ver()
            release = version[1] or version[0]
            if release:
                return f"Windows {release}"
        except (AttributeError, IndexError):
            pass
        return std_platform.release()
