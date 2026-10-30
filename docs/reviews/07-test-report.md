# v4.2.0 测试报告

日期：2026-10-26。版本 `4.2.0`。没有扫描真实家目录，没有提交。

这轮要让扫描回答「这个人在做什么」，而不是把某一种日记命名、软件自己的文件或私钥文件当成证据。

## 产品改动

- 日记只来自知识库自己的配置。Obsidian 读 `daily-notes.json` 的 `folder`，以及 periodic-notes 里已经启用且写了目录的 daily / weekly / monthly / quarterly。Logseq 读 `logseq/config.edn` 的 `:journals-directory`；没写这个键、且库里存在 `journals/` 时，才用默认目录。目录里的 Markdown 都算，不用 format、也不用文件名过滤。配置解析不出目录名时记 `journal_config_unparsed:`，日记为空。没有知识库时，日期开头的文件留在工作池。
- Logseq 图的标记是文件 `logseq/config.edn`。子目录 `.logseq/` 不是图。家目录下的 `.logseq` 仍因点开头被跳过，不当成图。
- 计数和采样跳过安装包、磁盘镜像、压缩包、`.log`、日志和缓存目录、常见聊天软件的数据目录（目录名整段相等）、以 `.app` 结尾的应用包，以及私钥文件（`.ppk` `.pfx` `.cer` `.crt` `.p8` `.keystore`，以及 `id_ecdsa` `id_dsa`）。`.key` 仍是 Keynote，只留文件名。笔记正文里的私钥和口令仍整份拒绝。
- 名额未改：候选 120、日记 8、每目录 3、下载 12、书籍 4。`count_is_total` 仍表示不按扫描模式截断。

## 审查闭环

| 步骤 | 报告 | 结果 |
|------|------|------|
| 日记配置 | `docs/reviews/08-journal-config.md` | 必须改：只认 `.logseq/` 会漏掉真实 Logseq 图 |
| 跳过名单 | `docs/reviews/09-skip-list.md` | 没有必须改 |
| 私钥与报告 | `docs/reviews/10-key-safety.md` | 没有必须改。文件名恰好是 `.pem` 的点文件会进 walk，但不会被打开 |
| 核实 | `docs/reviews/11-verified.md` | 只改 08-1。四种周期只留 3 条、folder 为 `.`、Org、主目录深度差，都不在这轮合同里 |
| 修正 | `kb_discover.py`、行为 21/25、README、CHANGELOG | 标记改为 `logseq/config.edn` |
| 责任点校验 | `docs/reviews/12-responsibility.md` | 没有必须改 |

责任点校验在临时目录复现了三组：有 `config.edn` 且没写日记目录时，`journals/` 里 12 篇「周一记事」是日记、`pages/` 里的日期名是工作文件，日记池每目录只进 3 篇；只有 `.logseq/` 的目录不会被发现；含 `BEGIN EC PRIVATE KEY` 的哨兵不进样本，`.ppk` 不在 walk 里，`QQ笔记` 的正文还在。

## 夹具怎么造

全部在测试脚本的临时目录里，用 `ENV_SCANNER_*` 把扫描根指过去。不读开发者的主目录。

- 行为 21：Obsidian 库写 `daily-notes.json`，`folder` 为 `07-Daily Note`。同一库的 `合同/` 里另有 12 份 `2024-01-*.md`，不进 `journals`。旁边的 Logseq 图只有空的 `logseq/config.edn`，没有 `journals/`，日记为空。自述 `个人画像.md` 被深读；含 OpenSSH 私钥头的 `个人总结.md` 被拒绝。
- 行为 23：`docs-b` 是带 `daily-notes.json` 的库，`日记/` 里 85 份日期文件只进样本 3 份，`市集/方案.md` 排在它们前面。`docs-f/日期名/` 没有库配置，10 份 `2024-03-*.md` 全部按工作文件入选。下载 40 份 pdf 仍只取 12。书籍 20 份只取 4。
- 行为 25：
  - Obsidian `daily/` 里是 `记事-N.md`，不是日期名，12 篇进日记，`kind` 为 daily。旁边 `weekly/` 的日期文件名不算日记。
  - Logseq 的 `config.edn` 只写了 page-title-format。`journals/周一记事-*.md` 12 篇算日记，`pages/` 的日期名不算。`{:journals-directory (str "journals")}` 得到空日记和 `journal_config_unparsed:`。只有 `.logseq/` 的目录不会被发现。
  - periodic-notes 里 daily 未启用，weekly 的目录是「周记」、文件名是「随便 N」。只留下 weekly 这一条。
  - 采样：配置目录 `diary/` 里混合日期名和「周一记事.md」，只入选 3 份。配置外的周报和 `1.n 背景` 全部入选。
  - 噪声：`.dmg` `.exe` `.zip` `.log` 不在 walk 里。`QQ/聊天.md` 和 `Tencent Files/记录.md` 不在。`QQ笔记/方案.md` 和 `关于QQ.md` 的正文在。`id_ecdsa` 和 `key.ppk` 不进样本。笔记里的 `BEGIN EC PRIVATE KEY` 仍整份拒绝。`演示.key` 的 `body_skipped` 是 `keynote`。

## 命令结果

在仓库根目录执行，2026-10-26。

| 命令 | 结果 |
|------|------|
| `bash tests/test-skill.sh` | 通过。核心文件、`config.json`、脚本语法均合法 |
| `bash tests/test-skill-behavior.sh` | 行为通过 25，失败 0 |
| `bash tests/test-skill-full.sh` | 通过 33，失败 0，警告 0。其中包含再跑一遍行为回归 |

全量里的证据版本断言是 `4.2.0`。`jq . config.json` 与 `python3 -m py_compile scripts/lib/*.py` 在改配置时已通过；全量测试又覆盖了 JSON 和语法。

## 这轮没有跑的部分

- 没有在真实 Windows 上跑 `run-scan.ps1`、注册表或 `os.startfile`。本机没有 PowerShell。行为 24 仍用 `ENV_SCANNER_PLATFORM=windows` 和替身验证目录逻辑。
- 没有复扫真实家目录，也没有打开 `~/.environment-scanner/reports`。
- 没有解压 zip。压缩包直接不进入计数和样本。
- 没有把普通 `.txt` 当成日志。只有 `.log` 和名为 log / logs / crash 的目录被跳过。
- 没有打开 `Library`，没有按每一个已安装软件名去扫，没有探测 GBK，没有改判断句式校验和 AI 关键词，没有改日记频率公式和 120 名额。
- 四种周期同时超过 10 篇时，证据仍只保留篇数最多的 3 条。这是原有上限，核实后不在这轮修改。
