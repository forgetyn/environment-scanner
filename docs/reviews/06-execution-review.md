# 执行审查（4.1.1 的六条）

对照 `docs/reviews/05-verified.md` 里「建议是否在本轮修改：改」且已收窄的 C1、C2、C3、C5、C8、C9。只读当前实现，夹具在临时目录里调用函数，没有扫描真实家目录，没有改业务代码。版本号 4.1.1 在 `config.json`、`SKILL.md`、`CHANGELOG.md` 的新节，以及 `run-scan.sh`、`run-scan.ps1`、`evidence_pack.py`、`judgment.py` 上已经对齐，不把这件事当漏改。

## 结论

通过。六条都按收窄后的范围实现，临时夹具的边界断言全部通过。没有发现会让目标失败或把正文泄进报告的新缺陷。

## C1 深读词典

按核实范围实现。`stem_matches_self_doc` 先看拒绝标记（关于我们、如何、怎么、怎样、教程、模板、范文、示例，子串），再要求 stem 与关键词全等，或 `endswith`。后缀仍只有 `.md`、`.markdown`、`.txt`。`collect` 把各库命中合在一起，按修改时间取 `max_deep_reads`（配置仍是 3）再读；读的时候发现私钥就丢掉，不从后面补。`max_depth` 仍是 5，`max_vaults` 仍是 3。

夹具结果：

- `关于我们`、`如何写简历`、`简历模板`、`怎样写简历`、`怎么写简历`、`简历示例`、`简历教程`、`简历范文`、`关于我们的简历` 不命中。`个人画像`、`简历`、`我的简历`、`个人总结`、`自我介绍`、`关于我`、`个人情况` 命中。`个人情况登记表`、`个人画像备份` 不命中，因为选定规则是全等或结尾，不是子串。`备份个人画像` 因结尾命中。
- 一个库里同时放 `关于我们.md`、`如何写简历.md`、`简历模板.md`、`个人画像.md`、`简历.md`、`我的简历.md`，以及更新的 `简历.docx`、`简历.pdf`。`deep_reads` 正好是那三份 Markdown，正文在；公司介绍、教程腔、模板、docx、pdf 的句子都不在。
- 四个库各两份自述，磁盘上 8 份。发现阶段仍只进 3 个库（原有 `max_vaults`，本轮不要求改发现深度），这 6 份里 `deep_reads` 是 3，不是每库各读、也不是 6 或 8。
- 私钥那次：更新的 `个人总结.md` 含 `BEGIN EC PRIVATE KEY`，其后是 `个人画像.md`、`我的简历.md`，更旧的 `简历.md` 也匹配词典。结果只留下前两份干净自述，`简历.md` 没有被补进来，密钥句子不在 JSON 里，`rejected_deep_reads` 记下 `private_key`。`关于我们.md` 和 `如何写简历.md` 即使更新也不占名额。

偏离点：无。

## C2 日记误判

按核实范围实现。`is_dated_note_name` 只认开头：`20xx` 加分隔符再加月，或开头的 `月.日` 后面是顿号、逗号或结束。空格章节号对不上。`select_candidates` 和 `vault_stats` 共用这个函数。120、日记 8、每目录 3、每目录工作文件 8、下载 12、书籍 4 都没改。

夹具结果：

- 日记：`2024-01-12`、`2026-10-25-周记`、`10.25、先`、`2024-01-N`、`1.1、背景`（顿号，和「10.25、…」同一条规则）。
- 不是日记：`周报2026-10-01`、`1.1 背景`、`1.1 背景二`。
- `select_candidates`：同一目录 10 份 `周报2026-10-*.md` 全部留下；6 份带空格的章节名全部留下；7 份开头就是日期的文件（含上面四个正例）只留下 3 份。
- 知识库统计：12 份周报、12 份 `1.n 背景` 不进 `journals`；12 份 `2024-01-*` 记在 `daily`，篇数 12。

偏离点：无。顿号形式的 `1.1、背景` 仍算日记，清单写的是空格形式留在工作池，不是把顿号也放回去。

## C3 办公格式与敏感词

按核实范围实现。`.doc`、`.rtf`、`.pages`、`.key`、`.numbers` 在 `DOCUMENT_EXTENSIONS` 里，也在 `BODY_SKIPPED` 里（值分别是 `doc`、`rtf`、`pages`、`keynote`、`numbers`）。`name_has_sensitive_token` 去掉扩展名后，整段相等，或按空白、下划线切开的一段相等，才跳过。连字符不切开。配置键仍是 `skip_file_substrings`，值仍是 `wallet`、`crypto`、`seed`。`.env`、`id_rsa`、`.pem` 的旧规则还在。

夹具结果：

- `walk` 和采样都留下 `seed-round.docx`（摘录含「种子轮材料还在」）、`crypto-wallet.docx`、`cryptocurrency.txt`、`seeds.txt`、`seedling.txt`、`Keyboard.md`、`Keyboard/a.md`、`wallets/keep.md`、`wallet-backup/keep.md`。
- 跳过且正文不出现：`seed.txt`、`my_seed.txt`、`my seed.txt`、`crypto.txt`、目录 `wallet` 里的文件。没有 `wallet` 警告，`count_is_total` 仍是 true。
- 五份办公文件都在 `files` 里，`body_skipped` 为上面的值，`excerpt` 和 `heading` 为空，文件里的哨兵句子不在样本 JSON。计数的 `structure.extensions` 能看到这些扩展名。

偏离点：无。连字符目录 `wallet-backup` 不跳过，和 `seed-round.docx` 是同一条「连字符不切开」。

## C5 空 OneDrive 与缺失根

按核实范围实现。`WindowsAdapter.default_user_roots` 按名字排序看 `OneDrive*`，`Documents` 和 `Desktop` 分开判断，目录里至少有一个条目才采用，否则看下一个，最后回到 `~/Documents` 或 `~/Desktop`。下载固定是 `~/Downloads`。书籍是选中的桌面下面的 `书籍`。`scan_collect.collect` 对不存在的根追加 `missing_root:{path}` 后继续；已存在但列不出来的根仍抛 `RootUnreadable`，`main` 返回 1 且不写文件。

夹具结果：

- 四个根都不存在：不抛，四条 `missing_root:` 与路径一致，笔记数 0，`count_is_total` 仍为 true。
- 文档根里有一份 Markdown，书籍路径不存在：笔记数 1，警告只有书籍那条 `missing_root:`。
- 文档根 `chmod 000`：`collect` 抛 `RootUnreadable`，入口失败且没有输出文件。
- 空的 `OneDrive/Documents` 和 `OneDrive/Desktop` 让位给主目录下的同名目录。`OneDrive/Downloads` 里有文件也不改变下载根。
- `OneDrive/Documents` 放进文件后选它，此时桌面仍是本地桌面，书籍仍是本地桌面下的 `书籍`。删掉该文件后，空的 `OneDrive`、空的 `OneDrive - A` 都不压过有文件的 `OneDrive - Contoso/Documents`。
- 桌面同样：有文件的 `OneDrive/Desktop` 胜出，清空后再由 `OneDrive - Contoso/Desktop` 胜出。书籍跟着当时选中的桌面，不单独探测 OneDrive 根下的 `书籍`。下载路径始终不变。

偏离点：无。

## C8 密钥

按核实范围实现。比较前去掉 NUL。PEM 用 `BEGIN`、若干大写词、`PRIVATE KEY`，因此 EC、ENCRYPTED、PGP、OPENSSH、RSA 以及多空格都覆盖。另有 `PuTTY-User-Key-File`。口令覆盖引号可选的 `password` / `passwd` / `api_key` / `secret` 加 `:` 或 `=`，允许一段下划线前缀；中文是 `密码` 或 `口令` 后面紧跟 `:`、`=` 或全角冒号。没有编码探测。

夹具结果：

- 拒绝：`BEGIN EC PRIVATE KEY`、`BEGIN ENCRYPTED PRIVATE KEY`、`BEGIN PGP PRIVATE KEY BLOCK`、原有的 OPENSSH 与单空格 RSA、双空格或更多空格的 `BEGIN RSA PRIVATE KEY`、`PuTTY-User-Key-File-2`、`{"password": ...}`（有无空格、单引号）、`DB_PASSWORD=`、`export SECRET=`、`api_key:`、`password=`、`密码：`、`密码:`、`口令=`、`口令：`，以及 NUL 隔开的 EC 头。
- 不拒绝：单独的「密码」「口令」「password」、`密码是123456`、`The password is not assigned.`、没有等号的 `DB_PASSWORD`、普通「BEGIN 写到这里」。
- 采样层把上面每一类都丢进 `rejected_documents`，哨兵和头都不在样本 JSON。标签拆进多个 `w:t` 的 docx，抽出的文本被认成私钥，整份拒绝。只写了「密码」和未赋值 `password` 的笔记留在 `files` 里，摘录仍有这两个词。只含「密码」两个字的 `个人画像.md` 仍被深读。

偏离点：无。

## C9 报告打码

按核实范围实现。`render` 先复制证据，再把 `deep_reads[].text` 换成「仅判断 AI 可读，报告不展示」。`recent_files` 有 `path` 时只跟深读路径比；没有 `path` 才用文件名。对上的摘录改成「与深读为同一文件，正文不在报告中展示」，标题清空。证据对象本身不改。可见表格本来就只渲染文件名、位置、时间。

夹具结果：

- 同一临时库里的 `简历.md`（标题里有电话和哨兵，正文里有邮箱和自述句）同时进入深读和近期文件，两条 `path` 字符串相同。证据 JSON 仍有电话、邮箱和自述句，`deep_reads.text` 是全文。用仓库里的 `templates/final-report.html` 渲染无判断报告后，整页 HTML 没有电话、邮箱、标题哨兵和自述句；有占位句，也有「与深读为同一文件」；另一份 `普通笔记.md` 的对照句还在。渲染不改写已经落盘的证据。
- 合成证据：同一路径的摘录和标题被抹掉；没有 path、文件名相同的也被抹掉；路径不同但文件名相同的摘录还在。深读全文不回到 HTML。

偏离点：无。摘录字段留的是一句说明，不是原文。清单要求的是抹掉正文，不是删掉这个字段。

## 必须改

无。

## 测试缺口

这是行为 25 还没写，不是实现错误。下面这些输入和期望，现有回归没有锁住。

已经锁住、不必再写成缺陷的部分：行为 02 锁「目录 `wallet` 不计数、`Keyboard` 下的 Markdown 计数、`.env` / `id_rsa` 不计数」。行为 03 锁「根不可读则失败且不写输出」。行为 11 只锁采样层的 `BEGIN OPENSSH PRIVATE KEY`。行为 21 锁「一份 `个人画像.md` 被深读、一份 OPENSSH 的 `个人总结.md` 被拒绝」，但那个库没有第四份可回填的自述，也没有「关于我们」。行为 23 锁「`2024-01-*` 每目录最多 3 份、`方案.md` 留在工作池」，没有周报文件名，也没有 `1.1 背景`。行为 24 锁「空的 `OneDrive/Documents` 让位给 `~/Documents`、放进文件后选它、删掉后再由 `OneDrive - Contoso/Documents` 胜出」。全量测试只断言 `ev["version"] == "4.1.1"`。

行为 25 应覆盖：

1. 自述命中与拒绝标记。输入：一个 vault，含 `关于我们.md`、`如何写简历.md`、`简历模板.md`、`个人画像.md`、`简历.md`、`我的简历.md`，以及更新的 `简历.docx`、`简历.pdf`。期望：`deep_reads` 的文件名正好是那三份 Markdown，三份正文在；公司介绍、教程、模板、docx、pdf 的句子不在 JSON 里。
2. 全局最多 3 份。输入：四个带标记的库，每个库两份能命中的自述（共 8 份）。期望：`knowledge_bases` 仍是 3（发现上限不放宽）；`deep_reads` 长度是 3，不是 6，也不是 8。
3. 私钥不回填。输入：一个库，修改时间从新到旧为含 `BEGIN EC PRIVATE KEY` 的 `个人总结.md`、`个人画像.md`、`我的简历.md`、同样能命中的 `简历.md`；另有更新的 `关于我们.md`。期望：`deep_reads` 只有 `个人画像.md` 和 `我的简历.md`；`简历.md` 不出现；`rejected_deep_reads` 有该私钥文件且原因为 `private_key`；密钥句子不在 JSON 里。
4. 日记边界。输入：`is_dated_note_name` 或 `select_candidates`。`2024-01-12`、`2026-10-25-周记`、`10.25、先`、`2024-01-N` 是日记。同一目录 10 份 `周报2026-10-*.md` 全部入选。同一目录 6 份带空格的 `1.1 背景` 一类文件名全部入选。同一目录 7 份开头就是日期的文件只入选 3 份。知识库里 12 份周报和 12 份 `1.n 背景` 不产生 `journals`，12 份 `2024-01-*` 产生，目录为 `daily`、篇数 12。
5. 整词与办公文件名。输入：扫描根含有效的 `seed-round.docx`（正文「种子轮材料还在」）、`crypto-wallet.docx`、`Keyboard.md`、`Keyboard/a.md`、`cryptocurrency.txt`、`seeds.txt`、`wallets/keep.md`、`seed.txt`、`my_seed.txt`、`my seed.txt`、`crypto.txt`、`wallet/hidden.md`，以及各带哨兵的 `周报.pages`、`方案.doc`、`笔记.rtf`、`演示.key`、`表格.numbers`。期望：前一组被计数且能进样本，`seed-round.docx` 的摘录含那句正文；后一组敏感名不在 `walk` 结果里，哨兵不在样本 JSON。五份办公文件在 `files` 中，`body_skipped` 依次为 `pages`、`doc`、`rtf`、`keynote`、`numbers`，`excerpt` 和 `heading` 为空。`config.json` 的键名仍是 `skip_file_substrings`。
6. 缺失根。输入：四个不存在的路径交给 `collect`。期望：不抛，`scan_warnings` 有四条 `missing_root:` 且路径一致，`count_is_total` 为 true。再测：文档根有一份 Markdown，书籍路径不存在。期望：成功，笔记数为 1，警告只有书籍那条。不可读根继续交给行为 03，不必在 25 里重复成新失败模式。
7. OneDrive 的其余根。行为 24 已锁文档根。还要锁：空的 `OneDrive/Desktop` 让位给 `~/Desktop`，且与文档根的选择互不影响；`OneDrive/Downloads` 里有文件时下载根仍是 `~/Downloads`；书籍始终是当前桌面下的 `书籍`。桌面在「有文件的 OneDrive 胜出、清空后再由 OneDrive - Contoso 胜出」上与文档根同一规则。
8. 新增密钥样例。输入：采样根里各一份 `BEGIN EC PRIVATE KEY`、`BEGIN ENCRYPTED PRIVATE KEY`、`BEGIN PGP PRIVATE KEY BLOCK`、`PuTTY-User-Key-File`、`{"password": ...}`、`DB_PASSWORD=`、`密码：`、`口令=`、NUL 隔开的 EC 头、双空格 `BEGIN RSA PRIVATE KEY`，以及把 `BEGIN` / `RSA` / `PRIVATE` / `KEY` 拆进多个 `w:t` 的 docx；每份带不会出现在路径里的哨兵。另有一份只写「密码」和未赋值 `password` 的笔记，一份只写「密码」的 `个人画像.md`。期望：前一组都在 `rejected_documents`（或深读拒绝列表），哨兵和头不在输出 JSON；普通笔记留在 `files`，摘录仍含这两个词；`个人画像.md` 仍被深读。
9. 报告打码。输入：vault 里的 `简历.md`，标题含电话，正文含邮箱；同目录一份不含这些字的 `普通笔记.md`。走知识库发现、采样、`build_evidence`，再用 `templates/final-report.html` 调用 `render`。期望：近期文件和深读的 `path` 相同；证据 JSON 仍含电话、邮箱和深读全文；HTML 整页不含电话和邮箱，深读 `text` 含「仅判断 AI 可读」，不含自述正文；普通笔记的摘录仍在 HTML 里。另用合成证据：同一路径的摘录和标题被抹掉；没有 `path` 时同名被抹掉；路径不同的同名文件摘录保留。

## 可留

不建议为这些扩大本轮改动。

- `find_self_docs` 的 docstring 仍写「按修改时间取最近几份」，实际返回该库全部命中，全局截断在 `collect`。参数 `config` 没有被这个函数使用。
- `SKILL.md` 同一条安全边界里，前面已经写了「非空才采用、空目录会跳过」，最后一句「探测只看目录在不在」比代码松。代码还会看目录里有没有至少一个条目。
- `SKILL.md` 没有点名 `.doc` / `.rtf` / `.pages` / `.key` / `.numbers` 只留文件名，也没有写 `wallet` / `crypto` / `seed` 已按整词匹配。`CHANGELOG.md` 的 4.1.1 节写了，和代码一致，现有句子没有写反。
