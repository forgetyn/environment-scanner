# 安全边界审查

对照 `SKILL.md` 安全边界、`README.md` 隐私声明与采集/渲染实现。默认 `deep`。环境变量改扫描根不算漏洞。下面只记声明挡不住、内容或路径仍会落盘的情况。

### S1 私钥块只认三种 PEM 头，其余密钥材料进入摘录
- 严重度：blocker
- 位置：`scripts/lib/common.py` `SECRET_PATTERNS`（约第 8–11 行）；`scripts/lib/sample_content.py` `build_record`（约第 312–321 行）、`office_xml_text`（约第 234–238 行）；`scripts/lib/kb_discover.py` `deep_read`（约第 245–255 行）
- 目标如何失败：`SKILL.md` 写的是发现「私钥块」就整份拒绝、禁止引用。正则只匹配 `BEGIN PRIVATE KEY`、`BEGIN RSA PRIVATE KEY`、`BEGIN OPENSSH PRIVATE KEY`，且区分大小写、要求头内部只有单个空格。`BEGIN EC PRIVATE KEY`、`BEGIN DSA PRIVATE KEY`、`BEGIN ENCRYPTED PRIVATE KEY`、`BEGIN PGP PRIVATE KEY BLOCK`、PuTTY 的 `PuTTY-User-Key-File-` 都不会拒绝。docx/pptx 抽文本时把标签换成空格，同一段里被拆开的 RSA/OPENSSH 头会变成双空格，连已声明要认的头也会漏。文件名规则只精确挡 `.env`、`credentials.json`、`id_rsa`、`id_ed25519` 和后缀 `.pem` / `.p12` / `.kdbx`，挡不住 `id_ecdsa.txt`、`id_rsa.md` 这类改后缀副本。漏网正文写入 `recent_files.excerpt`（默认每份最多 4000 字），并进入样本 JSON、证据 JSON，以及证据报告和最终报告折叠区里的整包 JSON。自述文件则把最多 500 行写入 `deep_reads.text`（证据 JSON；HTML 会换掉这个字段，见 S3）。
- 证据：`BEGIN (?:OPENSSH |RSA )?PRIVATE KEY`；`build_record` 在 `secret_reason` 未命中后执行 `record["excerpt"] = excerpt`；`office_xml_text` 有 `re.sub(r"<[^>]+>", " ", raw)`。
- 如何确认：用临时夹具放一份 `.md` 和一份 `.docx`，正文含未覆盖的 PEM 头，或把已覆盖的头拆进两个相邻的 Office 文本节点。断言该文件不在 `files` / `deep_reads`，而在对应的 `rejected_*`；渲染后的两份 HTML 和证据 JSON 都不含该头之后的密钥材料。再断言精确文件名 `id_rsa` 与后缀 `.pem` 仍然不会出现在 `excerpt`。
- 不成立的可能：头完整落在同一次解码后的连续文本里，且就是上述三种写法时，整份会被拒绝，摘录不会留下。规范 PEM 多数是大写单空格，小写头并不常见。

### S2 口令赋值漏掉引号、前缀和中文键名
- 严重度：blocker
- 位置：`scripts/lib/common.py` `secret_reason`（约第 10、28–32 行）；消费点同 S1 的 `build_record` 与 `deep_read`
- 目标如何失败：声明是发现「口令赋值」就整份丢弃。正则只认单词边界后的 `password` / `passwd` / `api_key` / `secret`，再跟 ASCII 的 `:` 或 `=`。因此下面这些赋值不会拒绝，正文照样进摘录和证据，并出现在两份 HTML 的原始 JSON 里：`"password": "..."`、`'api_key': ...`、`DB_PASSWORD=`、`AWS_SECRET_ACCESS_KEY=`、`secret_key=`、`my_api_key=`、`api-key:`、`password：`（全角冒号）、`密码:`、`密码：`、`口令=`、`邮箱密码:`。文件名子串 `wallet` / `crypto` / `seed` 只作用于文件名和目录名，不作用于正文，笔记里的助记词同样不会被拒绝。产品面向中文笔记和简历，深读词典又专门读「简历 / 个人总结」，这种漏匹配会把口令写进 `deep_reads.text` 和可能同时存在的 `excerpt`。
- 证据：`(?i)\b(?:password|passwd|api_key|secret)\s*[:=]\s*\S+`。`_password`、键名后的引号、全角冒号都不满足这个形状。
- 如何确认：夹具 `.md` / `.txt` 各一行覆盖 JSON 引号、下划线前缀、全角冒号、中文「密码/口令」。断言 `rejected_documents` 或 `rejected_deep_reads` 收到该路径，且证据 JSON 与渲染 HTML 中不存在赋值右侧的口令。对照断言裸的 `password=` 与 `SECRET=` 仍然被拒绝。
- 不成立的可能：`password=...`、`api_key: ...`、`export SECRET=...` 会整份拒绝。精确名为 `.env` 或 `credentials.json` 的文件在读正文前就被 `skip_file` 丢掉。CSV 只把第一行送去判定，更下面的单元格不会进 `excerpt`（也不会因此被拒绝）。

### S3 深读正文仍经摘录进入两份报告
- 严重度：blocker
- 位置：`scripts/lib/judgment.py` `render`（约第 649–653、686 行）与 `file_table`（约第 534–545 行）；`scripts/lib/evidence_pack.py` `build_evidence`（约第 142、153 行）；`templates/final-report.html` 约第 309–311 行；声明见 `README.md` 约第 91 行、`CHANGELOG.md` 4.0.0「报告隐私加固」
- 目标如何失败：声明是自述正文只给判断 AI，不进报告原始 JSON 折叠区，且简历里的手机号和邮箱不应出现在报告任何位置。渲染器确实会把 `deep_reads[].text` 换成占位句，可见表格也只渲染文件名、位置、时间。但采样和深读是两条管道，中间没有按路径或自述词典去重。默认 `deep` 会走四根目录的全层 `walk`，vault 又常在 `Documents` 下。近 90 天、名字命中「简历 / 个人总结」等的 `.md` / `.txt` 会同时成为 `deep_reads` 和 `recent_files`。摘录保留正文里非噪声行的前 4000 字，`evidence_pack` 原样放进 `recent_files`，两份 HTML（证据报告与最终报告）的 `{{RAW_JSON}}` 都不删 `excerpt`。联系方式写在简历开头时，折叠区能直接看到。证据 JSON 和 `environment-scanner-kb-*.json` 另外保留深读全文，这一点与「给判断 AI」一致，不是这条的主要失败点。
- 证据：`item["text"] = f"（{item.get('line_count', 0)} 行正文，仅判断 AI 可读，报告不展示）"` 只改 `deep_reads`；`recent_files` 仍带 `excerpt`；模板 `<pre>{{RAW_JSON}}</pre>`。
- 如何确认：夹具 vault 内放一份 90 天内改过的 `简历.md`，正文前部是普通句子加电话和邮箱，不要用表格行。跑默认深度后断言：HTML 里 `deep_reads` 的 `text` 已是占位句，且同一 HTML 和证据 JSON 的 `recent_files` 也不含这些句子、电话和邮箱。现有测试只断言占位句或深读字段存在，没有断言「报告任何位置」。
- 不成立的可能：文件超过 90 天、没挤进 120 个名额，或联系方式只写在 Markdown 表格行（`is_noise` 不把表格行放进摘录）时，折叠区可以没有这段正文。这是采样碰巧没选中，不是按深读路径排除。

### S4 跳过只看单个目录名，大小写、扫描根内的平台目录、Windows junction 可以绕过
- 严重度：degrade
- 位置：`scripts/lib/scan_collect.py` `skip_dir` / `walk`（约第 68–74、152–163 行）；`scripts/lib/sample_content.py` `discover_files`（约第 147–148、186–191 行）；`scripts/lib/kb_discover.py` `skip_dir_entry`（约第 86–89、104 行）；`scripts/lib/platform_win.py` `home_discover_skip_dirs`（约第 87–97 行）；`config.json` `features.smart_filtering`（约第 19–42 行）
- 目标如何失败：用户会以为 `.ssh`、Keychains、Library、AppData 整棵都不会被读。实际规则是：POSIX 符号链接在 `is_symlink()` 处直接跳过，嵌套的 `.ssh` 也因为「名字以点开头」被跳过，这两条没有绕过。真正漏的是：`skip_dir` 对 `Keychains` 是大小写精确匹配，`keychains` / `KEYCHAINS` 会进入主目录发现和四根 `walk`；知识库发现把平台跳过名单做成 `name in set or name.lower() in set`，集合里是 `Library` 不是 `library`，与采样发现的 `name.lower()` 不一致；四根 `walk` 根本不套用 Library / AppData 这套平台名单，扫描根里面一个叫 `Library` 或 `AppData` 的真实目录会被计数并采样。Windows 上 junction 往往不是 `is_symlink()`，适配器注释已承认 pathlib 会穿透，但只在主目录发现时按一份固定名字跳过，扫描根内部未列名的 junction 会被走进去读文档。硬链接不是符号链接，会按普通文件读正文。另外 `skip_sensitive_dirs` 和 `skip_system_files` / `skip_app_data` / `skip_cache_logs` 没有任何读者，改这些字段不会改变行为。
- 证据：`if name in rules["dir_names"]` 未做 casefold；`return name in platform_skip or name.lower() in platform_skip`；`walk` 只调用 `skip_dir`；发现循环只判断 `entry.is_symlink()`。
- 如何确认：在临时扫描根里各放一个大小写不同的 `keychains` 目录、一个名为 `Library` 的子目录，以及一个指向夹具外文档目录的 junction（仅 Windows 夹具）。断言这些目录下的 `.md` 不会出现在 `files` 或 `deep_reads`。再断言指向夹具外的符号链接目录不会被读取。不要把断言写成对真实主目录 `~/Library` 或 `~/.ssh` 的访问。
- 不成立的可能：默认 macOS 上 `iterdir` 给出的就是 `Library` 和以点开头的 `.ssh` / `.gnupg` / `.aws` / `.kube`，采样发现又把平台目录名做了小写比较，因此默认路径不会读进系统钥匙串或 `~/.ssh`。要读到内容，需要扫描根里出现大小写变体、同名普通目录、硬链接或未列入名单的 junction。

### S5 UTF-16 正文里的私钥头和口令赋值匹配不到，字符仍留下
- 严重度：degrade
- 位置：`scripts/lib/sample_content.py` `read_text_limited`（约第 210–221 行）；`scripts/lib/kb_discover.py` `deep_read`（约第 247–252 行）；判定仍是 `common.secret_reason`
- 目标如何失败：采样按 UTF-8 打开，`errors="ignore"` 只丢非法字节，不丢 NUL。UTF-16 里的 `BEGIN RSA PRIVATE KEY` 或 `password=` 每个 ASCII 字符之间都有 NUL，正则要求连续字母，于是不会拒绝。这些字符仍进入 `excerpt` 或 `deep_reads.text`，再进入证据 JSON；摘录还会进 HTML 折叠区。NUL 在页面里常常不占宽度，展开原始 JSON 时口令仍然可读。`SKILL.md` 只承认 GBK 会缺字，没有承认这种编码会让拒绝失效。GBK 文件里的纯 ASCII `password=` 一般仍能命中，这条不是 GBK 问题。
- 证据：`path.open("r", encoding="utf-8", errors="ignore")` 与只匹配连续 `BEGIN` / `password` 的正则。
- 如何确认：夹具用 UTF-16 LE 保存一份含已覆盖 PEM 头或 `password=` 的 `.txt`。断言该文件被拒绝，且证据 JSON 与 HTML 中不出现赋值右侧或 PEM 体。对照 UTF-8 的同一内容应已被拒绝。
- 不成立的可能：现代记事本默认 UTF-8；Office Open XML 本身是 UTF-8，不走这条解码。只有采样扩展名上的 UTF-16 文本会触发。

### S6 被拒绝文件的绝对路径仍写进证据和报告，判断正文也不查密钥
- 严重度：latent
- 位置：`scripts/lib/sample_content.py` `build_record` 拒绝分支（约第 315–317 行）；`scripts/lib/kb_discover.py` `deep_read`（约第 252–254 行）；`scripts/lib/evidence_pack.py`（约第 143、154 行）；`scripts/lib/judgment.py` `validate` 的 `known_files`（约第 175–177 行）与 `render` 的整包 JSON（约第 650–653 行）
- 目标如何失败：声明是拒绝后禁止引用。实现只是不把该文件放进 `recent_files` / `deep_reads`，校验只要求建议里的文件名落在这两份名单里，不扫描 `first_step` 或其他自由文本里有没有私钥或口令，也没有一份 rejected 路径拒绝表。同名的另一份普通文件会让这个文件名重新变成合法引用。与此同时，`rejected_documents` / `rejected_deep_reads` 的绝对路径会进入证据 JSON，并原样出现在两份 HTML 的折叠区。正文在 S1/S2 命中时不会留下，但密钥文件的位置会留下。
- 证据：拒绝记录是 `{"path": str(path), "reason": reason}`；`known_files` 只收集 `recent_files` 与 `deep_reads` 的 `name`。
- 如何确认：夹具中一份会被拒绝的笔记与一份同名的普通笔记同时存在。断言渲染 HTML 的折叠区不含被拒文件的绝对路径；判断文件的 `first_step` 若含 PEM 头或 `password=` 形式的赋值，校验失败。路径断言不要依赖把真实用户目录写进仓库。
- 不成立的可能：`rejected_*` 被设计成审计列表，`SKILL.md` 写了「记入 rejected_documents」。若「禁止引用」只约束建议里的文件名，路径留在折叠区是现有合同，不是误写入。合规的会话不会按技能说明去打开样本名单以外的路径。

扫描阶段没有发现主动出站，也没有发现改写扫描根里的用户文件。`run-scan.sh`、`run-scan.ps1`、`collect-data.sh` 只在输出目录 `mkdir` / `New-Item` 并让 Python 把 JSON 和 HTML 写到 `--output`；`open_report.py` 只对已落盘的 HTML 调用 `open` 或 `os.startfile`。注册表与 `sw_vers` 是只读。`shutil` 只用于 `disk_usage`。模板在浏览器打开时加载 Chart.js，这已在 `README.md` 说明；同一次打开还会请求 `fonts.googleapis.com` 与 `fonts.gstatic.com`，README 没有写，但这不是扫描阶段出站，不单列。

读过：`SKILL.md` 安全边界、`README.md` 隐私节、`config.json` 的 `smart_filtering` 与 `content_sample`、`scripts/lib/common.py`、`sample_content.py`、`kb_discover.py`、`scan_collect.py`、`evidence_pack.py`、`judgment.py`、`open_report.py`、`app_inventory.py`、`platform_mac.py`、`platform_win.py`、`templates/final-report.html`、`scripts/run-scan.sh`、`scripts/run-scan.ps1`、`scripts/collect-data.sh`、`scripts/generate-final-report.sh`。
