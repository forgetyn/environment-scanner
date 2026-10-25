# Environment Scanner - Codex Project Memory

## 项目定位

这是一个 `environment-scanner` skill，面向非技术背景的普通用户：他们不知道自己做的事情哪些可以用 AI 提效、先做哪个、该给 AI 什么信息。skill 只读扫描用户的近期文档与已安装应用收集证据，由会话 AI 基于证据判断"哪几件事适合交给 AI、第一件怎么开始"，判断必须通过本地确定性校验后渲染最终报告。

## 当前快照（2026-10-25）

- 工作目录：`/Users/forget/skills/mine/environment-scanner`
- 版本：`v4.0.0`（`SKILL.md` / `config.json` / `scripts/run-scan.sh` 对齐）
- 架构：脚本收证据（计数+结构聚合 / 采样 / 应用清单 / 知识库发现与自述深读）+ 会话 AI 两层判断（诊断+综合+三件套）+ 本地校验渲染（图表数据确定性注入）
- 采集层：`scripts/lib/scan_collect.py`、`sample_content.py`、`app_inventory.py`、`kb_discover.py`
- 证据层：`scripts/lib/evidence_pack.py` → `environment-scanner-evidence-*.json`（structure / activity_heat / weekly_counts(26周) / ai_usage_signals / knowledge_bases / deep_reads）
- 判断层：`scripts/lib/judgment.py` + `scripts/generate-final-report.sh`；合同 v4：persona / diagnosis / understanding 四卡 / 三件套建议(kind, 上限10) / 优先级三段式 / cadence / assets / structure_advice；引用双通道（文件名 + 聚合指标 metric ref）
- 报告：`templates/final-report.html`（v1.2 风格八大区块 + Chart.js 四图，图表数据由渲染器从证据注入）
- 默认扫描深度：`deep`；默认输出目录：`$HOME/.environment-scanner/reports`
- 全流程不出站（Chart.js 为报告查看时的 CDN 库加载，不上传数据）
- 本地归档目录：`bak/`（2026-03-13 与 2026-10-25 两批；含 v3.1 模板留档）
- git 仓库已初始化（2026-10-25，为开源发布准备）；`.gitignore` 挡住：`bak/`、真实扫描产物（`examples/report/` 内容 + 任意位置 `environment-scanner-*.json|html`）、`.DS_Store`、`__pycache__/`、`.claude/settings.local.json`、`.serena/`、`.zcode/plans/`、编辑器目录；`examples/report/` 以 `.gitkeep` 保持空目录占位

## 核心文件入口

- `SKILL.md`：触发描述、两步工作流、判断准则（rubric）、安全边界、校验规则
- `scripts/run-scan.sh`：唯一扫描入口（计数 → 采样 → 应用清单 → 证据合并 + 证据报告）
- `scripts/collect-data.sh` / `scripts/collect-data.ps1`：计数包装（bash / PowerShell）
- `scripts/generate-final-report.sh`：校验 AI 判断并渲染最终报告
- `scripts/lib/`：`common.py`、`scan_collect.py`、`sample_content.py`、`app_inventory.py`、`evidence_pack.py`、`judgment.py`
- `templates/final-report.html`：唯一报告模板（最终报告与证据报告共用，section 合同 overview/suggestions/priorities/evidence）
- `config.json`：默认深度、跳过规则、采样与清单上限、判断合同
- `test-skill.sh` / `test-skill-behavior.sh`（18 项）/ `test-skill-full.sh`（28 项）
- `bak/manifests/move-manifest-2026-10-25.txt`：旧渲染链归档映射
- `bak/manifests/move-manifest-2026-03-13.txt`：v1 时代归档映射

## 归档状态

- 2026-10-25：旧渲染链归档至 `bak/scripts/2026-10-25`、`bak/lib/2026-10-25`、`bak/templates/2026-10-25`（render-dynamic / hybrid×2 / deep / preview / extract-insights / generate-report-spec / report_spec.py / 三个旧模板）
- 2026-03-13：`bak/docs|templates|reports|misc/2026-03-13`
- `examples/report` 保持空目录

## 已确认问题（当前状态）

### 已修复（2026-10-25，v4.0.0）
1. 「报告越改越差」：恢复 v1.2 报告形态（八大区块+图表+叙事），根因是输入深度/综合自由度/呈现质量三个乘数被历次安全修复逐个牺牲；本版在保留 v3 防幻觉管道的前提下把三个乘数补回。
2. 「聚合洞察被禁」：引用双通道让基于聚合指标的建议（如沉睡书库）合法且可验证。
3. 「图表数据靠 AI 手填」（v1.2 自身缺陷）：图表数字全部由渲染器从证据确定性注入。
4. 「自述深读依赖用户手动提供」：知识库自动发现（Obsidian/Logseq vault 标记 + 自述词典 + 日记量化），非技术用户零操作。
5. 隐私：深读正文不进报告原始 JSON；实测联系方式不外漏。

### 已修复（2026-10-25，v3.1.0）
1. 「已在用 AI 的事被重复推荐基础用法」：判断新增 AI 使用程度评估（none/occasional/deep），深度活动只给升级型建议，且无 AI 使用证据时校验拒绝升级型建议。
2. 「报告缺整体视角」：新增全局诊断层（每件事的 AI 使用程度 + 时间占用 + 一句话最大剩余机会），证据层补结构信号（activity_heat / weekly_counts / structure 聚合）。
3. 「报告基调不区分用户」：persona 画像（novice/power）由 ai_usage_signals 推断，报告基调随之切换；power 画像强制至少一条升级型建议。

### 已修复（2026-10-25，v3.0.0）
1. 建议语义错位：从"把这份文件交给 AI 总结"改为"这件事里 AI 能替你做哪部分 + 第一步 + 预期省掉什么"（三件套）。
2. 应用信号缺失：新增 `app_inventory.py`，只读收集应用名单（macOS 目录枚举 + Windows 注册表），系统自带应用由判断准则忽略。
3. "可提效"无判断模型：语义判断交给会话 AI，SKILL.md 内置判断准则（AI 提效机会模式清单），本地校验防幻觉。
4. 优先级等于活跃度排序：改为快见效优先，校验强制"存在快见效建议时第一条必须是快见效项"。
5. 建议价值陈述写死：三件套中 `expected_saving` 每条由判断生成。
6. 动态出站渲染链维护负担：整链归档，全流程不出站。

### 历史已修复
- 2026-10-21（v2.2.0 / v2.1.0）：建议证据绑定、零信号不凑建议、动态渲染默认关闭且脱敏、输出落点收敛、计数不被模式截断、私钥过滤等（详见 CHANGELOG）。
- 2026-03-13：mktemp 兼容、suggestion-card 正则误判、动态渲染超时、回退可观测性、混合报告叙事层。
- 2026-03-06：config.json 合法性、Windows 计数脚本、scan_mode 生效、敏感目录过滤、版本对齐、预览/深度报告自动化。

### 待处理
1. Windows 实机回归：`app_inventory.py` 的 `winreg` 分支、`run-scan.sh` 的 `python3||python` 探测、`shutil.disk_usage` 均未在真实 Windows 机器上跑过；内容采样也未移植到 PowerShell。
2. PDF 和 xlsx 正文在采样层仍不解析（文件只在 evidence 里带名字）；判断时可以由会话 AI 直接读这些文件补足。

## 启动后建议先做的快速检查

```bash
cd /Users/forget/skills/mine/environment-scanner
jq . config.json >/dev/null
bash -n scripts/run-scan.sh
bash -n scripts/generate-final-report.sh
python3 -m py_compile scripts/lib/*.py
bash test-skill.sh
bash test-skill-behavior.sh
bash test-skill-full.sh
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

## 最近一次变更记录

- 2026-10-25：执行 v4.0.0「恢复 v1.2 报告体验」改造（起因：用户对比 2026-03-05 的 v1.2 报告后反馈越改越差），包含：
  - 第一性原理复盘：报告价值 = 输入深度 × 综合自由度 × 呈现质量，三个乘数分别在 v2.1/v2.2/v1.3.x+v2.1 被牺牲
  - 新增 `kb_discover.py`（vault 标记检测、日记习惯量化、自述文档深读 500 行、私钥拒绝）
  - 判断合同 v4：understanding 四卡 / assets / cadence / structure_advice / 优先级三段式 / 引用双通道（文件+聚合指标）/ 建议上限 10 / deep_reads 可引用
  - 模板重写为 v1.2 风格八大区块 + Chart.js 四图（数据确定性注入，CDN 仅加载库）；旧 v3.1 模板留档 bak
  - 隐私加固：深读正文不进报告 raw JSON
  - 回归：行为 21 项 / 全量 29 项，0 失败 0 警告。真实验证：发现 911 篇 Obsidian vault、双日记（83+60 篇）、深读 3 份自述，真实判断一次通过校验
  - Windows 侧未在本机执行

- 2026-10-25：执行 v3.1.0 分层判断改造（响应用户对真实报告的复盘：活动识别准但建议缺整体视角、报税建议是已做过的事），包含：
  - 判断分两层：全局诊断（persona + AI 使用程度 + 时间占用 + 整体结论）与三件套建议（新增 kind: basic/upgrade）
  - 证据层结构信号：`scan_collect.py` 的 top_dirs/extensions 聚合，`evidence_pack.py` 的 activity_heat/weekly_counts/ai_usage_signals
  - 校验新增分层合同（persona/diagnosis/kind、无据不升级、power 必有升级型），行为回归新增行为 19，共 19 项
  - 真实复扫：120 近期文件 / 46 应用 / 35 份带 AI 痕迹 / 10 个 AI 应用 → power 画像，真实分层判断一次通过校验并渲染
  - 回归：`test-skill-full.sh` 28 通过 / 0 失败 / 0 警告。Windows 未在本机执行

- 2026-10-25：执行 v3.0.0 架构反转（脚本收证据 + 会话 AI 判断 + 本地校验渲染），包含：
  - 需求对齐确认四个决策：AI 判断机制、应用清单作参考信号（兼容 mac/win）、建议三件套、第一条先推最快见效的小事
  - 新增 `app_inventory.py`（macOS 目录 + Windows 注册表，纯 stdlib）、`evidence_pack.py`、`judgment.py`、`common.py`、`generate-final-report.sh`、`templates/final-report.html`
  - `run-scan.sh` 重排四阶段；`scan_collect.py` 磁盘统计跨平台化
  - 旧渲染链（7 脚本 + 1 lib + 3 模板）归档至 `bak/2026-10-25` 并写 manifest；动态出站渲染彻底移除
  - 测试重写：行为回归 18 项、全量回归 28 项，全部通过（0 失败 0 警告）
  - 真实主目录冒烟：120 近期文件 + 46 应用 → 真实判断一次通过校验并渲染最终报告
  - 同步更新 `SKILL.md`、`config.json`、`CHANGELOG.md`
  - Windows 侧未在本机执行，维持待实机回归

## 历史变更记录（摘要）

- 2026-10-21：v2.2.0 内容主题改造（建议来自近期文件、可复制提示、删除固定候选，行为回归扩到 19 项）；v2.1.0 行为与安全修复（计数/敏感路径/权限/脱敏/默认深度，新增 `scan_collect.py` 与 `report_spec.py`）。
- 2026-03-13：混合报告前端质量增强；渲染稳定性修复（mktemp/正则/超时/可观测性）；文档精简；v2.0.0 动态化报告改造（report-spec 中间层 + 双模式渲染）；Aggressive 本地归档清理（bak/ + manifest）。
- 2026-03-06：v1.3.6 混合方案（速度+质量平衡）；P0+P1+P2 深度自动化（config 修复、Windows 计数脚本、scan_mode 生效、敏感过滤、预览/深度报告自动化）。

## 经验沉淀（避免重复犯错）

1. 任何"支持 X 模式"的声明都必须由脚本参数与输出字段双重验证；config 里不保留脚本不消费的字段。
2. 配置文件改动后必须立即执行 `jq . config.json`，避免提交无效 JSON。
3. 测试脚本禁止写死用户路径，统一基于脚本所在目录解析；夹具全部放临时目录。
4. 每次修复必须形成闭环：记录问题 -> 修复 -> 测试 -> 更新文档与经验。
5. 在 `set -euo pipefail` 场景下避免 `find | head`，优先使用 `awk` 限流计数。
6. 语义质量判断交给会话 AI，但必须配本地确定性校验（引用存在性、文件名落进提示词、零信号强制空），否则会回到"套话建议"老路。
7. 对"深度报告"先保证可重复骨架，再逐步提升语义质量。
8. 删除/归档旧链路时同步写 manifest，保证可恢复、可追溯。
