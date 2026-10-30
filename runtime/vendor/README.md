# 自带的 Python

这里是随工具一起分发的 CPython 3.12.14 压缩包。用户不用自己安装 Python。

扫描入口会先用电脑上已经能运行、且版本不低于 3.9 的解释器。没有合格解释器时，把对应压缩包解压到 `~/.environment-scanner/runtime/`，再用那里的绝对路径。不改系统 PATH，也不要管理员权限。

四个包都来自 [python-build-standalone](https://github.com/astral-sh/python-build-standalone/releases/tag/20260825) 的 `install_only` 构建（发布号 `20260825`）。python.org 的 3.12.14 目录没有提供 Windows embeddable zip，所以 Windows 用同一套可解压构建。解释器本身是 CPython，许可证见 `LICENSE-CPython.txt`。构建脚本的上游仓库另有自己的许可证；这里分发的是编好的解释器。

校验和写在 `manifest.txt`。解压前会核对，对不上就停止。

从网络下载整个技能目录时，macOS 可能提示这个未签名的解释器无法打开。那是系统的安全提示。本机复制或 git 检出通常不会出现。脚本不会自动关闭这项保护。
