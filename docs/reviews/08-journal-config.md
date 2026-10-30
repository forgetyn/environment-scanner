# 日记配置识别审查

审查范围只限日记识别和采样分池。夹具都在临时目录，调用了 `journal_specs`、`vault_stats`、`collect`、`collect_journal_dirs`、`candidate_pool`、`collect_samples`、`kb_html`。没有扫家目录，也没有读真实扫描报告。

## 结论

有必须改。一条：真实的 Logseq 图没有 `.logseq/`，日记配置和采样分池都不会生效，这个人的日记习惯会从证据里消失。

Obsidian 的 `daily-notes.json`、periodic-notes 的 enabled 和 folder、逃出库的路径、无库时的日期文件名，都按当前规则工作。名额和 `journal_min_files` 没有被改掉。

## 成立的问题

### 1. 真实 Logseq 图不会被当成知识库，日记目录也不会进入采样

- 严重度：必须改
- 位置：`scripts/lib/kb_discover.py` 的 `VAULT_MARKERS`、`find_vaults`、`discover_vaults`、`journal_specs`（有 `.logseq` 才读 `logseq/config.edn`）。`scripts/lib/sample_content.py` 的 `collect_journal_dirs` 用的是同一套 `find_vaults`。
- 夹具和断言：临时图里只有 `journals/周一记事-0.md` 到 `周一记事-11.md`、`pages/2024-02-01.md` 这一类日期文件，以及 `logseq/config.edn`（只写了 page-title-format，没有 journals-directory）。没有 `.logseq/`。`find_vaults` 和 `discover_vaults` 都是 0。直接对这个目录跑 `vault_stats`，`journals` 仍是 `[]`。`collect_journal_dirs` 是空的，`candidate_pool` 把「周一记事」判成 `work`。mtime 改成近期后再跑 `collect_samples`：12 篇周一记事全部入选，12 篇 pages 日期名也全部入选。这是工作池回填，不是日记的每目录 3。
- 对照：同一个结构加上 `.logseq/` 之后，没有 config.edn、但存在 `journals/` 时，证据是 1 条，`dir` 为 `journals`，`files` 为 12，`kind` 为 `daily`；`pages/` 里的日期名不算。采样把周一记事判成 `journal`。
- 为什么会看不懂：技能要求先发现知识库，再按那个库自己的配置认日记；判断准则又写明日记习惯不看文件名。Logseq 自己的图是 `journals/`、`logseq/config.edn`、`pages/`，没有 `.logseq/`。配置解析写对了，但门闩打不开，证据里就没有日记习惯。会话 AI 不能靠「周一记事」或日期文件名把这件事认回来。行为 21 和行为 25 的夹具自己创建了 `.logseq/`，所以这两项会过，盖不住这个洞。

### 2. 四种周期都达到门槛时，每季会被截掉

- 严重度：应该改
- 位置：`scripts/lib/kb_discover.py` 的 `vault_stats`。按篇数排序后只留 `[:3]`。
- 夹具和断言：periodic-notes 的 daily、weekly、monthly、quarterly 都 `enabled: true`，folder 都非空，各放 12 篇 `记事-N.md`。结果 `journals` 只有 3 条，没有 `quarterly`。篇数相同时顺序就是写入顺序，先丢掉每季。只开 quarterly 时，句子是「每季记」每季，说明文案本身有这个词。
- 为什么会看不懂：真正常年使用时，篇数几乎总是日大于周、周大于月、月大于季。每季只要和其他三种一起过了 10 篇，报告里就不会出现「每季」。季度复盘不会进入日记习惯，后面的协作节奏也看不到这一档。

### 3. folder 写成 `.` 时，整个库都算每日日记

- 严重度：记录
- 位置：`scripts/lib/kb_discover.py` 的 `_folder_inside`。空字符串会拒绝，单个 `.` 会解析成库根本身。
- 夹具和断言：`daily-notes.json` 的 folder 是 `.`。库根 12 篇项目稿，子目录里再 12 篇。`journals` 一条，`dir` 为 `.`，`files` 为 24，`span_days` 为 1，`weekly_freq` 为 168.0。
- 为什么要记一笔：空字符串、纯空白、缺字段、`null` 都不会把整库当日记，这是对的，Obsidian 没设目录时写的也是空字符串。但只要配置被写成 `.`，项目笔记会全部变成每日日记，频率按最少 1 天被抬到很高。采样也会按日记名额收这些文件。

### 4. Logseq 的 Org 日记不计数

- 严重度：记录
- 位置：`kb_discover.markdown_files` 和 `candidate_pool` 只认 `.md`、`.markdown`。
- 夹具和断言：有 `.logseq/` 的图，`journals/` 里 12 个 `.org` 和 12 个 `.md`。证据 `files` 是 12，Org 没有进去。
- 为什么要记一笔：Logseq 可以把首选格式设成 Org。这种人的日记既不进习惯统计，也不占日记名额。Markdown 用户不受影响。

### 5. 主目录上，采样找库比证据发现浅一层

- 严重度：记录
- 位置：`collect_samples` 对四个扫描根用 `KB_DEFAULT["max_depth"]`（5），对主目录用 `content_sample.home_depth`（4）。证据发现用 `kb_discover.max_depth`（5），而且从子目录开始数。
- 夹具和断言：每个深度放在各自的兄弟分支里，避免浅层库挡住深层库。文档根 `find_vaults` 找到的相对深度是 1、3、4、5。采样对主目录找到的是 1、3、4。证据 `discover_vaults` 同一次最多 3 个库，结果里有相对深度 5。`home/notes/Vault` 这种常见位置另测过：发现开启时记事按日记名额入选 3 篇。
- 为什么要记一笔：比主目录深 4 层、又不在四个扫描根里的库，证据可能已经写出日记习惯，采样既找不到这个库，也读不到里面的笔记。常见的「文档里的库」和「主目录下两层的库」不受影响。

## 查过但没有问题的点

- `is_dated_note_name` 已不在 `common.py`，`sample_content.py` 也不再引用。无库时 `2024-01-12.md`、`2026-10-25-周记.md`、`10.25、先.md`、`2024-01-N.md`、`周报2026-10-01.md`、`1.1 背景.md`、`周一记事.md` 的 `candidate_pool` 都是 `work`。
- 无库夹具：同一目录 10 份周报全部入选，6 份 `1.n 背景` 全部入选，7 个日期开头再加 1 篇周一记事也全部入选，没有被日记的每目录 3 截断。
- Obsidian `daily-notes.json` 的 folder 是「日记」、format 是 `YYYY-MM-DD`：12 篇 `记事-N.md`、`not-date.md`、`note.markdown`、子目录里的一篇都算，合计 `files` 15；旁边的 `忽略.txt` 不算。format 只出现在字段里，没有拿来滤文件名。合同目录里的日期名和周报不进 `journals`。
- 同一个日记目录再被 periodic-notes 的 daily 指一次，`(path, kind)` 去重后仍是 1 条。核心插件的「手账」和已启用的「周记」会同时留下；`enabled: false` 的「旧每日」里全是日期文件名，不算。
- periodic-notes 四种都 `enabled: false` 时，目录里全是日期文件名，`journals` 仍是空。`yearly` 即使 enabled 也不在统计里。`enabled: true` 但 folder 为空、空白、缺字段或 `null` 时，`journals` 为空，库根和另一个目录里的 `YYYY-MM-DD` 文件采样仍是 `work`，也没有 `journal_config_unparsed:`。
- 有 `.logseq/`、没有 config.edn、存在 `journals/`：周一记事 12 篇进证据，`pages/` 的日期名不算。`journals/` 不存在就不猜。config 里没写这个键，或者这行被 `;;` 注释掉，仍用默认 `journals`；format 保存的是 `:journal/page-title-format`，不是 file-name-format，也不按它滤文件名。自定义目录「我的日记」不会回退到默认 `journals`。
- `:journals-directory (str "journals")`：`journals` 为 `[]`，`scan_warnings` 有 `journal_config_unparsed:`。采样的日记目录也是空的，周一记事和 pages 都是 `work`。带引号的绝对路径、`~`、`..`、`journals/../../outside`、空字符串，以及不带引号的 `../` 和 `~/`，同样是空日记加这条警告，不会改用本地 `journals/`。指向库外的符号链接目录也被拒绝。Obsidian 的绝对路径、`~` 和 `..` 同样不进 `journals`，只是不写这条警告。
- 配置目录里的 12 篇记事，`collect_samples` 只入选 3。旁边的 10 份周报、7 个日期开头、6 份 `1.n 背景` 全部入选。目录里只有这 12 篇日记、没有别的文件时，结果仍是 3，剩余名额不会把日记回填进来。三个已启用目录各 6 篇时，入选父目录计数是 3、3、2，合计 8，没有超过每目录 3。
- 采样前的日记目录和 `journal_specs` 是同一批路径。未启用的 daily 是 `work`，启用且 folder 为「月记」的记事是 `journal`。文档根和桌面根里的记事是 `journal`，各入选 3，旁路的日期名是 `work`。下载根和书籍根也能找到 vault，但 `candidate_pool` 先判下载和书籍：下载目录 20 篇记事加 1 篇旁路入选 11+1，用的是下载上限 12；书籍根入选 4，用的是书籍上限。这不是按文件名分池。
- 发现开启时，主目录 `notes/Vault` 的记事入选 3，旁路日期文件单独入选。发现关闭时，这个库不进样本。四个扫描根在配置深度内都能找到带 `.obsidian` 的库。
- 证据条目含 `dir`、`kind`、`format`、`files`、`span_days`、`weekly_freq`。12 篇 mtime 相同：`span_days` 1，`weekly_freq` 84.0。10 篇首尾相距 9 天：`span_days` 9，`weekly_freq` 7.78。9 篇不进 `journals`，10 篇进。`load_kb_config()` 的 `journal_min_files` 是 10。`load_sample_config()` 仍是候选 120、日记 8、每目录 3、下载 12、书籍 4。
- `kb_html` 对四种 kind 分别写出每日、每周、每月、每季。拼在一起的句子是「「每日记」每日12 篇/持续 9 天」，后面按同样句式接每周、每月、每季。`./日记` 和 `日记/` 各数到 12 篇，旁边的项目稿不算。
- 证据发现不进入名为 Library 的目录。采样的 `find_vaults` 会把夹具里 Library 下的 vault 收进日记目录列表，但 `discover_files` 仍跳过它，样本里这些文件是 0。分池结果没有变，不作为缺陷重开。
