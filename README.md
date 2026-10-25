# Environment Scanner

![version](https://img.shields.io/badge/version-4.0.0-blue) ![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%5Bpartial%5D-lightgrey) ![privacy](https://img.shields.io/badge/privacy-read--only%20%7C%20no%20upload-green)

**帮"不知道 AI 能帮我干什么"的人找到答案。**

这是一个面向非技术用户的 AI 助手技能（skill）：只读扫描你的近期文档、已安装应用和笔记知识库，基于真实证据回答"我做的事情里，哪几件适合交给 AI？第一件从哪儿开始？"，并生成一份带图表的 HTML 报告。

## 它解决什么问题

想用 AI 提效的人最常见的困境不是"不会写提示词"，而是根本不知道自己日常做的事情里，哪些是 AI 擅长的。通用的 AI 建议文章给的是"人人适用"的套话；这个 skill 的做法是：先看你电脑上真实在发生什么——近期在写什么文档、装了什么应用、记不记笔记——再由 AI 基于这些证据做判断。

## 工作原理：采集 → 判断 → 校验

| 阶段 | 谁做 | 做什么 |
|------|------|--------|
| 1. 采集 | 本地脚本（只读） | 计数聚合、近期文档采样、应用清单、知识库发现，产出证据文件 `environment-scanner-evidence-*.json` |
| 2. 判断 | 会话 AI | 按内置判断准则产出两层判断：全局诊断（你是谁、在做什么、AI 用到什么程度、最大机会在哪）+ 三件套建议 |
| 3. 校验渲染 | 本地脚本 | 校验判断里每个引用是否真实存在，通过后渲染最终报告；图表数字由渲染器从证据确定性注入 |

第 3 步是防幻觉的关键：AI 判断里引用的**文件名必须在证据里真实存在**，引用的**聚合指标（如电子书总数）必须真实可查**，`first_step` 点名了文件就必须写清文件名，零信号时禁止硬凑建议。校验不过，报告不出。

## 报告里有什么

最终报告是一份暗色风格的单文件 HTML（八大区块 + 四张图表）：

- **用户画像与整体理解**——四张理解卡：你在做的活动、关注的领域、工作方式、文件结构特点，重要论点都挂真实证据
- **全局诊断**——每件事的 AI 使用程度（没用过 / 偶尔 / 深度）与时间占用，以及"最大的剩余机会在哪"
- **建议（最多 10 条）**——每条三件套：这件事里 AI 替你做哪部分 / 第一步具体怎么做（含可复制的开场提示词）/ 预期省掉什么
- **优先级路线图**——第一条永远是最快见效的小事；每条讲清为什么、怎么分步开始、长期有什么帮助
- **高价值资产发现**——已成体系的知识库、沉睡的资源（比如"435 本电子书还没激活"）、可产品化的经验
- **长期协作节奏**——日 / 周 / 月分别把什么文件以什么方式交给 AI
- **数据图表**——文件类型分布、活跃领域雷达、26 周活跃趋势、时间分配

报告输出到 `~/.environment-scanner/reports/`。

## 安装

**要求**：macOS（完整支持）；bash 与 Python 3（仅标准库，无第三方依赖）；`jq` 可选（缺失时走默认配置）。

把这个仓库克隆到你 AI 助手的技能目录（兼容采用 SKILL.md 技能规范的助手，如 ZCode、Claude Code）：

```bash
# ZCode（~/.agents/skills/）
git clone https://github.com/forgetyn/environment-scanner.git ~/.agents/skills/environment-scanner

# Claude Code（~/.claude/skills/）
git clone https://github.com/forgetyn/environment-scanner.git ~/.claude/skills/environment-scanner
```

## 使用

装好后直接对 AI 助手说：

> 帮我扫扫电脑，看看我做的事情哪些可以用 AI 提效。

技能会自动触发，跑完两步（采集 → 判断 → 校验渲染）后，助手会用白话给你讲前 3 条建议，并告诉你报告文件的位置。

也可以手动分步执行：

```bash
# 第 1 步：收集证据（默认 deep）
bash scripts/run-scan.sh [quick|standard|deep]

# 第 2 步：AI 基于证据写判断文件后，校验并渲染报告
bash scripts/generate-final-report.sh <evidence.json> <judgment.json> <output.html>
```

## 扫描范围与深度

默认扫描根：`~/Documents`、`~/Desktop`、`~/Downloads`、`~/Desktop/书籍`，外加主目录有限深度的发现（找 Obsidian/Logseq 笔记库和自述文档）。三种深度：

| 模式 | 回看 | 读多少正文 | 用途 |
|------|------|-----------|------|
| `quick` | 30 天 | 只记文件名，不读正文 | 快速看一眼 |
| `standard` | 30 天 | 最多 40 份，每份 2000 字 | 日常使用 |
| `deep`（默认） | 90 天 | 最多 80 份，每份 4000 字 | 完整判断 |

知识库发现会自动识别 Obsidian / Logseq vault（`.obsidian/`、`.logseq/` 标记），统计笔记规模、顶层目录和日记习惯；并对命中自述词典（个人总结 / 简历 / 关于我 等）的最近 3 份文档深读（每份最多 500 行），这是理解"这个人是谁"的最强证据。

## 隐私与安全

- **只读**：不修改、不删除、不移动扫描范围内的任何用户文件；只在自己的输出目录写 JSON 和 HTML
- **全流程不出站**：不调用外部渲染服务，不从网络安装任何东西；报告里的图表库（Chart.js）仅在你打开报告查看时从 CDN 加载库文件本身，不上传任何数据
- **敏感内容拒绝**：跳过 `.ssh`、`.gnupg`、Keychains 等敏感目录和 `id_rsa`、`.env`、`.pem` 等敏感文件；正文采样遇到私钥块或口令赋值时整份丢弃并禁止引用
- **深读正文不进报告**：自述文档的正文只用于 AI 判断，不会出现在报告的原始 JSON 折叠区
- **不要求完全磁盘访问权限**；扫描根不可读时停止而不是报错硬闯

## 可配置项（环境变量）

| 变量 | 作用 | 默认 |
|------|------|------|
| `ENV_SCANNER_OUTPUT_DIR` | 输出目录 | `~/.environment-scanner/reports` |
| `ENV_SCANNER_DOCUMENTS` / `_DESKTOP` / `_DOWNLOADS` / `_BOOKS` | 覆盖四个扫描根 | 系统默认目录 |
| `ENV_SCANNER_HOME` / `ENV_SCANNER_DISCOVER_HOME=0` | 主目录发现的根 / 开关 | `~` / 开启 |
| `ENV_SCANNER_APPLICATIONS` | 应用清单扫描根 | `/Applications`、`~/Applications` |
| `ENV_SCANNER_KB_DISCOVER=0` | 关闭知识库发现 | 开启 |

## 平台支持与已知限制

- **macOS**：完整支持（本项目的开发与回归环境）
- **Windows**：部分支持——计数脚本（PowerShell）和应用清单（注册表）代码路径已就绪，但**未在真实 Windows 机器上验证过**；内容采样尚未移植到 PowerShell
- **Linux**：暂不支持（无自动采集脚本）
- PDF 和 Excel 文件目前只在证据里记录文件名，不解析正文；判断时 AI 可以直接读这些文件补足

## 开发

```bash
bash tests/test-skill.sh          # 快速检查：文件齐全、语法合法
bash tests/test-skill-behavior.sh # 行为回归（21 项，夹具全在临时目录）
bash tests/test-skill-full.sh     # 全量回归（29 项：采集 + 校验矩阵 + 渲染合同）
```

文档结构：`SKILL.md` 是行为语义真相源（判断准则与判断文件合同），`config.json` 是配置真相源（只保留真实生效字段），`CHANGELOG.md` 记录全部版本历史，`AGENTS.md` 是给 AI 编码助手的项目指南。
