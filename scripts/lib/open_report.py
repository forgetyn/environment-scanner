#!/usr/bin/env python3
"""用系统默认程序打开已经写好的 HTML 报告。

macOS 走 open，Windows 走 os.startfile（交给 .html 的默认浏览器）。
Linux 扫描本身不支持，这里只走 xdg-open，避免打开动作在该系统上直接崩溃。

ENV_SCANNER_OPEN_REPORT=0 时不打开，只打印路径。
调用方应在报告已经落盘之后调用；本脚本找不到文件时返回 1。
"""

import os
import sys
from pathlib import Path

from platforms import get_platform


def main(argv=None):
    argv = list(sys.argv if argv is None else argv)
    if len(argv) != 2:
        print("用法: python3 scripts/lib/open_report.py <report.html>", file=sys.stderr)
        return 2
    path = Path(argv[1]).expanduser()
    if not path.is_file():
        print(f"❌ 报告不存在，无法打开: {path}", file=sys.stderr)
        return 1
    resolved = path.resolve()
    if os.environ.get("ENV_SCANNER_OPEN_REPORT", "1") == "0":
        print(f"ℹ️ 已跳过自动打开报告: {resolved}")
        return 0
    try:
        code = get_platform().open_html(resolved)
    except OSError as exc:
        print(f"⚠️ 报告已生成，但自动打开失败: {resolved} ({exc})", file=sys.stderr)
        return 1
    if code:
        print(f"⚠️ 报告已生成，但自动打开失败: {resolved}", file=sys.stderr)
        return 1
    print(f"✅ 已打开报告: {resolved}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
