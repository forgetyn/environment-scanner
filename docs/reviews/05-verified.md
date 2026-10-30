# 核实结果

对照 `scripts/lib` 与一份临时夹具（不改仓库数据）。严重度按核实后的影响重标，四份报告里的 blocker 都没有维持。

## 成立

### C1 深读会把「关于我们」「如何写简历」当成这个人是谁
- 判定：成立
- 来源：E1
- 严重度：degrade
- 位置：`scripts/lib/kb_discover.py` `find_self_docs`、`deep_read`、`collect`
- 代码里实际发生的事：词典是子串，`.md/.markdown/.txt` 才读。夹具里的 `关于我们.md` 和 `简历.md` 都被读进 `deep_reads`。每个 vault 各取最近 3 份再追加，三个库最多 9 份；`SKILL.md` 写的是最近 3 份。私钥命中的那份直接丢掉，不会改读下一份。
- 为何伤害目标：准则把 `deep_reads` 当成职业和自我认知的最强证据。公司介绍或简历模板会变成「这个人是谁」，第一件交给 AI 的事跟着偏。真正的 `.docx`/`.pdf` 简历走不到这条通道。
- 建议是否在本轮修改：改。收紧成完整文件名或加边界，并改成全局最多 3 份。不要改发现深度。

### C2 章节号和文中日期被当成日记，名额把正在写的稿挤掉
- 判定：部分成立
- 来源：E2
- 严重度：degrade
- 位置：`scripts/lib/common.py` `is_dated_note_name`；`scripts/lib/sample_content.py` `select_candidates`
- 代码里实际发生的事：`20xx-月` 出现在文件名任意位置，或开头是 `1.1 ` 这种章节号，就离开工作池。日记每目录 3 份、总共 8 份，只有工作池能回填。夹具里 10 份 `周报2026-10-*.md` 只留下 3 个名字，6 份 `1.1 背景.md` 只留下 3 个，没有警告。120 个名额、目录轮转、日记/下载/书籍上限本身是文档写明的，不是这条的问题。
- 为何伤害目标：模型按 `recent_files` 认近况。一叠章节稿或带日期的合同会像「偶尔写日记」。`activity_heat` / `weekly_counts` 只数这份样本；四个根的全量还在 `structure.top_dirs` 和 `structure.extensions`，所以不是完全没有另一份计数。
- 建议是否在本轮修改：改。只收紧「像日记」的规则，让章节号和夹在合同名里的日期留在工作池。不要动 120 和日记上限。带日期的周记继续进日记池，这是 `is_dated_note_name` 的注释。

### C3 常见办公格式没有文件名，`seed` 子串把文件从总量里抹掉
- 判定：部分成立
- 来源：E3
- 严重度：degrade
- 位置：`scripts/lib/sample_content.py` `DOCUMENT_EXTENSIONS`、`consider_file`；`scripts/lib/scan_collect.py` `skip_file`、`skip_dir`
- 代码里实际发生的事：近期名单只有 `.md/.markdown/.txt/.csv/.docx/.pptx/.pdf/.xlsx`。夹具里的 `周报.pages`、`方案.doc` 不在 `recent_files`，但 `structure.extensions` 仍有 `.pages` 和 `.doc`，文件类型图能看见。`seed-round.docx` 因文件名含 `seed` 被整份跳过，计数和样本都没有，`scan_warnings` 为空，`count_is_total` 仍是 true。`wallet`、`crypto` 同样是子串。
- 为何伤害目标：非技术用户的 Pages、旧 `.doc` 没有文件可写进第一步。种子轮材料或带这些词的笔记会像从未存在，模型却以为计数是总量。PDF/xlsx 不解析正文是已公开限制，这条不是那个。
- 建议是否在本轮修改：改。`.pages/.key/.numbers/.doc/.rtf` 至少像 PDF 一样留下文件名，不必解析正文。`wallet`/`crypto`/`seed` 改成整词或固定文件名，不要无声吃掉普通文件名。

### C4 云盘笔记和符号链接目录会像「这个人不写东西」
- 判定：部分成立
- 来源：E4
- 严重度：degrade
- 位置：`scripts/lib/platform_mac.py` `home_discover_skip_dirs`；`scripts/lib/sample_content.py` `discover_files`；`scripts/lib/kb_discover.py` `discover_vaults`；三处 `is_symlink()`
- 代码里实际发生的事：主目录发现和知识库发现都跳过名为 `Library` 的目录，不写「未扫描」。因此 `~/Library/Mobile Documents/` 里的 iCloud Obsidian、`~/Library/CloudStorage/` 里的 OneDrive/Google Drive 不会进 `knowledge_bases` 或近期文件。符号链接目录直接跳过。四个根本身没有深度上限；家目录发现在第 4 层停下，也不记 `sample_budget_reached`。
- 为何伤害目标：笔记只放在这些路径时，成功的扫描仍是 `knowledge_bases: []`，报告会像没有写作习惯。打开「iCloud 桌面与文稿」时路径仍是 `~/Documents` 和 `~/Desktop`，不受影响。跳过 `Library` 已写在 `SKILL.md`，不是未文档化的笔误。
- 建议是否在本轮修改：不改。整棵放行 `Library` 会扫进系统数据。要单独放行 iCloud/CloudStorage 的文档路径，是新的发现规则，不是这一轮的小修补。

### C5 根不存在，或字典序靠前的空 OneDrive，仍写成一份成功的总量
- 判定：部分成立
- 来源：E5、P2
- 严重度：degrade
- 位置：`scripts/lib/scan_collect.py` `assert_root_readable`、`walk`、`collect`；`scripts/lib/platform_win.py` `default_user_roots`
- 代码里实际发生的事：目录不存在时 `assert_root_readable` 直接返回，`walk` 给空列表，不记警告，`count_is_total` 仍是 true。夹具四个根都不存在时，进程照样给出全 0。Windows 适配器按 `OneDrive*` 字典序，碰到第一个含 `Documents` 的目录就返回。夹具里空的 `OneDrive/Documents` 盖住了 `OneDrive - Contoso/Documents` 里的文件，也盖住 `~/Documents`。下载目录不参加这次探测。书籍固定是桌面下的 `书籍`。
- 为何伤害目标：证据仍是合法 JSON，KPI 会写「电子书 0」「笔记总数 0」。模型可以据此说没有书、没有笔记。macOS 上缺的通常只是本来就没有的 `~/Desktop/书籍`，0 在那里是「默认文件夹不存在」。真正写错树的是多个 OneDrive 时选中空的那一个。`obsidian_notes` 只是文档根里的 markdown 篇数，桌面上的笔记不算，普通 README 算；近期文件列表仍能看见桌面文件，所以这不是「完全没扫到」。
- 建议是否在本轮修改：改。多个 `OneDrive*` 时不要采用空目录，空的再回落到下一个或 `~/Documents`。根不存在时记一条警告，不要把扫描改成失败——书籍目录经常不存在，失败会让正常 macOS 扫描停掉。

### C6 应用名和正文的宽匹配会把普通软件标成已经在用 AI
- 判定：部分成立
- 来源：E6
- 严重度：degrade
- 位置：`scripts/lib/evidence_pack.py` `AI_TEXT_MARKERS`、`AI_APP_KEYWORDS`、`ai_usage_signals`
- 代码里实际发生的事：正文里的 `skill`、`agent`、`自动化` 会记成 AI 痕迹；`用AI写周报` 因为中文和 AI 之间没有词边界，反而不算。应用名是子串：夹具里的 `UltraEdit` 进入了 `ai_apps`（含 `trae`），`CursorSense` 会含 `cursor`。分母是裁剪后的 `recent_files`。准则没有份数门槛。
- 为何伤害目标：画像看这个结构。误命中多时，模型可能把新手标成 power，不再给从零开始的第一步。单次 `skill` 不会由代码自动改写 `persona`，模型仍能看见命中的原文。装过就算、超过 400 个按字母截断，是清单本身的形状，不是这条的主要失败。
- 建议是否在本轮修改：不改。信号是给模型看的启发式，不是自动画像。收紧词表要连同「用AI写」这种漏报一起重做，超出这一轮。

### C7 「顶层目录」实际是直接父目录，日记周频在同一天的 mtime 上被抬高
- 判定：部分成立
- 来源：E7
- 严重度：degrade
- 位置：`scripts/lib/kb_discover.py` `vault_stats`
- 代码里实际发生的事：`top_dirs` 用 `path.parent.name`，满 3 篇才计入，所以 `项目/2024/01/日期.md` 的领域是 `01`，不是 `项目`。日记分组用的是相对路径第一段。`span_days` 用 mtime，并且至少为 1 天；30 篇 mtime 相同会得到每周 210 篇。日记门槛读的是代码里的 `DEFAULT_CONFIG`（10），不是已经载入的配置；两边现在都是 10，改配置才会失效。
- 为何伤害目标：准则要求用日记频率和知识库结构写「这个人怎么工作」。嵌套库会被说成在 `01` 里工作；拷贝或同步把 mtime 收成同一天时，会按一个不存在的每日强度去设计协作。笔记篇数本身仍是数过的。
- 建议是否在本轮修改：不改。篇数和路径还在，模型能对照文件名。改父目录层级和频率公式会牵动行为 21 的日记合同，不是这一轮必须的。

### C8 私钥和口令只认很窄的一种写法，其余进摘录
- 判定：成立
- 来源：S1、S2、S5
- 严重度：degrade
- 位置：`scripts/lib/common.py` `SECRET_PATTERNS`；`scripts/lib/sample_content.py` `build_record`、`read_text_limited`、`office_xml_text`；`scripts/lib/kb_discover.py` `deep_read`
- 代码里实际发生的事：能整份拒绝的是 `BEGIN PRIVATE KEY`、`BEGIN RSA PRIVATE KEY`、`BEGIN OPENSSH PRIVATE KEY`，以及单词边界后的 `password`/`passwd`/`api_key`/`secret` 再加半角 `:` 或 `=`。实测 `BEGIN EC PRIVATE KEY`、`BEGIN ENCRYPTED PRIVATE KEY`、PGP、PuTTY、`"password": "..."`、`DB_PASSWORD=`、`密码:`、`口令=` 都是 `None`，正文继续进入 `excerpt` 或 `deep_reads.text`。UTF-16 的 ASCII 之间留下 NUL，同一条正则也不命中。Office 文本把标签换成空格后，被拆开的 RSA 头会变成双空格，连已覆盖的头也会漏。`password=`、`api_key:`、`export SECRET=` 仍会拒绝。
- 为何伤害目标：`SKILL.md` 写的是发现私钥块或口令赋值就整份丢弃、禁止引用。漏网的材料写进证据 JSON，摘录再进入两份报告的原始 JSON。产品读的是中文笔记和简历，中文「密码」恰好不在规则里。
- 建议是否在本轮修改：改。补上常见 PEM 头、JSON 引号、下划线前缀和中文「密码/口令」；比较前去掉 NUL。不要为此做编码探测，GBK 缺字仍按已公开限制保留。

### C9 同一份简历的正文经摘录进入报告，深读字段的打码盖不住
- 判定：成立
- 来源：S3
- 严重度：degrade
- 位置：`scripts/lib/sample_content.py` `build_record`；`scripts/lib/evidence_pack.py` `build_evidence`；`scripts/lib/judgment.py` `render`；`templates/final-report.html` 的 `{{RAW_JSON}}`
- 代码里实际发生的事：渲染只把 `deep_reads[].text` 换成「仅判断 AI 可读」。采样是另一条管道，不按深读路径排除。夹具里 90 天内的 `简历.md` 同时在两个列表里，摘录含「电话 13800138000」和邮箱。证据 JSON 和两份 HTML 的折叠区都有这些句子；可见表格只有文件名。`CHANGELOG.md` 写过手机号和邮箱不会出现在报告任何位置，和这次渲染相反。
- 为何伤害目标：声明是自述正文不进报告。用户展开原始数据就能看到简历开头。证据 JSON 里留全文给判断 AI，这一点与声明一致，不是这条的失败点。
- 建议是否在本轮修改：改。渲染时按路径去掉已深读文件的 `excerpt`，或采样阶段不要再读这些文件的正文。不要把深读全文重新放进报告。

### C10 校验会放行没有开场提示词的判断，但编造文件名仍然被挡住
- 判定：部分成立
- 来源：F1
- 严重度：degrade
- 位置：`scripts/lib/judgment.py` `validate`；行为 09、行为 19
- 代码里实际发生的事：活动、角色、第一步、理由只要求非空。有文件时，第一步只要包含其中一个文件名。只有指标时，第一步可以是「先做一下」。`quick_win` 全是 false 时不检查第一条；`effort: high` 也可以标 `quick_win: true`。用这份形状调用 `validate`，返回空错误。行为 09 的合格样本就是「把《活动方案.md》交给 AI。」，没有「不要补充文件里没有的事实」。不存在的文件名、没点名文件的第一步、不存在的优先级 id，测试会拒绝。
- 为何伤害目标：三件事可以被一句空话渲染成完整报告，用户以为已经知道该给 AI 什么。文件名伪造这条门禁是有效的，报告把「校验完全不看内容」说重了。已公布的校验规则也没有承诺检查提示词句式，它只承诺文件名要出现。
- 建议是否在本轮修改：不改。收紧句式是新合同，会把现在测试锁住的合格样本全部打红。这一轮不把语义审查加进 `validate`。

### C11 优先区块不展示可复制的第一步，但建议卡里有
- 判定：部分成立
- 来源：F2
- 严重度：degrade
- 位置：`scripts/lib/judgment.py` `priority_block`、`suggestion_card`、`render`；`templates/final-report.html` 导航
- 代码里实际发生的事：优先卡只渲染 `why`、`how_to_start`、`long_term` 和建议的 `activity`，不渲染 `first_step`。建议卡有「第一步」全文，并且排在优先区块前面。非 power 的开篇固定写「标还没用 AI 的，是最先值得尝试的地方」，不检查那一行有没有对应建议。时间分配图用的是样本目录文件数占比，标题已经写了「活跃目录占比」。
- 为何伤害目标：从「最值得优先尝试」点进去的人看不到要交的文件和提示词，除非模型把同一句话写进 `how_to_start`。建议区仍然有第一步，所以不是整页都没有答案。
- 建议是否在本轮修改：不改。把 `first_step` 抄进优先卡、重排导航，是版式改动。建议卡已经带着可执行的一步。

### C12 文件名必须真实，目录可以编，指标值为 0 也算存在
- 判定：部分成立
- 来源：F3
- 严重度：degrade
- 位置：`scripts/lib/judgment.py` `ref_error`、`metric_lookup`、`suggestion_card`
- 代码里实际发生的事：文件引用只查 `name` 是否在 `recent_files` 或 `deep_reads` 里，不查 `parent`。`parent` 写成「完全编造/不存在」时 `validate` 通过，报告把 `parent/name` 拼进「用到的证据」。`counts.ebooks` 为 0 时查找结果不是 `None`，引用通过。两个真实文件只在第一步里出现一个也通过。`knowledge_bases.0.notes` 因为路径走进列表而失败。
- 为何伤害目标：第一步可能把人指到一个编出来的目录。文件名仍必须真实，按文件名还能找到。指标通道是技能明确允许的；值为 0 表示这个字段在，不表示书库里有书。
- 建议是否在本轮修改：不改。补 parent 核对要先规定它必须等于证据里的 `parent`。当前合同只检查文件名，用户不至于拿到一份不存在的文件。

## 已驳回

- F4：`校验规则` 只承诺「没有任何 AI 痕迹却给升级建议」和「power 至少一条升级」。代码就是这样。`deep` 活动仍可配 `basic`、`persona` 不跟 `ai_usage_signals` 对账，这是准则比门禁严，不是门禁写了却没做。行为 19 的周报样本是 `occasional` 配 `basic`，技能允许。
- F5：有建议时四张理解卡各 2–6 条，写在 `SKILL.md` 校验规则里，也写在 `validate` 里。比合同更瘦的判断被拒，是合同生效，不是放行套话。
- F6：`zero_signal` 的定义就是没有近期文件且没有应用名，错误文案也这么写。深读文件名可以引用，但标志为真时禁止建议。macOS 正常会扫到 `/Applications`，这条很少触发；近期文件和深读都空时禁止编造是对的。
- E8：四个根的 `walk` 不看时间预算，重跑计数是稳的。样本发现按目录名排序。知识库 `iterdir` 不排序，只在超过 3 个库或 20 秒用尽时才会换库。预算用尽已有 `kb_budget_reached` / `sample_budget_reached`。家目录不大时两次扫描不会变。
- S4：默认路径上 `Library` 被整棵跳过，`.ssh` 因点开头被跳过，系统钥匙串和 `~/.ssh` 读不进来。`keychains` 大小写、扫描根里一个叫 `Library` 的普通目录、硬链接，都要用户自己放进扫描根才发生。`skip_sensitive_dirs` 没有读者，改它不改变行为，但现行跳过名单走的是 `skip_dir_names`，默认扫描没有因此漏读密钥。
- S6：`SKILL.md` 要求把拒绝文件记入 `rejected_documents`。绝对路径留在审计列表和折叠区是这份合同，不是把密钥正文写回去。建议里的文件名必须落在 `recent_files` 或 `deep_reads`，同名普通文件才能再次被引用。判断正文不再扫一遍私钥，超出采样边界的声明。
- P1：`windows_registry_unavailable` 在没有 `winreg` 时，以及导入成功但一个 `DisplayName` 都没有时，用了同一条字符串。`SKILL.md` 把这条定义成「没有 winreg」。Program Files 不存在会从 `sources` 消失。这是未实机的 Windows 清单边缘，空名单在页面上已经写成「没有收集到应用清单」，不是把别人的应用编出来。
- P3：`ENV_SCANNER_PLATFORM` 优先于本机系统，`SKILL.md` 写了这是强制开关。`run-scan.sh` 不清除它；证据里的 `scan.platform` 仍是 `platform.system()`。只有这个变量被留在环境里才会换适配器。默认不设置时走 macOS 适配器。
- P4：各阶段是一次 `write_text` 完整 JSON。子进程非零时入口不会继续合并。半截文件只出现在写入过程中被杀掉之后。`SKILL.md` 让下一步读最新证据，这是崩溃残留，不是一次成功扫描交出坏证据。根不可读发生在写文件之前。
- P5：ps1 打印 Win32 路径，`generate-final-report.sh` 用 `[ -f ]`。仓库没有在 Windows 上跑过这条交接，不能把「bash 一定打不开」写成已发生的事实。最终报告第二步仍是 bash，这是已写明的分工。
- P6：跳过名单没有 `Local Settings`，`Contact` 对不上 `Contacts`，占位 GUID 不是目录名，junction 也不是 `is_symlink()`。默认 ACL 拒绝列出这些 junction 时，代码记 `unreadable:` 后返回，不烧预算，也不把目标树算进文件。`AppData` 本身在名单里。
- P7：行为 15、16、22、24 有的断言是在本机 Python 里真的跑了（冒号分隔、OneDrive 被选中、无 `winreg` 时的警告、`startfile` 补丁）。源码子串和「未实机验证」几个字锁得松，这是测试缺口，不是用户拿到的证据错了。文档已经写明 ps1 未在真实 Windows 上执行。
- P8：按文档使用分号和冒号、两侧不留空格时，macOS 路径不会被切成盘符。空格会让 `Path(" ~/x")` 展不开波浪号并被静默丢掉，文档没有让用户写成带空格的分隔。设置 `ENV_SCANNER_APPLICATIONS` 后改走一级目录名，是覆盖扫描根的既有测试合同（行为 15），不是两套分隔符互相切错。
