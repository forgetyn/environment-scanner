# 核实结果（08 / 09 / 10）

对照当前未提交代码（目标 v4.2.0）和临时目录夹具。没有改业务代码、测试或配置。没有扫家目录，没有读 `~/.environment-scanner/reports`。夹具文件名都是假名。

## 总结

要改的只有 08-1。

08-2、08-3、08-4、08-5 都能复现，但不是这轮把原来对的行为改坏，合同也没有这些，不改。09 抽查的两处和原文一致，不改。10 的「文件名恰好是 `.pem`」能复现，正文没有被读进摘录或深读，不改。

## 逐条

### 08-1 真实 Logseq 图不会被当成知识库

- 来源：`docs/reviews/08-journal-config.md` 第 1 条
- 原严重度：必须改
- 是否复现：复现
- 建议：改
- 证据：
  - 代码只认子目录 `.logseq/`。`VAULT_MARKERS`、`find_vaults`、`discover_vaults` 都查这个目录；`journal_specs` 也要先看到 `.logseq/` 才去读 `logseq/config.edn`。采样的 `collect_journal_dirs` 用的是同一套 `find_vaults`。
  - 临时图只有 `journals/周一记事-0.md` 到 `周一记事-11.md`、`pages/2024-02-01.md` 这一类日期名，以及 `logseq/config.edn`（只写了 `:journal/page-title-format`，没有 `:journals-directory`）。没有 `.logseq/`。`find_vaults` 和 `discover_vaults` 都是 0。`journal_specs` 是空的，没有 `journal_config_unparsed:`。`vault_stats` 的 `journals` 是 `[]`。`collect_journal_dirs` 是 0。`candidate_pool` 把周一记事和 pages 都判成 `work`。`collect_samples`（`deep`，发现关闭，根在临时目录）入选 24 份：周一记事 12、pages 12。这是工作池回填，不是日记的每目录 3。
  - 直接调用 `logseq_journal_specs`（不经过 `.logseq/` 门闩）得到 1 条，`dir` 为 `journals`，警告是空的。解析本身会按「没有这个键，且 `journals/` 存在」用默认目录。门闩不打开，这条结果到不了证据，也到不了采样分池。
  - 对照：同一结构改成有 `.logseq/`、没有 `config.edn`、仍有 `journals/`。`find_vaults` 和 `discover_vaults` 都是 1。`journals` 1 条，`dir` 为 `journals`，`kind` 为 `daily`，`files` 为 12。周一记事的池是 `journal`，入选 3。pages 的池仍是 `work`，入选 12。日期文件名没有被当成日记。
  - 公开资料里的文件图不是 `.logseq/`。Logseq 源码 `deps/common/src/logseq/common/config.cljs` 把 `app-name` 定义成 `"logseq"`。`src/main/frontend/config.cljs` 的 `get-repo-config-path` 是 `app-name` 拼上 `config.edn`，也就是 `logseq/config.edn`；同文件注释写发布样式在 `repo-dir/logseq/export.css`。官方文档仓库 [logseq/docs](https://github.com/logseq/docs) 的根上有 `journals/`、`pages/`、`logseq/config.edn`，目录列表里没有 `.logseq`。这份 `config.edn` 本身也没有 `:journals-directory`。官方说明 [How to create a Logseq graph using existing Markdown files](https://github.com/logseq/docs/blob/master/pages/How%20to%20create%20a%20Logseq%20graph%20using%20existing%20Markdown%20files.md) 写新建图会创建 `journals`、`pages`、`assets`。
  - `.logseq` 这个名字出现过，但不是图里的目录。Issue [#8308](https://github.com/logseq/logseq/issues/8308) 里有人提议把图内的 `logseq` 改成 `.logseq`（仿 Obsidian）。维护者回复不想做这个破坏性改名；该 issue 仍开着。`src/electron/electron/configs.cljs` 的 `dot-root` 是家目录下的 `.logseq`，那是应用自己的全局配置和缓存，不是某一张图的标记。论坛说明也把两者分开：用户选定的图里有一个叫 `logseq` 的目录，里面是 `config.edn`；`~/.logseq` 是插件、设置和缓存。

### 08-2 四种周期都过门槛时，每季被截掉

- 来源：`docs/reviews/08-journal-config.md` 第 2 条
- 原严重度：应该改
- 是否复现：复现
- 建议：不改
- 证据：periodic-notes 的 daily、weekly、monthly、quarterly 都启用，目录都非空，各 12 篇。`journals` 只有 daily、weekly、monthly，没有 quarterly。`vault_stats` 按篇数排序后只留 `[:3]`。篇数相同时稳定排序先丢掉每季。这个 `[:3]` 在本轮 diff 之前就有（当时按日期目录名分组，同样只留 3 条）。本轮没有要求四种周期同时出现在证据里。日记每目录 3 条是采样名额，和这条截断不是一回事，也不在这次要改的范围里。

### 08-3 folder 写成 `.` 时，整个库都算每日日记

- 来源：`docs/reviews/08-journal-config.md` 第 3 条
- 原严重度：记录
- 是否复现：复现
- 建议：不改
- 证据：`daily-notes.json` 的 folder 是 `.`。库根 12 篇，子目录再 12 篇。`journals` 一条，`dir` 为 `.`，`files` 为 24，`span_days` 为 1，`weekly_freq` 为 168.0。`_folder_inside` 拒绝空字符串、绝对路径和 `..`，但单个 `.` 会解析成库根。这是本轮新的配置路径，不是把原来已经拒绝的整库日记改坏。本轮合同没有要求再拒绝 `.`。

### 08-4 Logseq 的 Org 日记不计数

- 来源：`docs/reviews/08-journal-config.md` 第 4 条
- 原严重度：记录
- 是否复现：复现
- 建议：不改
- 证据：有 `.logseq/` 的图，`journals/` 里 12 个 `.org` 和 12 个 `.md`。证据 `files` 是 12。`NOTE_SUFFIXES` 只有 `.md` 和 `.markdown`。上一版统计笔记时用的也是这两个后缀。本轮合同没有要求把 Org 算进日记。

### 08-5 主目录上，采样找库比证据发现浅一层

- 来源：`docs/reviews/08-journal-config.md` 第 5 条
- 原严重度：记录
- 是否复现：复现（只核了深度差，没有重跑审查里的整段深度矩阵）
- 建议：不改
- 证据：临时主目录下放了相对深度 4 和 5 两座带 `.obsidian/` 的库，分属不同分支。`find_vaults` 用采样的 `home_depth` 4 时只找到深度 4。同一个函数用知识库的 `max_depth` 5，以及 `discover_vaults`（`max_depth` 5），都找到 4 和 5。`collect_samples` 对四个扫描根用深度 5，对主目录用 `home_depth` 4。`home_depth: 4` 在本轮 diff 之前就已经是 4，知识库深度也已经是 5。本轮合同没有要求把这两层对齐。

### 09 跳过名单抽查

- 来源：`docs/reviews/09-skip-list.md`（原文结论是没有问题）
- 原严重度：无
- 是否复现：抽查与原文一致。没有重跑整份矩阵
- 建议：不改
- 证据：`skip_dir("QQ笔记")` 为假，`skip_dir("QQ")` 为真。临时根里的 `QQ笔记/方案.md` 在 `walk` 结果里，摘录里有「用户方案正文标记」。同一次 `walk` 没有 `.dmg`，打开记录里也没有它，安装包哨兵不在样本 JSON 里。

### 10 文件名恰好是 `.pem`

- 来源：`docs/reviews/10-key-safety.md` 的记录
- 原严重度：记录
- 是否复现：复现
- 建议：不改
- 证据：`Path(".pem").suffix` 是空字符串，`Path("a.pem").suffix` 是 `.pem`。`skip_file(".pem")` 为假，`skip_file("a.pem")` 为真。`walk` 能看见文件名 `.pem`，看不见 `a.pem`。采样没有打开 `.pem` 或 `a.pem`。两个哨兵都不在样本 JSON 里。旁边的普通笔记被读了，说明不是追踪器没记到打开。放进带 `.obsidian/` 的库之后，`find_self_docs` 只返回 `个人总结.md`，不会选 `.pem`。正文因此进不了摘录、深读或报告。不为这个点文件把 `.key` 收进私钥后缀。

## 最小改法

只改 08-1 的识别标记。Logseq 图的标记改成「这个目录里有文件 `logseq/config.edn`」。`find_vaults`、`discover_vaults` 和 `journal_specs` 用同一处判断。采样不用再单独写一套。认到图之后，仍走现在的 `logseq_journal_specs`，不要另写日记规则。

日记只来自这份 `config.edn`。没有 `:journals-directory` 这个键，并且库里存在 `journals/` 时，才用默认目录 `journals`。键在，但解析不出目录名时，`journals` 为空，并记 `journal_config_unparsed:`。`pages/` 和其他配置目录以外的日期文件名仍是工作文件。不要按文件名猜日记。

不要把家目录下的 `~/.logseq` 当成图。那是应用的全局目录，不是文件图。也不要继续把「有一个 `.logseq/` 子目录」当作真实图的标记；官方图没有这个目录。`README.md` 里把 Logseq 标记写成 `.logseq/` 的那一句要改成 `logseq/config.edn`，否则文档还在教错误的图。行为测试现在自己创建 `.logseq/`，那测不到真实图；夹具要改成带 `logseq/config.edn` 的图，解析规则不用放宽。
