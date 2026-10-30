# 任务计划：Windows 平台适配器改造（environment-scanner v4.1.0）

> 断线恢复指引：读完本文件 + `findings.md` + `progress.md` 即可继续。
> 按「阶段状态」找到第一个未完成阶段接着做；每完成一个阶段必须回来更新状态。

## 目标

1. 对抗性审查暴露的 Windows 兼容硬伤全部修复。
2. 操作系统差异收进独立的平台适配器（`platform_mac.py` / `platform_win.py`），其余模块不再混写 if darwin / if windows 双分支。
3. Windows 提供原生 PowerShell 入口（`run-scan.ps1`），无需 Git Bash。
4. 版本升 `v4.1.0`，三套测试全绿，真实 mac 复扫无回归。

## 关键决策（不要偏离）

| 决策 | 内容 | 理由 |
|------|------|------|
| D1 适配器而非全盘复制 | 只拆 OS 差异（应用清单/发现跳过/用户目录/系统版本/路径分隔符），80% OS 无关逻辑保持单一实现 | 全盘复制会使维护翻倍；项目 2.x 曾因重复渲染链买单（已归档教训） |
| D2 多路径分隔符统一为 `;` | `ENV_SCANNER_APPLICATIONS`、`ENV_SCANNER_INSIGHT_DOCS` 都改用 `;` | `:` 会切碎 Windows 盘符路径；mac 路径不含 `;` |
| D3 平台可强制覆盖 | `ENV_SCANNER_PLATFORM=windows|darwin` 可强制适配器选择 | 让 Windows 代码路径在 mac 上可单测（除 winreg） |
| D4 适配器文件不能叫 `platform.py` | 命名为 `platforms.py`（选择器）+ `platform_mac.py` / `platform_win.py` | `platform.py` 会遮蔽标准库 platform 模块（lib 目录在 sys.path） |
| D5 collect-data.ps1 归档 | 被 run-scan.ps1 + Python 采集完全取代 | 它只有计数、落后 v4 合同，留着制造"已支持"错觉 |
| D6 ps1 入口标注未实机验证 | 本机无 PowerShell（已确认），run-scan.ps1 只做人工审查 | 如实声明，不做虚假验证声明 |

## 阶段

### 阶段 0：对抗性审查 + 方案确认 — ✅ complete
产出见 findings.md「对抗性审查结论」。5 个问题：分隔符×2 处、CRLF、AppData/junction 穿透预算、OneDrive 静默空证据；另有 GBK 编码乱码（不修，记录）。

### 阶段 1：平台适配器三文件 — ✅ complete
- `scripts/lib/platforms.py`（选择器 + Linux 兜底适配器 + ENV_SCANNER_PLATFORM 覆盖）
- `scripts/lib/platform_mac.py`（.app 枚举 / mac 跳过目录 / 默认根 / sw_vers）
- `scripts/lib/platform_win.py`（winreg 卸载表 + Program Files / AppData+junction 跳过 / OneDrive 探测 / win32_ver）
- 已 `py_compile` 通过；未做行为测试（阶段 5 覆盖）

### 阶段 2：四个采集模块接适配器 — ✅ complete
- `app_inventory.py`：已重写——删除自身 darwin/winreg 分支与平台枚举，改 `adapter.collect_app_names()`；`ENV_SCANNER_APPLICATIONS` 分隔符来自 `adapter.env_path_sep()`；`platform` 字段用 `adapter.name()`
- `kb_discover.py`：跳过名单 = `adapter.home_discover_skip_dirs() ∪ BUILD_TOOL_DIRS`（补回 node_modules/venv 等构建目录）
- `sample_content.py`：`discover_skip` = config 名单 ∪ adapter 名单 ∪ 构建目录；默认四根改 `adapter.default_user_roots()`
- `scan_collect.py`：`system_info()` 版本改 `adapter.os_version()`（删除 sw_vers 分支与 subprocess 依赖）；默认四根改适配器
- 验收：`py_compile` 全过；`bash tests/test-skill-behavior.sh` 21/21 全绿（适配后 mac 无回归）
- 备注：仓库在此期间被外部整理（测试移入 `tests/` 且已自带 `dirname/..` 修正、新增 README.md、新增 .gitignore、清理了 .zcode/.serena/.claude）——已确认与本阶段改动无冲突

### 阶段 3：硬伤修复 + 开源卫生 — ✅ complete
- `.gitignore` 已由外部整理提供
- `run-scan.sh` 的 `IFS=':'` 已改为 `IFS=';'`
- 新建 `.gitattributes`（`*.sh`/`*.py` eol=lf，`*.ps1` eol=crlf）
- 验收：`bash -n` 通过

### 阶段 4：Windows 原生入口 — ✅ complete
- 新建 `scripts/run-scan.ps1`：镜像 run-scan.sh 五阶段（python 调用相同 lib），PowerShell 原生，无需 Git Bash。UTF-8 BOM + CRLF
- 归档 `scripts/collect-data.ps1` → `bak/scripts/2026-10-25/`，已写入 manifest
- 验收：人工逐行审查（本机无 pwsh）。文件头注明「未实机验证」。审查记录见 progress.md

### 阶段 5：测试 — ✅ complete
- 行为 22、23 在计划写成之后已经存在（报告自动打开、样本名额）。平台适配器测试顺延为行为 24，断言与计划里的「行为 22」相同
- mac 实路径：sep=`:`、`Library` 在跳过名单。`ENV_SCANNER_PLATFORM=windows`：sep=`;`、`AppData` 在跳过名单、OneDrive fixture 命中 `OneDrive/Documents`、无 winreg 时 `windows_registry_unavailable`
- 行为 15 仍用冒号：它跑在 mac 适配器上，mac 的 `env_path_sep()` 按本阶段合同仍是 `:`。Windows 多项分隔由行为 24 覆盖
- 顺手补上：`ImportError` 时也写 `windows_registry_unavailable`（原先只有注册表打开后为空才警告）
- 验收：行为 24/24、全量 33，0 失败 0 警告

### 阶段 6：真实 mac 复扫回归 — ✅ complete
- `bash scripts/run-scan.sh` → `environment-scanner-evidence-2026-10-25-215203.json`
- 对照 174604：120 文件 / 46 应用（名单相同）/ 1 vault / 日记 83+60。证据报告九个区块都在
- 笔记 912（174604 为 911，20:53 已是 912）。周频 2.71→2.70，持续天数仍是 215

### 阶段 7：文档同步 — ✅ complete
- `SKILL.md`：v4.1.0；「平台架构」小节；安全边界补 OneDrive、跳过名单、分隔符、GBK
- `config.json`：version 4.1.0（windows_program_dirs 等键保留）
- `CHANGELOG.md`：[4.1.0] 条目。此前 Unreleased 的样本名额、自动打开、测试目录移动一并写入 4.1.0
- `AGENTS.md`：快照、文件入口、待处理（Windows 实机回归、GBK）
- 版本号对齐：SKILL.md / config.json / run-scan.sh / run-scan.ps1 / evidence_pack.py / judgment.py

## 遇到的错误

| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| （暂无） | | |

## 完成定义

阶段 0-7 全部 complete；三套测试 0 失败 0 警告；真实复扫指标与 4.0.0 一致；文档留痕齐全。
