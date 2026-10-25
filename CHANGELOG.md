# 更新日志

本文件用于记录 Environment Scanner Skill 的所有重要变更。

格式参考 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)，
并遵循 [语义化版本规范](https://semver.org/spec/v2.0.0.html)。

## [Unreleased]

### 变更
- 测试脚本从根目录移至 `tests/`（`tests/test-skill.sh` / `tests/test-skill-behavior.sh` / `tests/test-skill-full.sh`），并修正脚本内 `SKILL_DIR` 定位（指向仓库根）与脚本间互相引用路径。测试脚本仅用于开发迭代，技能运行时不依赖，行为不变。移动后回归验证：快速 / 行为 21 项 / 全量 29 项，0 失败 0 警告。
- 重构 `AGENTS.md` 为纯全局指南（项目定位 / 当前快照 / 目录结构与核心文件入口 / 归档说明 / 已知限制与待处理 / 快速检查 / 迭代约束 / 留痕规则 / 经验沉淀）；原文件内的变更记录与修复历史全部并入 `CHANGELOG.md`（各版本节已完整覆盖同等内容，无信息丢失），此后变更记录只在 `CHANGELOG.md` 维护。

### 仓库管理
- 新增中文 `README.md`：项目定位、工作原理（采集 → 判断 → 校验渲染）、报告八大区块、安装（ZCode / Claude Code 技能目录）、对话触发用法与手动两步命令、扫描深度对照表、隐私与安全边界、环境变量表、平台支持与已知限制、开发测试入口。
- 开源发布准备：新增 `.gitignore` 并初始化 git 仓库。不入库内容：本地归档 `bak/`（旧版本留档 + 历史真实报告）、真实扫描产物（`examples/report/` 内容与任意位置生成的 `environment-scanner-*.json|html`，含个人数据）、macOS/Python/编辑器文件（`.DS_Store`、`__pycache__/`、`.idea/` 等）、本地 AI 工具文件（`.claude/settings.local.json`、`.serena/`、`.zcode/plans/`）。`examples/report/` 以 `.gitkeep` 占位保持空目录。

## [4.0.0] - 2026-10-25

### 变更
- 报告形态回归 v1.2 的完整体验：八大区块（用户画像 / 整体理解四张卡 / 数据可视化 / 建议 / 长期协作 / 三段式优先级 / 高价值资产发现 / 文件结构建议），暗色视觉、导航、Chart.js 图表。此前三个版本"越改越薄"的根因是：输入深度（v2.1 删自述文档）、综合自由度（v2.2 禁聚合洞察）、呈现质量（v1.3.x 模板化 + v2.1 关动态渲染）被逐个牺牲换安全。
- 图表数字全部由渲染器从证据确定性注入（文件类型分布 / 活跃领域雷达 / 26 周活跃趋势 / 时间分配），判断文件不含图表数据，AI 无法手填——修复 v1.2 报告自身编造雷达图数据的问题。
- 建议上限从 8 放宽到 10；文件引用集合扩展到 `deep_reads`。
- 版本号对齐为 `v4.0.0`（`SKILL.md` / `config.json` / `scripts/run-scan.sh` / `scripts/lib/evidence_pack.py` / `scripts/lib/judgment.py`）。

### 新增
- 新增 `scripts/lib/kb_discover.py`：知识库自动发现（用户思路）——一级：Obsidian（`.obsidian/`）/ Logseq（`.logseq/`）vault 标记检测 + 笔记统计 + 顶层目录分布 + 日记习惯量化（按一级目录聚合日期命名文件：篇数/持续天数/周均）；二级：自述文档词典匹配（个人总结/个人画像/自我介绍/关于我/个人情况/简历）最近 3 份深读至 500 行，私钥与口令照旧拒绝。`ENV_SCANNER_KB_DISCOVER=0` 可关。
- 判断合同 v4：`understanding`（整体理解四卡，每条可挂 basis 引用）、`cadence`（日/周/月协作节奏）、`assets`（资产发现）、`structure_advice`、优先级三段式（`why`/`how_to_start[]`/`long_term[]`）；**引用双通道**——文件名或聚合指标（`{"type":"metric","ref":"counts.ebooks"}`，dotted path 必须真实存在），"198 本电子书是沉睡资产"这类聚合洞察重新合法且可验证。
- 报告隐私加固：深读正文不再进入报告的原始 JSON 折叠区（仅保留文件名与行数）；实测简历中的手机号与邮箱不会出现在报告任何位置。
- 行为回归新增行为 20（指标双通道）与行为 21（知识库发现），共 21 项；全量回归 29 通过 / 0 失败 / 0 警告。

### 说明
- Chart.js 经 CDN 加载（只拉取库文件，不上传任何数据），离线打开时图表区自动降级为提示。
- 真实主目录验证：自动发现 1 个 Obsidian vault（911 篇、近 7 天 44 篇）、量化出双日记习惯（83 篇/215 天 + 60 篇/284 天）、深读 3 份自述文档；真实 v4 判断一次通过校验并渲染完整报告。
- 旧 `templates/final-report.html`（v3.1 轻量版）留档于 `bak/templates/2026-10-25/final-report-v3.1.html`。

## [3.1.0] - 2026-10-25

### 变更
- 判断从一层改为两层：新增「全局诊断层」（persona 画像 + 每件事的 AI 使用程度 + 时间占用粗估 + 一句话整体结论），具体建议层保持三件套。
- 建议新增 `kind` 字段：`basic`（基础用法，只给没用过/偶尔用 AI 的活动）和 `upgrade`（升级用法，把深度用户的一次性 AI 用法变成可重复流程）。已经深度用 AI 的事不再推荐基础用法——修复「把用户已经在做的事再推荐一遍」的问题。
- 报告基调按画像切换：novice 教从零开始，power 讲「把零散用法变成系统」。
- 版本号对齐为 `v3.1.0`（`SKILL.md` / `config.json` / `scripts/run-scan.sh` / `scripts/lib/evidence_pack.py` / `scripts/lib/judgment.py`）。

### 新增
- 证据层结构信号：`evidence_pack.py` 新增 `activity_heat`（最活跃目录及最近活跃天数）、`weekly_counts`（按周数量分布）、`sample_extensions`、`ai_usage_signals`（近期文件里的 AI 痕迹标记数与 AI 应用清单）；`scan_collect.py` 新增 `structure.top_dirs` 与 `structure.extensions` 全量聚合。
- 校验新规则：persona/diagnosis/kind 缺失或非法被拒；无任何 AI 使用证据时不允许升级型建议；画像为 power 时必须至少一条升级型建议；诊断活动最多 8 条且 activity/ai_usage/time_note 齐全。
- 报告模板新增诊断表格（在做的事 / AI 使用程度 / 时间占用）、整体结论框、基础/升级徽章。
- 行为回归新增行为 19（判断分层合同矩阵），共 19 项；全量回归 28 通过 / 0 失败 / 0 警告。

### 说明
- `collect-data.ps1` 未加 structure 聚合（Windows 实机仍未回归；Windows 侧全链路走 Python 采集时自然获得该字段）。
- 真实主目录复扫已完成：120 近期文件 / 46 应用 / 35 份带 AI 痕迹 / 10 个 AI 应用，判断为 power 画像，真实分层判断一次通过校验并渲染最终报告。

## [3.0.0] - 2026-10-25

### 变更
- 架构反转：脚本只负责收集证据，不再用规则生成建议。「哪件事可以被 AI 提效、怎么排序」由会话 AI 基于证据判断，判断必须通过本地确定性校验（引用的文件必须真实存在、提示词必须点名文件、零信号不许凑建议）。
- 每条建议改为「三件套」：这件事里 AI 能替你做哪部分 + 第一步具体怎么做（含可复制开场提示）+ 预期帮你省掉什么。
- 优先级改为「先推最快见效的小事」：存在快见效建议时，第一条必须是快见效项。
- `run-scan.sh` 重排为四阶段：计数 → 近期文档采样 → 应用清单 → 证据合并与证据报告。无判断时降级为证据报告，不再输出套话建议。
- 版本号对齐为 `v3.0.0`（`SKILL.md` / `config.json` / `scripts/run-scan.sh` / `scripts/lib/evidence_pack.py` / `scripts/lib/judgment.py`）。

### 新增
- 新增 `scripts/lib/app_inventory.py`：只读收集已安装应用名单（macOS 枚举 `/Applications` 与 `~/Applications` 的一级 `.app` 名字；Windows 走 `winreg` 卸载表与 Program Files 目录名）。可用 `ENV_SCANNER_APPLICATIONS` 覆盖扫描根。
- 新增 `scripts/lib/common.py`（噪声行/私钥识别/JSON 读写共享函数）、`scripts/lib/evidence_pack.py`（证据合并）、`scripts/lib/judgment.py`（判断校验 + 报告渲染）、`scripts/generate-final-report.sh`（校验并渲染最终报告）、`templates/final-report.html`。
- 判断文件合同：`activities` + 建议（`activity/ai_role/first_step/expected_saving/quick_win/effort/reason/sources/app_refs/evidence`）+ `priorities` + `insufficient_evidence`。
- 行为回归更新为 18 项：新增应用清单、证据包合并、判断校验矩阵、最终报告渲染合同、全流程不出站；全量回归 28 通过 / 0 失败 / 0 警告。

### 移除
- 归档旧渲染链（`bak/` + `bak/manifests/move-manifest-2026-10-25.txt`）：`render-dynamic-report.sh`、`generate-hybrid-report.sh`、`generate-hybrid-report-legacy.sh`、`generate-deep-report.sh`、`generate-preview-report.sh`、`extract-insights.sh`、`generate-report-spec.sh`、`lib/report_spec.py`、`templates/deep-report.html`、`templates/preview-report.html`、`templates/hybrid-report.html`。动态出站渲染（frontend-design/codex）彻底移除，全流程不出站。
- `config.json` 删除不再生效的声明（scan_phases、output_formats、collaboration_modes、visual_report、data_visualization、navigation、search、incremental_scan 等），只保留真实生效字段。

### 修复
- `scan_collect.py` 的磁盘占用从 `df` 改为 `shutil.disk_usage`，Windows 下不再依赖 unix 命令；`scan_scope` 注明应用名单单独只读收集。

### 说明
- Windows 端到端仍未实机验证：`app_inventory.py` 的注册表分支和 `run-scan.sh` 的 `python3||python` 探测已具备代码路径，需要一台 Windows 机器做真实回归。`collect-data.ps1` 保持计数职责不变。
- 真实主目录冒烟已完成：120 份近期文件 + 46 个应用 → 真实判断一次通过校验并渲染最终报告。

## [2.2.0] - 2026-10-21

### 变更
- 建议改为从近期文件的文件夹名和正文生成。每条建议点名具体文件，并给出可以直接复制给 AI 的一句话。
- 无参数时的默认扫描深度改为 `deep`（90 天、最多 80 份正文）。`config.json` 的 `default_config.scan_depth` 仍是来源，命令行参数优先。
- 删除 16 条固定候选。文件个数、文件夹体积和桌面拥挤度不再单独生成建议。
- 新增 `scripts/lib/sample_content.py`。`standard` 读取最多 40 个近期文档，每个最多 2000 字；`quick` 只记录文件名；`deep` 放宽天数和字数。计数值在三种模式下保持不变。
- 默认在主目录做有限发现，跳过资料库、应用和敏感目录，并设有目录数与时间预算。
- 动态渲染提示继续脱敏：不带路径、文件名、父目录和证据原句。
- 版本号对齐为 `v2.2.0`（`SKILL.md` / `config.json` / `scripts/run-scan.sh`）。

### 修复
- 修复只有书籍数量或桌面文件数时，报告仍给出阅读、清理、学习等与用户当前工作无关的建议。

### 说明
- `collect-data.ps1` 仍只输出计数。Windows 内容采样未移植，也未在本机执行。

## [2.1.0] - 2026-10-21

### 变更
- 默认渲染改为本地模板。只有显式 `ENV_SCANNER_RENDER_MODE=dynamic` 才调用模型，并且 prompt 只含聚合指标。
- 删除 frontend-design 的远程安装。
- 扫描计数改为真实总量。`quick|standard|deep` 不再把结果截成 50/100/200。
- 建议改为最多 8 条、有最低分，证据必须命中主题。零信号时不生成建议。
- 洞察文档只接受调用参数或 `ENV_SCANNER_INSIGHT_DOCS`。单份文档最多 200 行，私钥和口令赋值会被拒绝。
- 默认输出目录改为 `$HOME/.environment-scanner/reports`。预览文件默认保留。
- 无参数扫描深度统一为 `standard`，从 `config.json` 读取。
- 新增 `test-skill-behavior.sh`，覆盖计数、敏感路径、权限、证据绑定和不出站。

### 修复
- 修复建议证据按候选下标轮转粘贴的问题。
- 修复规格层 Markdown 标题清洗正则多写一层反斜杠的问题。
- 修复采集 JSON 由字符串拼接生成、主机名引号会写坏文件的问题。
- 修复 `*key*` 子串过滤误伤 `Keyboard`、同时放过 `.env` 和 `id_rsa` 的问题。

### 移除
- 移除写死的两份个人总结文档路径。
- 移除「必须输出 10 条建议」的合同。

## [未发布]

### 新增
- 计划：增量扫描能力（v1.2）
- 计划：Obsidian 插件集成（v1.4）
- 新增 `ENV_SCANNER_DYNAMIC_TIMEOUT_SEC`（默认 `45`），用于限制动态渲染等待时长，避免第 4 阶段卡住。
- 在混合回退报告中新增结构化叙事区块：`用户画像` / `核心关注领域` / `最优先建议`。

### 变更
- 简化 `SKILL.md` 的版本更新说明，仅保留当前版本重点并指向 `CHANGELOG.md`。
- 从 `SKILL.md` 移除重复历史更新块（`v1.3.x`），降低维护漂移。
- 增强 `scripts/render-dynamic-report.sh` 的回退可观测性，输出明确的合同校验失败原因。
- 升级 `templates/hybrid-report.html` 的视觉系统（版式层级、字体、氛围背景、分区过渡、原始 JSON 默认折叠）。
- 升级 `scripts/generate-hybrid-report-legacy.sh` 的建议卡呈现方式为“摘要 + 详情”，降低文本疲劳感。

### 修复
- 修复 `scripts/render-dynamic-report.sh` 中不兼容 macOS 的临时文件模板写法，改为可移植 `mktemp` 并统一清理。
- 修复动态/模板校验路径中的 `suggestion-card` 正则误判，避免有效模板输出被错误判为无效。
- 修复回退质量退化问题：有效 legacy 模板输出不再因正则误计数降级为 `fallback_basic`。

## [2.0.0] - 2026-03-13

### 新增
- 新增 `scripts/generate-report-spec.sh`，作为 report-spec 中间层，在渲染前产出 `report-spec.json`。
- 新增 `scripts/render-dynamic-report.sh`，支持 `auto|dynamic|fallback` 渲染模式及渲染元数据追踪。
- 新增 `scripts/generate-hybrid-report-legacy.sh`，作为兜底模板渲染器以提升韧性。
- 在 `config.json` 新增 `report_spec` 输出格式和报告渲染合同字段。
- 在 `test-skill-full.sh` 增加 spec 合同、建议相关性与渲染回退路径的质量/稳定性测试。

### 变更
- 升级流程为 `spec -> renderer`：`scripts/generate-hybrid-report.sh` 负责编排 spec 生成与渲染。
- 升级 `scripts/run-scan.sh` 到 `v2.0.0`，新增 `report-spec` 输出及 deep/hybrid/spec 完整性严格校验。
- 建议生成从固定内容改为数据驱动主题池评分（`bucket_scores + evidence + activity_signals + scan stats`）。
- Top-3 优先级改为从当次 Top-10 评分建议池动态选出，不再固定硬编码条目。
- 协作节奏仍保持日/周/月结构，但文案改为基于活跃度与证据密度动态生成。
- 更新 `SKILL.md` 报告标准：从固定主题改为“最小结构合同 + 数据相关建议”。
- 更新 `test-skill.sh` 与 `test-skill-full.sh` 以适配动态架构（移除对历史归档文件的校验）。

### 修复
- 修复 `scripts/run-scan.sh` 输出文件时间戳精度导致的同名冲突风险（提升到秒级）。
- 修复 `scripts/generate-deep-report.sh` 中 `mktemp` 冲突风险（采用正确 `XXXXXX` 模板并清理）。
- 修复采集/提取/预览/深度脚本对输出父目录处理不一致问题（统一 `mkdir -p "$(dirname "$OUTPUT_FILE")"`）。
- 修复回退 HTML 合同兼容性：将 legacy 模板中的 `insights` 锚点/id 规范化为 `evidence`。

### 移除
- 移除“必须包含固定主题（如自媒体）”的硬编码语义约束。

### 说明
- 已将过时 docs/templates/reports/misc 归档到本地分类目录 `bak/*/2026-03-13`，并通过 `bak/manifests/move-manifest-2026-03-13.txt` 记录映射。
- 归档清理带来的临时不兼容，已在 v2.0.0 测试与流程对齐中吸收。

## [1.3.6] - 2026-03-06

### 新增
- 新增 `scripts/generate-hybrid-report.sh`，生成混合增强 HTML 报告（固定导航、搜索、图表筛选、Chart.js 可视化）。
- 新增 `templates/hybrid-report.html` 作为混合报告模板。
- 更新 `scripts/run-scan.sh`，一键执行混合链路（`data + insights + deep + hybrid`；preview 作为中间校验产物生成）。

### 变更
- 优化 `scripts/extract-insights.sh` 证据清洗逻辑，降低 Markdown 标题/表格噪声。
- 更新 `test-skill.sh` 与 `test-skill-full.sh`，覆盖混合模板/脚本可用性和执行验证。
- 将 `scripts/run-scan.sh` 默认输出目录改为 `examples/report`（可由 `ENV_SCANNER_OUTPUT_DIR` 覆盖），确保产物在技能目录内。
- 将 preview 定义为中间校验产物：deep/hybrid 成功后自动删除（设置 `ENV_SCANNER_KEEP_PREVIEW=1` 可保留）。
- 核心版本号对齐为 `v1.3.6`（`SKILL.md` / `config.json` / `scripts/run-scan.sh`）。

### 修复
- 在不恢复手工依赖的前提下，恢复更丰富的报告体验（导航/搜索/图表）。

## [1.3.5] - 2026-03-06

### 变更
- 深度报告升级为证据驱动语义：置信分、信号摘要、机会、风险、差异化建议叙事。
- 更新 `scripts/generate-deep-report.sh`，计算加权优先级并输出非重复建议理由。
- 更新 `scripts/extract-insights.sh`，输出 `evidence_lines`、`bucket_scores`、`activity_signals`。
- 更新 `templates/deep-report.html`，渲染证据链、语义置信度与信号分区。
- 核心版本号对齐为 `v1.3.5`（`SKILL.md` / `config.json` / `scripts/run-scan.sh`）。

### 修复
- 将深度报告中通用重复建议文案改为规则驱动上下文建议，降低重复感。

## [1.3.4] - 2026-03-06

### 新增
- 新增 `scripts/extract-insights.sh`，从用户文档提取结构化洞察。
- 新增 `scripts/generate-deep-report.sh`，生成确定性深度 HTML 报告。
- 新增 `templates/deep-report.html`，作为深度报告骨架模板。

### 变更
- 更新 `scripts/run-scan.sh`，单次运行产出四类结果：`data`、`preview`、`insights`、`deep`。
- 更新测试脚本，验证深度报告链路（`extract` + `generate`）与产物完整性。
- 核心版本号对齐为 `v1.3.4`（`SKILL.md` / `config.json` / `scripts/run-scan.sh`）。

### 修复
- 通过自动化骨架生成与洞察接入，降低深度报告手工步骤。

## [1.3.3] - 2026-03-06

### 新增
- 新增 `scripts/generate-preview-report.sh`，从 JSON 自动生成 HTML 预览报告。
- 新增 `templates/preview-report.html` 作为预览报告模板。

### 变更
- 更新 `scripts/run-scan.sh`，在数据采集后自动生成预览报告。
- 收敛辅助文档（`README.md`、`QUICK_REFERENCE.md`、`FILE_INDEX.md`、`TEST_REPORT.md`），减少重复维护内容。
- 更新 `test-skill.sh` 与 `test-skill-full.sh`，覆盖预览模板/脚本可用性与执行验证。
- 核心版本号对齐为 `v1.3.3`（`SKILL.md` / `config.json` / `scripts/run-scan.sh`）。

### 修复
- 通过引入确定性预览产出，降低报告流程的手工依赖。

## [1.3.2] - 2026-03-06

### 变更
- 更新 `scripts/collect-data.sh`，使扫描深度（`quick`/`standard`/`deep`）按采样上限真实生效。
- 更新 `scripts/run-scan.sh`，向采集脚本透传扫描模式并规范化非法输入。
- 更新 `scripts/collect-data.ps1`，使扫描模式上限与 shell 实现保持一致。
- 对齐 `SKILL.md`、`config.json`、`scripts/run-scan.sh` 核心版本号。

### 修复
- 修复 `scan_mode` 输出不一致问题（`collect-data.sh` 不再硬编码 `deep`）。
- 增加脚本级敏感路径过滤，降低误分析不安全目录风险。
- 修复 `set -euo pipefail` 下的潜在管道不稳定问题：将 `find | head` 计数改为 `find | awk` 有界计数。

## [1.3.1] - 2026-03-06

### 新增
- 新增 `scripts/collect-data.ps1`，支持 Windows 数据采集。

### 变更
- 更新 `SKILL.md`，使平台说明与脚本实际可用性一致。
- 更新测试脚本，统一从当前工作区解析路径，移除历史硬编码路径。

### 修复
- 修复 `config.json` 非法 JSON 语法（`output_formats.html.features`）。
- 修复测试中的文件名大小写检查不一致（`SKILL.md` / `README.md`）。

## [1.1.0] - 2026-03-05

### 新增
- **增强可视化报告**（`visual-report-enhanced.html`）
  - 固定导航栏（6 个主分区）
  - 基于 Chart.js 的 4 个交互图表：
    - 文件类型分布（环形图）
    - 关注领域雷达图
    - 知识库增长趋势（折线图）
    - 时间投入分配（极区图）
  - 实时搜索功能
  - 按类别图表筛选
  - 完整内容展示（无截断）
  - 响应式设计优化
  - 打印友好优化

- **详细协作计划**
  - 每日协作：早晨/白天/晚间任务
  - 每周协作：周一/周三/周五任务
  - 每月协作：月初/中旬/月末任务
  - 每种协作模式对应价值说明

- **用户体验改进**
  - 更优信息架构
  - 更清晰视觉层级
  - 可执行建议（含步骤化引导）
  - 完整的“10 条建议”展示（无截断）
  - 详细“优先支持”分区

- **测试基础设施**
  - 自动化测试脚本（`test-skill.sh`）
  - 权限校验
  - 文件完整性检查
  - 可视化校验清单

### 变更
- 默认输出格式从 `markdown` 改为 `html`
- 默认模板从 `visual-report.html` 改为 `visual-report-enhanced.html`
- 更新 README，补充详细使用说明
- 更新 `config.json` 到 v1.1.0，并纳入新特性

### 修复
- 修复可视化报告内容截断问题
- 修复协作计划细节缺失问题
- 修复建议描述不完整问题

## [1.0.0] - 2026-03-05

### 新增
- **初始发布**
  - 基础环境扫描能力
  - 权限预检查机制
  - 5 阶段扫描工作流
  - 用户内容分析
  - 知识管理工具识别
  - 项目结构识别

- **输出格式**
  - Markdown 报告（`templates/report.md`）
  - 基础 HTML 可视化（`templates/visual-report.html`）
  - JSON 数据导出

- **核心特性**
  - 智能过滤（系统文件、缓存、敏感数据）
  - 安全模式（只读、不修改）
  - 进度反馈
  - 权限错误处理

- **报告分区**
  - 用户画像总览
  - 10 条长期协作建议
  - 基础协作计划（日/周/月）
  - 3 条优先支持项
  - 关键发现

- **文档**
  - `SKILL.md`（完整技术文档）
  - `README.md`（使用说明）
  - `config.json`（配置文件）
  - `IMPROVEMENT_ROADMAP.md`（未来路线）
  - `examples/sample-user-report.md`（示例输出）

### 安全
- 全程只读分析
- 自动过滤敏感目录
- 扫描前权限检查
- 扫描过程透明反馈

---

## 版本历史摘要

| 版本 | 日期 | 主要变化 |
|------|------|---------|
| v2.2.0 | 2026-10-21 | 近期文件采样，建议改为点名文件的协作提示 |
| v2.1.0 | 2026-10-21 | 真实计数、有门槛的建议、本地默认渲染、洞察范围收紧 |
| v2.0.0 | 2026-03-13 | 动态报告架构（`report-spec + dynamic renderer + fallback`）与数据驱动建议池 |
| v1.3.6 | 2026-03-06 | 混合增强报告输出（交互 UI + 快速自动化流水线） |
| v1.3.5 | 2026-03-06 | 深度报告语义质量升级（证据链 + 加权优先级） |
| v1.3.4 | 2026-03-06 | 深度报告自动化（洞察提取 + 确定性深度 HTML） |
| v1.3.3 | 2026-03-06 | P2 修复：文档收敛与预览报告自动生成 |
| v1.3.2 | 2026-03-06 | P1 修复：扫描模式生效、安全过滤、核心版本对齐 |
| v1.3.1 | 2026-03-06 | P0 修复：配置语法、Windows 脚本、路径安全测试 |
| v1.1.0 | 2026-03-05 | 增强可视化报告、交互图表、完整内容展示 |
| v1.0.0 | 2026-03-05 | 初始发布 |

## 升级指南

### 从 v1.0.0 升级到 v1.1.0

**配置变更：**
```json
{
  "version": "1.1.0",
  "default_config": {
    "output_format": "html",  // 由 "markdown" 调整为 "html"
    "template_version": "enhanced"  // 新增
  }
}
```

**模板变更：**
- 旧版：`templates/visual-report.html`
- 新版：`templates/visual-report-enhanced.html`（默认）

**建议验证的新特性：**
1. 固定导航栏
2. 交互图表
3. 实时搜索
4. 图表筛选
5. 完整内容展示

**迁移步骤：**
1. 将 `config.json` 更新到 v1.1.0
2. 测试增强可视化报告
3. 验证所有新特性可正常工作
4. 如有需要更新文档

---

## 未来路线图

### v1.2.0（计划）
- 增量扫描支持
- 结果缓存
- 变更追踪
- 性能优化

### v1.3.7（计划）
- 跨平台扩展优化（Windows、Linux）
- 平台特定优化
- 扩展文件系统支持

### v1.4.0（计划）
- Obsidian 插件集成
- Notion API 集成
- Roam Research 集成
- 自定义知识工具支持

### v2.1.0（计划）
- AI 驱动洞察
- 预测式建议
- 自动化工作流优化
- 团队协作能力

---

**说明**：本技能遵循语义化版本规范。主版本升级可能包含不兼容变更。
