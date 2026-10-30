#!/usr/bin/env python3
"""平台适配器选择。

操作系统差异只在 platform_mac / platform_win 里实现，其余模块通过
get_platform() 拿到适配器，不再各写一套 if darwin / if windows。
Linux 返回基础适配器（应用清单为空，其余目录逻辑通用）。

适配器接口（各平台实现保持一致）：
    name()                  -> "mac" | "windows" | "linux"
    env_path_sep()          -> 多路径环境变量的分隔符
    app_roots(config)       -> 应用清单扫描根
    collect_app_names(warnings, config) -> 已安装应用名列表
    home_discover_skip_dirs() -> 主目录发现时要跳过的目录名
    default_user_roots(home) -> {"documents","desktop","downloads","books"}
    os_version()            -> 系统版本描述
    open_html(path)         -> 用系统默认程序打开报告，返回退出码

注意：本文件不能叫 platform.py，否则会遮蔽标准库 platform 模块。
"""

import subprocess
import platform as std_platform


class LinuxAdapter:
    def name(self):
        return "linux"

    def env_path_sep(self):
        return ":"

    def app_roots(self, config):
        return []

    def collect_app_names(self, warnings, config):
        warnings.append("app_inventory_unsupported_platform:linux")
        return []

    def home_discover_skip_dirs(self):
        return {"snap", "flatpak", ".cache", ".config"}

    def default_user_roots(self, home):
        return {
            "documents": home / "Documents",
            "desktop": home / "Desktop",
            "downloads": home / "Downloads",
            "books": home / "Desktop" / "书籍",
        }

    def os_version(self):
        return std_platform.release()

    def open_html(self, path):
        completed = subprocess.run(["xdg-open", str(path)], check=False)
        return completed.returncode


def get_platform():
    import os

    forced = os.environ.get("ENV_SCANNER_PLATFORM", "").strip().lower()
    system = std_platform.system().lower()
    key = forced or system
    if key in ("darwin", "mac", "macos"):
        from platform_mac import MacAdapter

        return MacAdapter()
    if key in ("windows", "win", "win32", "cygwin"):
        from platform_win import WindowsAdapter

        return WindowsAdapter()
    return LinuxAdapter()
