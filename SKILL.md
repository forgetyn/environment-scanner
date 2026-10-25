---
name: environment-scanner
description: 当用户想知道"我做的事情哪些可以用 AI 提效""帮我扫扫电脑看看能让我用 AI 干什么"，或要求扫描自己的电脑、文件、笔记、项目、电子书、安装的软件并生成环境报告时使用。只读，不修改扫描范围内的用户文件。支持 quick、standard、deep。
---

# Environment Scanner Skill v4.0.0

帮用户做需求发现：只读扫描电脑（近期文档 + 已安装应用 + 知识库与自述文档），收集证据，由本会话 AI 产出两层判断——全局诊断（你是谁、在做什么、AI 用到什么程度、最大的机会在哪）和具体建议（三件套）。报告恢复完整叙事：用户画像、整体理解、真实数据图表、建议、长期协作节奏、优先级、高价值资产发现。图表数字全部由渲染器从证据确定性注入，AI 不许手填；所有事实引用（文件名或聚合指标）必须通过本地确定性校验。

## 工作流（两步）

```bash
# 第 1 步：收集证据（默认 deep，来源是 config.json 的 default_config.scan_depth）
bash scripts/run-scan.sh [quick|standard|deep]
```

然后只读输出目录里最新的 `environment-scanner-evidence-*.json`。不要打开样本列表以外的文件，不要要求完全磁盘访问权限。

基于证据写判断文件 `environment-scanner-judgment-<同时间戳>.json`（结构见下），然后：

```bash
# 第 2 步：校验判断并渲染最终报告
bash scripts/generate-final-report.sh <evidence.json> <judgment.json> <environment-scanner-final-<时间戳>.html>
```

校验失败会逐条给出原因，修正判断文件后重跑即可。最后在对话里用白话给出前三条，并指向报告文件。没有判断时只有证据报告，不用固定模板凑建议。

## 判断文件结构（诊断层 + 综合层 + 三件套建议）

```json
{
  "persona": "novice|power",
  "diagnosis": {
    "summary": "一句话整体结论：最大的剩余机会在哪",
    "activities": [{"activity": "…", "ai_usage": "none|occasional|deep", "time_note": "…", "note": "可选"}]
  },
  "understanding": {
    "activities":  [{"text": "…", "basis": ["文件名或指标引用，可选"]}],
    "domains":     [{"text": "…"}],
    "work_style":  [{"text": "…"}],
    "structure":   [{"text": "…"}]
  },
  "suggestions": [{
    "id": "s1",
    "kind": "basic|upgrade",
    "activity": "你在做的事（白话）",
    "ai_role": "这件事里 AI 能替你做哪一部分",
    "first_step": "第一步怎么做，含可复制的开场提示词；引用了文件就必须点名文件名",
    "expected_saving": "预期帮你省掉什么",
    "quick_win": true,
    "effort": "low|medium|high",
    "reason": "为什么是现在",
    "sources": [
      {"name": "活动方案.md", "parent": "桌面/市集"},
      {"type": "metric", "ref": "counts.ebooks"}
    ],
    "app_refs": ["Keynote"],
    "evidence": "一句话证据"
  }],
  "priorities": [{
    "id": "s1", "why": "为什么最有价值",
    "how_to_start": ["第 1 周做什么", "第 2 周做什么"],
    "long_term": ["长期帮助 1", "长期帮助 2"]
  }],
  "cadence": {
    "daily":   {"summary": "一句话", "items": ["…"]},
    "weekly":  {"summary": "一句话", "items": ["…"]},
    "monthly": {"summary": "一句话", "items": ["…"]}
  },
  "assets": [{"title": "高价值资产", "what": "这是什么", "why_valuable": "为什么有价值", "how_to_use": ["用法 1"], "basis": ["可选引用"]}],
  "structure_advice": [{"title": "…", "detail": "…"}],
  "insufficient_evidence": false
}
```

**引用双通道**：`{"name": "文件名"}` 引用证据里的近期文件；`{"type": "metric", "ref": "counts.ebooks"}` 引用聚合指标（dotted path 必须真实存在于证据，如 `counts.ebooks`、`structure.top_dirs`）。聚合引用让"435 本电子书是沉睡资源"这类洞察合法且可验证。

## 判断准则

### 第 0 步：先判断画像（persona）

看 `ai_usage_signals`：`marker_files`（近期文件里带 AI 痕迹的份数）、`markers`、`ai_apps`。痕迹密集 → `power`；几乎没有 → `novice`。画像决定报告基调：novice 教他从零把事交给 AI，power 不再讲基础用法，重点是"把零散用法变成系统"。

### 第 1 步：全局诊断（diagnosis）

1. 从 `recent_files`（文件名/文件夹/标题/摘录）、`knowledge_bases`（Obsidian/Logseq 笔记数、活跃度、顶层目录、日记习惯）、`deep_reads`（自述文档全文）识别用户在做的事。`deep_reads` 是理解"这个人是谁"的最强证据——职业、优势、关注点、自我认知优先从这里取。
2. 每件事标 `ai_usage` 三档；`summary` 横向比较所有活动，回答"最大的剩余机会在哪"，不逐条罗列。

### 第 2 步：整体理解（understanding 四张卡）

像顾问写评估，不像清单。四张卡各 2-6 条：主要活动类型 / 关注的主要领域 / 工作或学习方式 / 文件结构特点。要求：具体到人（引用真实数字、真实文件、日记习惯、知识库结构），带洞察（不止描述还有判断），重要论点挂 basis 引用。日记频率、持续天数、知识库规模都是现成的好素材。

### 第 3 步：具体建议（三件套）

1. 只对 `none`/`occasional` 活动给 `basic` 建议；对 `deep` 活动只给 `upgrade` 建议（把一次性用法变成可重复流程/skill、打通断点）。已深度用 AI 的事绝不推荐基础用法。
2. 建议模式：初稿写作、长文压缩/总结、表格清洗查重、演示文稿与讲稿、信息整理归档、翻译、格式转换、重复性回复、学习材料问答、活动筹备、流程自动化（升级型）、沉睡资源激活（可引用聚合指标）。
3. 优先级第一条必须是最快见效的小事；每条优先级写三段：为什么最有价值 / 如何开始（分步）/ 长期帮助。
4. 说人话，不出现"置信度、主题池、评分"。第一步默认发给当前 AI 助手，加一句"不要补充文件里没有的事实"。
5. 不编造：文件引用必须来自 `recent_files` 或 `deep_reads`，指标引用必须真实存在，`app_refs` 必须来自 `apps`。证据不足宁可 0 条。

### 第 4 步：资产发现与协作节奏

1. `assets`：找高价值资产（已成体系的知识库、独特的方法论文档）、沉睡资源（量大但未激活，如电子书库、旧报告库）、可产品化经验。每条说清是什么、为什么有价值、怎么用。
2. `cadence`：结合活跃度设计日/周/月协作节奏，事项要具体到"把什么文件以什么方式交给 AI"，不写空话。
3. `structure_advice`：只在有真问题时给（目录混乱、命名不一致、版本混乱），最多 4 条。

## 校验规则（generate-final-report.sh 会拒绝以下情况）

- `persona` 非法；`diagnosis` 缺失或字段不全；诊断活动超过 8 条。
- 有建议时缺少 `understanding`（四卡各需 2-6 条非空要点）或 `cadence`（daily/weekly/monthly 各需 summary 和 1-4 条事项）。
- 建议 `kind` 非法；无 AI 使用证据却出现升级型建议；power 画像没有升级型建议。
- 建议不是 0 到 10 条；引用的文件不在近期文件里；指标引用在证据里不存在；引用了文件但 `first_step` 没点名文件名。
- 优先级超 3 条、引用不存在的建议 id、缺 `how_to_start`/`long_term`；有快见效建议时第一条必须是快见效项。
- 资产超过 6 条或字段不全；结构建议超过 4 条；没有建议时 `insufficient_evidence` 必须为 true；零信号禁止生成建议。

## 安全边界

- 可以在输出目录写本工具自己的 JSON 和 HTML。不修改、不删除、不移动扫描根里的用户文件。
- 扫描根默认是 `~/Documents`、`~/Desktop`、`~/Downloads`、`~/Desktop/书籍`，可用 `ENV_SCANNER_DOCUMENTS`、`ENV_SCANNER_DESKTOP`、`ENV_SCANNER_DOWNLOADS`、`ENV_SCANNER_BOOKS` 覆盖（测试必用）。
- 主目录有限发现默认开启（`ENV_SCANNER_DISCOVER_HOME=0` 关闭，`ENV_SCANNER_HOME` 改根）。应用清单只读 `/Applications`、`~/Applications` 的一级名字（`ENV_SCANNER_APPLICATIONS` 覆盖），不读应用内容。
- 知识库发现默认开启（`ENV_SCANNER_KB_DISCOVER=0` 关闭）：在主目录有限深度内找 Obsidian/Logseq vault 标记，统计笔记与日记习惯；只对文件名命中自述词典（个人总结/个人画像/自我介绍/关于我/个人情况/简历）的最近 3 份文档深读（每份最多 500 行）。发现私钥或口令赋值时整份拒绝。不做全盘全文扫描。
- 跳过规则以 `config.json` 的 `features.smart_filtering` 为准。采样上限以 `features.content_sample` 为准：deep 看 90 天、最多 80 份、每份 4000 字；发现过程最多 8000 目录或 15 秒。
- 正文采样最多读前 200 行，发现私钥块或口令赋值时丢弃该文件正文（记入 rejected_documents，禁止引用）。
- 扫描根本身不可读时停止且不写输出；子目录不可读时跳过并记入 `scan_warnings`。
- 不要求用户打开完全磁盘访问权限。整个流程不出站：不调用外部渲染服务，不从网络安装任何 skill。
- Linux 没有自动采集脚本，不要临时拼一套等价命令。Windows 目前只有 `collect-data.ps1`（计数）和 `app_inventory.py` 的注册表分支，未实机验证。

## 文件

- `scripts/run-scan.sh`：证据收集入口
- `scripts/lib/scan_collect.py`：计数和跳过
- `scripts/lib/sample_content.py`：近期文档采样
- `scripts/lib/app_inventory.py`：应用清单（macOS 目录 + Windows 注册表）
- `scripts/lib/kb_discover.py`：知识库发现（Obsidian/Logseq vault、日记习惯、自述深读）
- `scripts/lib/evidence_pack.py`：证据合并
- `scripts/lib/judgment.py`：判断校验 + 报告渲染
- `scripts/generate-final-report.sh`：校验并渲染最终报告
- `templates/final-report.html`：报告模板
- `config.json`：默认深度、跳过规则、采样与清单上限
- `CHANGELOG.md`：版本历史
