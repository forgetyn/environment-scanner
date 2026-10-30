# Environment Scanner - Codex Project Memory

本文件只放全局性信息：项目定位、当前快照、结构、已知限制、开发约定。所有变更记录（版本变更 / 修复历史 / 归档动作）一律记录在 `CHANGELOG.md`，本文件不再重复维护。

## 项目定位

这是一个 `environment-scanner` skill，面向非技术背景的普通用户：他们不知道自己做的事情哪些可以用 AI 提效、先做哪个、该给 AI 什么信息。skill 只读扫描用户的近期文档与已安装应用收集证据，由会话 AI 基于证据判断"哪几件事适合交给 AI、第一件怎么开始"，判断必须通过本地确定性校验后渲染最终报告。

## 当前快照（2026-10-26）

- 工作目录：`/Users/forget/skills/mine/environment-scanner`
- 版本：`v4.3.0`（`SKILL.md` / `config.json` / `scripts/run-scan.sh` / `scripts/run-scan.ps1` / `scripts/lib/evidence_pack.py` / `scripts/lib/judgment.py` 对齐）
- 解释器：`scripts/find-python.sh` 与 `scripts/find-python.ps1` 同一顺序。能运行的系统 Python（≥ 3.9）优先；否则把 `runtime/vendor/` 里的 CPython 3.12.14 解压到 `~/.environment-scanner/runtime/<平台>-<架构>/`。用户不用安装 Python。扫描过程不下载解释器
- 架构：脚本收证据（计数+结构聚合 / 采样 / 应用清单 / 知识库发现与自述深读）+ 会话 AI 两层判断（诊断+综合+三件套）+ 本地校验渲染（图表数据确定性注入）。操作系统差异在 `platforms.py` + `platform_mac.py` / `platform_win.py`，其余模块不写双分支
- 采集层：`scripts/lib/scan_collect.py`、`sample_content.py`、`app_inventory.py`、`kb_discover.py`（经适配器取应用清单、发现跳过、默认根、系统版本）
- 证据层：`scripts/lib/evidence_pack.py` → `environment-scanner-evidence-*.json`（structure / activity_heat / weekly_counts(26周) / ai_usage_signals / knowledge_bases / deep_reads）
- 判断层：`scripts/lib/judgment.py` + `scripts/generate-final-report.sh`（Windows 为 `generate-final-report.ps1`）；合同 v4：persona / diagnosis / understanding 四卡 / 三件套建议(kind, 上限10) / 优先级三段式 / cadence / assets / structure_advice；引用双通道（文件名 + 聚合指标 metric ref）
- 报告：`templates/final-report.html`（v1.2 风格八大区块 + Chart.js 四图，图表数据由渲染器从证据注入）。最终报告写好后自动打开（macOS `open`，Windows `os.startfile`；`ENV_SCANNER_OPEN_REPORT=0` 关闭）。证据报告不自动打开
- 默认扫描深度：`deep`；默认输出目录：`$HOME/.environment-scanner/reports`。近期样本最多 120 个名额：工作文件按目录轮转（每目录 8），日记最多 8（每目录 3），下载最多 12，书籍最多 4；正文仍最多 80 份。日记目录来自知识库配置（Obsidian daily-notes / 已启用的 periodic-notes，Logseq journals-directory 或默认 `journals`），不看文件名是否像日期。计数不按模式截断，但安装包、压缩包、日志、私钥文件和软件数据目录不计入
- 全流程不出站（Chart.js 为报告查看时的 CDN 库加载，不上传数据）
- 本地归档目录：`bak/`（2026-03-13 与 2026-10-25 两批；含 v3.1 模板留档）
- git 仓库已初始化（2026-10-25，为开源发布准备）；`.gitignore` 挡住：`bak/`、真实扫描产物（`examples/report/` 内容 + 任意位置 `environment-scanner-*.json|html`）、`.DS_Store`、`__pycache__/`、`.claude/settings.local.json`、`.serena/`、`.zcode/plans/`、编辑器目录；`examples/report/` 以 `.gitkeep` 保持空目录占位

## 目录结构与核心文件入口

- `SKILL.md`：触发描述、两步工作流、判断准则（rubric）、安全边界、校验规则
- `README.md`：面向 GitHub 用户的中文项目介绍（安装 / 使用 / 隐私 / 限制 / 开发）
- `scripts/run-scan.sh`：bash 扫描入口（计数 → 采样 → 应用清单 → 知识库 → 证据合并 + 证据报告）
- `scripts/run-scan.ps1`：Windows 原生扫描入口，调用同一套 Python 库，不需要 Git Bash。未在真实 Windows 上执行
- `scripts/collect-data.sh`：bash 计数包装。旧 `collect-data.ps1` 已归档到 `bak/scripts/2026-10-25/`
- `scripts/find-python.sh` / `scripts/find-python.ps1`：选择解释器。`ENV_SCANNER_PYTHON` 优先；设了但不能用就停。商店替身（路径含 `WindowsApps`）不启动
- `scripts/generate-final-report.sh`：校验 AI 判断并渲染最终报告，成功后调用 `scripts/lib/open_report.py` 打开
- `scripts/generate-final-report.ps1`：Windows 最终报告入口。未在真实 Windows 上执行
- `runtime/vendor/`：四个平台的 CPython 3.12.14 压缩包、`manifest.txt`、许可证。只入库压缩包，解压目录在用户主目录
- `scripts/lib/`：`common.py`、`platforms.py`、`platform_mac.py`、`platform_win.py`、`scan_collect.py`、`sample_content.py`、`app_inventory.py`、`kb_discover.py`、`evidence_pack.py`、`judgment.py`、`open_report.py`
- `templates/final-report.html`：唯一报告模板（最终报告与证据报告共用，section 合同 overview/suggestions/priorities/evidence）
- `config.json`：默认深度、跳过规则、采样与清单上限、判断合同
- `tests/test-skill.sh`（快速检查）/ `tests/test-skill-behavior.sh`（行为回归，26 项）/ `tests/test-skill-full.sh`（全量回归，46 项）：仅开发迭代使用，技能运行时不依赖

## 归档说明

- `bak/` 仅本地保留（已被 `.gitignore` 排除，不在仓库中）：2026-10-25 归档旧渲染链（`bak/scripts|lib|templates/2026-10-25`），2026-03-13 归档 v1 时代文件（`bak/docs|templates|reports|misc/2026-03-13`）
- 归档映射记录：`bak/manifests/move-manifest-2026-10-25.txt`、`bak/manifests/move-manifest-2026-03-13.txt`
- `examples/report` 保持空目录（`.gitkeep` 占位）

## 已知限制与待处理

1. Windows 实机回归仍未做：`run-scan.ps1`、`find-python.ps1`、`generate-final-report.ps1`、`winreg` 卸载表、报告打开用的 `os.startfile` 都只在 macOS 上用强制平台、替身或人工审查验证过。内容采样走 Python（`sample_content.py`）。32 位 Windows 不支持。从网络下载的技能目录里，macOS 可能拦住未签名的自带解释器；脚本不会清除隔离标记，也不会关闭 Gatekeeper。
2. PDF 和 xlsx 正文在采样层仍不解析（文件只在 evidence 里带名字）；判断时可以由会话 AI 直接读这些文件补足。
3. Windows GBK 文本：采样按 UTF-8 忽略无法解码的字节，记事本类 txt/csv 可能缺字。本版不引入编码探测。

历史问题的修复记录见 `CHANGELOG.md` 对应版本节。

## 启动后建议先做的快速检查

```bash
cd /Users/forget/skills/mine/environment-scanner
jq . config.json >/dev/null
bash -n scripts/run-scan.sh
bash -n scripts/find-python.sh
bash -n scripts/generate-final-report.sh
python3 -m py_compile scripts/lib/*.py
bash tests/test-skill.sh
bash tests/test-skill-behavior.sh
bash tests/test-skill-full.sh
```

## 迭代约束

- 以 `SKILL.md` 作为行为语义真相源（含判断准则与判断文件合同）
- 以 `config.json` 作为配置真相源（只保留真实生效字段）
- 每次改动必须同步 `CHANGELOG.md`
- 回归门槛："核心脚本语法 + 判断校验矩阵 + 渲染合同完整性"，三套测试 0 失败 0 警告

## 文档留痕规则（强制）

每次更新或修改代码/配置/流程时，必须至少同步以下文档：

1. `CHANGELOG.md`：记录本次改动内容和日期
2. `AGENTS.md`：更新当前快照或已知问题状态（如有变化）
3. 若涉及归档/迁移，必须新增或更新 `bak/manifests/move-manifest-<date>.txt`

## 经验沉淀（避免重复犯错）

1. 任何"支持 X 模式"的声明都必须由脚本参数与输出字段双重验证；config 里不保留脚本不消费的字段。
2. 配置文件改动后必须立即执行 `jq . config.json`，避免提交无效 JSON。
3. 测试脚本禁止写死用户路径，统一基于脚本所在目录解析；夹具全部放临时目录。
4. 每次修复必须形成闭环：记录问题 -> 修复 -> 测试 -> 更新文档与经验。
5. 在 `set -euo pipefail` 场景下避免 `find | head`，优先使用 `awk` 限流计数。
6. 语义质量判断交给会话 AI，但必须配本地确定性校验（引用存在性、文件名落进提示词、零信号强制空），否则会回到"套话建议"老路。
7. 对"深度报告"先保证可重复骨架，再逐步提升语义质量。
8. 删除/归档旧链路时同步写 manifest，保证可恢复、可追溯。
9. 同一补丁号在 python.org 有源码包，不代表有 Windows embeddable zip。3.12.14 只有源码包，自带运行环境用的是 python-build-standalone 的 `install_only` 压缩包。
