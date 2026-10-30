# 证据偏差审查

只审采样、计数、知识库、应用清单、证据合并，以及默认根和主目录跳过名单怎样改写证据。不把已公开限制（GBK 不探测、PDF/xlsx 只留文件名、Windows 未实机）再报一遍；下面写的是这些洞会让证据看起来已经扫全。

### E1 深读会把别人的稿或旧简历写成「这个人是谁」

- 严重度：blocker
- 位置：`scripts/lib/kb_discover.py` `find_self_docs`、`deep_read`、`discover_vaults`、`collect`
- 目标如何失败：判断准则把 `deep_reads` 当成职业、优势、自我认知的最强证据。词典是子串，而且三个 vault 各取一份，不按人、不按新旧筛选。模型会用一份「关于我们」或「简历模板」写用户画像，并据此决定第一件交给 AI 的事。真正的简历若是 `.docx`/`.pdf`，这条通道里根本没有。
- 证据：`SELF_DOC_KEYWORDS = (..., "关于我", "个人情况", "简历")`，后缀只有 `.md/.markdown/.txt`；`if any(keyword in entry.stem ...)` 后按 mtime 取前 `max_deep_reads`。`collect` 对每个 vault 各深读再追加，没有全局上限。`discover_vaults` 用未排序的 `iterdir()`，凑满 `max_vaults`（3）就停。实测「关于我们」「如何写简历」「个人情况登记表」都会命中。私钥正则一旦命中，整份真自述被丢，假模板可以留下。
- 如何确认：临时主目录放两个带 `.obsidian` 的目录，先被遍历的那个只放 `关于我们.md`，真库放 `个人总结.md`，看 `deep_reads` 的正文是不是「关于我们」。
- 不成立的可能：两个文件都在，模型若先看 `mtime` 和标题，会自己丢掉 2016 年的简历；用户的自述恰好是 `个人总结.md` 且所在库排进前三个。

### E2 120 个名额会把正在写的那一类文件挤掉，热度图再把它写成事实

- 严重度：blocker
- 位置：`scripts/lib/sample_content.py` `select_candidates`、`take_round_robin`、`collect_samples`；规则在 `scripts/lib/common.py` `is_dated_note_name`
- 目标如何失败：周报、合同、章节稿只要文件名里有日期或像 `1.1 背景`，就离开工作池，进日记池。日记每目录 3 份、总共最多 8 份，剩余名额只回填工作池。一个文件夹里的全年周报在 `recent_files` 里只剩 3 个名字。模型看到的「近况」是杂项目录里轮转出来的文件，于是把主业说成零散杂事，或把写周报说成几乎不写。正文预算 80 份按这个顺序读，工作文件够 80 份时，日记和书籍只有文件名、`body_skipped=not_read`。
- 证据：`DATE_NAME_RE.search` 命中任意位置的 `20xx-月`，`SHORT_DATE_RE` 命中开头的 `1.1 `。`select_candidates` 写明只有工作池可以回填。`preference` 在多个父目录之间轮转，每目录先停在 8，大目录不会因为文件多而多占。`activity_heat` / `weekly_counts` 只统计这份样本，空周不出现；证据里没有另一份未截断的近期目录计数。`config.json` 的 `generic_dir_names` 没有任何脚本读取，`Documents`/`下载` 会直接成为热度目录。行为 23 把「日期文件只留 3 个」锁成了通过条件，没有覆盖 `周报2026-10-25.md` 或 `1.1 背景.md`。
- 如何确认：一个目录放 10 个 `1.1 背景.md` 式章节稿、不放别的近期文件，看 `recent_files` 是否只剩 3 条，且没有「名额不够」之类的警告。
- 不成立的可能：主业文件名不含日期、只集中在一个目录，回填可以把该目录补到最多 120；6 个文件名如果已经高度同题，模型仍可能认对主题，只是认错体量。

### E3 扩展名闭集和敏感词子串让主业文件从未进入证据

- 严重度：blocker
- 位置：`scripts/lib/sample_content.py` `DOCUMENT_EXTENSIONS`、`consider_file`；`scripts/lib/scan_collect.py` `skip_dir` / `skip_file`
- 目标如何失败：非技术用户的默认产物经常是 Pages/Keynote/Numbers、旧版 `.doc`、WPS、`.rtf`。它们不在闭集里，`recent_files` 没有名字也没有摘录。模型按准则从近期文件认活动，会说这个人几乎不写文档，或只根据碰巧扫到的少数 `.txt` 下结论。文件名带 `seed`/`crypto`/`wallet` 的整棵目录同样消失，计数和样本都不含它们，看起来像从未做过种子轮材料或相关笔记。
- 证据：闭集是 `.md/.markdown/.txt/.csv/.docx/.pptx/.pdf/.xlsx`。这不是「pdf/xlsx 只留文件名」——那些后缀至少还在名单里。`skip_file`/`skip_dir` 对 `wallet`、`crypto`、`seed` 做子串匹配，不写警告。`count_is_total: True` 仍在。行为测试还断言 wallet 跳过时 `scan_warnings` 里不能出现说明。
- 如何确认：扫描根里只放 `周报.pages`、`方案.doc`、`seed-round.docx`，看 `recent_files` 是否为空、`scan_warnings` 是否也空。
- 不成立的可能：用户的正文都是 `.docx/.md`，模型又主动去看 `structure.extensions` 里的 `.pages` 计数；那样能发现「有这种格式」，但仍然点不出文件名，第一步提示词无文件可引用。`seed` 若真是助记词文件名，丢掉是本意。

### E4 跳过 Library、深度到点、符号链接，都会让云盘里的主业像「不写文档」

- 严重度：blocker
- 位置：`scripts/lib/platform_mac.py` `home_discover_skip_dirs`；`scripts/lib/sample_content.py` `discover_files`；`scripts/lib/kb_discover.py` `discover_vaults`；三处 `is_symlink(): continue`
- 目标如何失败：macOS 上 Obsidian 走 iCloud 时，库在 `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/`。OneDrive/Google Drive 的现代路径在 `~/Library/CloudStorage/`。微信收到的文件在 `~/Library/Containers/`。这三处都叫 Library，样本发现和知识库发现都整棵跳过，没有「未扫描」。深度停在主目录下第 4 层（知识库第 5 层）也不产生 `sample_budget_reached`。模型看到 `knowledge_bases: []`、近期文件里没有这些笔记，会把一个以云笔记为生的人写成没有写作习惯。符号链接目录被直接跳过，链到外部盘的工作目录同样消失。
- 证据：跳过集合含 `Library`（`config.json` 的 `discover_skip_dir_names` 再加一次）。`discover_files` 在 `depth >= home_depth`（4）时不再进入子目录。`default_user_roots` 只认 `~/Documents`、`~/Desktop`、`~/Downloads`、`~/Desktop/书籍`，没有 Mac 的 OneDrive。四个根本身没有深度上限；洞在根以外。
- 如何确认：只把带 `.obsidian` 的库放在上述 iCloud 路径下，看 `knowledge_bases` 是否为空且 `scan_warnings` 没有缺扫说明。
- 不成立的可能：库就在 `~/Documents` 或桌面，`walk` 会扫到。打开「iCloud 桌面与文稿」时，路径仍是 `~/Documents` 和 `~/Desktop`，不受 Library 跳过影响。用户若已把微信文件另存到桌面，那些副本仍在。

### E5 根缺失、OneDrive 空目录命中、书籍目录没有，空计数仍写成总量

- 严重度：degrade
- 位置：`scripts/lib/scan_collect.py` `assert_root_readable`、`walk`、`collect`；`scripts/lib/platform_win.py` `default_user_roots`；`scripts/lib/platform_mac.py` `default_user_roots`；`scripts/lib/evidence_pack.py` `zero_signal`
- 目标如何失败：目录不存在时 `walk` 返回空列表，不追加警告，`count_is_total` 仍是 true。Windows 上只要 `OneDrive*/Documents` 是个空目录就采用它，不再看真正的 `Documents`，也不读 User Shell Folders。下载目录完全不参加重定向。书籍固定是桌面下的 `书籍`，没有这个文件夹则 `ebooks=0`。模型会引用 `counts.ebooks` / `counts.obsidian_notes` 说「没有书、没有笔记」。后一个字段还把「文档根里的全部 markdown」标成笔记总数：桌面上的笔记不算，普通 README 算。`zero_signal` 只看近期文件和应用名，知识库和深读不算；有应用、无文件时允许继续编活动，有库、无应用时反而当成零信号。
- 证据：`if not root.exists(): return`。`resolve` 里 `if target.is_dir(): return target`，不看里面有没有文件。`downloads` 写死 `home / "Downloads"`，`books` 写死 `desktop / "书籍"`。`"obsidian_notes": len(markdown)` 只来自文档根。`zero_signal: not files and not app_names`。行为 24 只断言 OneDrive 目录存在时会被选中，没有断言空 OneDrive 盖住真文档。
- 如何确认：主目录下建空的 `OneDrive/Documents`，把 markdown 放进旁边的 `Documents`，用 Windows 适配器做一次计数，看 `obsidian_notes` 是否为 0 且 `scan_warnings` 为空。
- 不成立的可能：真文档就是那份 OneDrive 目录，或 `Documents` 已是指向它的 junction，两边是同一棵树。书籍本来就不在桌面 `书籍` 里时，0 只是「默认路径没有」，模型若只说「这个默认文件夹是空的」就没有判错；字段名和 `count_is_total` 不会这样限定。

### E6 应用名和正文里的宽匹配，会把不会用 AI 的人标成已经在用

- 严重度：degrade
- 位置：`scripts/lib/evidence_pack.py` `AI_TEXT_MARKERS`、`AI_APP_KEYWORDS`、`ai_usage_signals`
- 目标如何失败：画像只看这一个结构：痕迹密则 power，几乎没有则 novice。power 不再教基础用法，已经标成 deep 的事只能给升级建议。`skill` 会命中简历和岗位说明里的 skills，`agent` 会命中旅行社/中介，`自动化` 会命中「办公自动化」。应用名是子串：`UltraEdit` 含 `trae`，`CursorSense` 含 `cursor`。反过来，`用AI写周报` 因为中文和 AI 之间没有词边界，不算痕迹。分母是裁剪后的 `recent_files`，E2 把分母压小以后，一两处误命中的 `file_ratio` 会显得很密。
- 证据：`keyword in str(app).casefold()`；正文规则含 `skill`、`智能体|agent`、`自动化`、`\bAI\b`。只扫描 `heading` 和 `excerpt`，不看深读。应用清单只有名字，装过就算。超过 `max_apps`（400）后按字母截断，只留 `app_list_truncated`，靠后的真 AI 应用会从 `ai_apps` 里消失，方向相反。
- 如何确认：一份摘录为「我的 skills 包括沟通」的普通周报，加一个应用名 `UltraEdit`，看 `markers` 和 `ai_apps` 是否都非空。
- 不成立的可能：模型把「痕迹密集」理解成多份文件反复出现模型名，而不是一次 `skill` 命中。那样单次误命中不会翻成 power。准则没有给门槛，两种读法都成立。

### E7 日记频率和「顶层目录」会把周报、月份文件夹说成这个人的工作方式

- 严重度：degrade
- 位置：`scripts/lib/kb_discover.py` `vault_stats`
- 目标如何失败：准则要求用日记频率、持续天数、知识库结构写「这个人怎么工作」。`top_dirs` 实际按直接父目录名计数，不是 vault 下第一层。`项目/2024/01/日期.md` 会把 `01` 当成主领域，同名 `附件` 会跨分支合并。日期文件名用 E2 的同一条规则，一组周报会被写成 `journals`。`weekly_freq` 用 mtime 跨度而不是文件名里的日期：同步或拷贝把 mtime 收成同一天时，跨度被抬到至少 1 天，频率变成「每周几十篇」。模型会按这个假习惯设计每天协作，并把历史周报当成现在的日记强度。
- 证据：`name = path_obj.parent.name`，满 3 篇即进入 `top_dirs`。日记分组用 `rel.parts[0]`，门槛误用 `DEFAULT_CONFIG["journal_min_files"]` 而不是已经读入的 config（两边现在都是 10，改配置不会生效）。`span_days = max((max(mtime)-min(mtime))/86400, 1.0)`。行为 21 只覆盖扁平的 `07-Daily Note/日期.md`，mtime 就是文件名那天。
- 如何确认：30 篇笔记放在 `Vault/项目/2024/01/`，文件名是日期，mtime 全部改成同一天；看 `top_dirs` 是否出现 `01` 而不是 `项目`，以及 `weekly_freq` 是否远大于每周 7。
- 不成立的可能：日记插件把笔记直接放在第一层目录，且 mtime 没被同步改写。那时 `journals.dir` 和频率都还能用。`top_dirs` 对再套一层的库仍然是错的。

### E8 预算到顶几乎不说明缺了什么；同一次扫描重跑，库和主目录样本会变，测试没锁

- 严重度：degrade
- 位置：`scripts/lib/sample_content.py` `discover_files`；`scripts/lib/kb_discover.py` `discover_vaults`；`scripts/lib/platform_win.py` `home_discover_skip_dirs`
- 目标如何失败：四个根的 `walk` 没有时间预算，计数重跑是稳的。不稳的是根以外的发现和 vault 选择。样本按目录名排序，但 15 秒到点就停在当时走到的位置；知识库 20 秒、且 `iterdir` 无序，凑满 3 个库或时间用尽时，两次扫描可以选出不同的库，深读的「这个人」跟着变。警告只有 `sample_budget_reached` / `kb_budget_reached`，不写少了哪一段。深度用尽和名额裁剪连这个记号都没有。准则第 0 到第 4 步不读 `scan_warnings`，模型仍把 `recent_files` 当成完整近况。Windows 跳过名单没有 `Local Settings`（名单里有一条非十六进制占位 GUID）。junction 不是 symlink，按名字排序会先钻进它；预算被它烧完以后，排在后面的中文目录（`工作`、`坚果云`）每次都到不了。
- 证据：`warnings.append("sample_budget_reached")` 与 `kb_budget_reached` 各只有这一串。`home_discover_skip_dirs` 含 `AppData`、`Application Data`，不含 `Local Settings`。行为 14 只断言预算标记和少了一个深路径文件；行为 21 只有一个扁平库。没有「同一输入连跑两次，vault 集合和近期文件集合一致」的断言。
- 如何确认：主目录放多个 vault，把知识库时间预算调到 1 秒，连跑两次，比较 `knowledge_bases` 的路径集合。
- 不成立的可能：家目录很小，15/20 秒和 8000/6000 目录都碰不到顶，且 vault 不超过 3 个。这时重跑差异消失。Windows 若 `iterdir` 根本不列出隐藏 junction，Local Settings 这条不触发；名单里的占位 GUID 仍然说明跳过集合不是按真实 junction 闭合的。
