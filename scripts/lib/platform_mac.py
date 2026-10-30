#!/usr/bin/env python3
"""macOS 平台适配器：应用清单、主目录发现、用户目录默认值、系统版本。"""

import os
import platform as std_platform
import subprocess
from pathlib import Path


class MacAdapter:
    def name(self):
        return "mac"

    def env_path_sep(self):
        return ":"

    def app_roots(self, config):
        return list(config.get("mac_dirs") or ["/Applications", "~/Applications"])

    def collect_app_names(self, warnings, config):
        """只读 /Applications 与 ~/Applications 的一级 .app 名字，不读应用内容。"""
        names = []
        for raw_dir in self.app_roots(config):
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
                if not entry.name.endswith(".app"):
                    continue
                names.append(entry.name[: -len(".app")])
        return names

    def home_discover_skip_dirs(self):
        return {
            "Library", "Applications", "Movies", "Music", "Pictures", "Public",
            ".Trash", "Caches", "Containers", "Group Containers",
        }

    def default_user_roots(self, home):
        return {
            "documents": home / "Documents",
            "desktop": home / "Desktop",
            "downloads": home / "Downloads",
            "books": home / "Desktop" / "书籍",
        }

    def os_version(self):
        try:
            return (
                subprocess.check_output(
                    ["sw_vers", "-productVersion"], text=True, stderr=subprocess.DEVNULL
                ).strip()
                or std_platform.release()
            )
        except (OSError, subprocess.CalledProcessError):
            return std_platform.release()

    def open_html(self, path):
        """用默认应用打开报告。返回 open 的退出码。"""
        completed = subprocess.run(["open", os.fspath(path)], check=False)
        return completed.returncode
