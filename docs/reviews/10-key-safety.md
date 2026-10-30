# 私钥文件与笔记密钥审查

审查对象是 v4.2.0 未提交改动里的这一条边界：私钥文件在打开前跳过；写进笔记正文的密钥和口令整份拒绝，不能进入样本摘录、深读正文或最终报告。`.key` 必须继续当作 Keynote。

夹具在 `mkdtemp` 临时目录，不在仓库里，也不是真实家目录。哨兵都是 `ZZK-` 假字符串，没有生成密钥材料。流水线实际调用了 `scan_collect.walk`、`sample_content.collect_samples`（`deep`，并把 `id_rsa` 和 `演示.key` 放进显式路径）、`kb_discover.collect`（其中的 `deep_read`），以及 `judgment.render`（证据报告，和一份不含哨兵的判断；模板是 `templates/final-report.html`）。打开追踪先确认能抓住一次故意的 `read_text`，再包住 `Path.open`、`io.open` 和 `builtins.open`。没有扫到真实家目录，没有读 `~/.environment-scanner/reports`。

## 结论

没有必须改。

精确文件名 `id_ecdsa`、`id_dsa`、`id_rsa`、`id_ed25519`，以及后缀 `.pem`、`.ppk`、`.pfx`、`.p12`、`.kdbx`、`.cer`、`.crt`、`.p8`、`.keystore`，大小写变体（`ID_ECDSA`、`Id_Ed25519`、`Key.PPK`、`Cert.PEM`、`G.KEYSTORE` 等）都在读内容之前被丢掉。`walk` 结果里没有这些文件名，采样和深读都没有 `open` 它们。笔记里的 `BEGIN EC PRIVATE KEY`、`BEGIN ENCRYPTED PRIVATE KEY`、`BEGIN PGP PRIVATE KEY BLOCK`、`PuTTY-User-Key-File`、带引号的 `password`、中文「密码：」仍整份拒绝，哨兵不进摘录，也不进两份 HTML。`.key` 仍被计入并采样，`body_skipped` 是 `keynote`，正文没有读。同一路径的深读正文留在证据 JSON，报告 HTML 里没有。旁边有 `.ppk` 时，普通笔记照样能读。

下面只有一条记录，不是必须改，也不是应该改。

## 成立的问题

### 记录：整个文件名就是 `.pem` 时，不会按后缀跳过

- 严重度：记录
- 位置：`scripts/lib/scan_collect.py` 的 `skip_file`。后缀用的是 `Path(name).suffix`。`PurePath(".pem").suffix` 是空字符串，因为这是没有主文件名的点文件，不是 `a.pem` 那种后缀。
- 夹具和实际结果：`docs/dotfile/.pem`，正文只有 `ZZK-DOTFILE-PEM`。`skip_file(".pem")` 为假，`skip_file("a.pem")` 为真。`walk` 能看见这个文件名，扩展名计数里多了 1 个「无扩展名」。采样、深读、渲染都没有 `open` 它。
- 泄露或误伤：没有读到内容。哨兵不在 `walk` 的路径字符串、样本 JSON、拒绝记录、深读 JSON、证据 JSON 或两份 HTML 里。没有误伤别的文件。

名单里的 `.pem` 后缀（`a.pem`、`Cert.PEM`、`Server.Pem`、`demo.key.pem`、库里的 `简历.pem`）都在打开前丢掉了。这条只影响「文件名恰好是 `.pem`」这一种点文件，而且报告看不到正文。不要为了它把 `.key` 加进私钥后缀。

## 查过但没有问题的点

### 1. 这些私钥文件不被打开，大小写也跳过

`config.json` 的 `skip_file_names` 有 `id_rsa`、`id_ed25519`、`id_ecdsa`、`id_dsa`。`skip_file_suffixes` 有 `.pem`、`.ppk`、`.pfx`、`.p12`、`.kdbx`、`.cer`、`.crt`、`.p8`、`.keystore`。`skip_file` 对文件名做 `lower()`，对后缀做 `Path(name).suffix.lower()`，再和已经小写的后缀集合比。不是只比原始大小写。

夹具把小写、大写、混写分开放，避免大小写不敏感的磁盘把 `id_ecdsa` 和 `ID_ECDSA` 收成同一个文件。内容只有哨兵，没有私钥头，这样即使被当成普通文本读进来，`secret_reason` 也救不了。实测 `skip_file` 对下列名字全为真，`walk` 里没有它们，三次业务调用（`walk`、`collect_samples`、`kb_discover.collect`）的打开记录里也没有它们：

- 无后缀：`id_ecdsa`、`id_dsa`、`id_rsa`、`id_ed25519`，以及 `ID_ECDSA`、`ID_DSA`、`ID_RSA`、`ID_ED25519`、`Id_Ed25519`
- 后缀：`a.pem`、`a.ppk`、`a.pfx`、`a.p12`、`a.kdbx`、`a.cer`、`a.crt`、`a.p8`、`a.keystore`、`prod.backup.keystore`、`demo.key.pem`
- 大写后缀：`Key.PPK`、`Cert.PEM`、`My.PpK`、`Server.Pem`、`A.PFX`、`B.P12`、`C.KDBX`、`D.CER`、`E.CRT`、`F.P8`、`G.KEYSTORE`、`My.Certificate.CER`

同一目录里的 `login.ppk`、`id_rsa`，库里的 `id_rsa`、`简历.pem`、`个人总结.ppk`，也都不在打开记录里。显式路径再传一次 `id_rsa`：不进 `files`，不进 `rejected_documents`，没有 `open`。

`my-id_rsa.md` 和 `ID_ECDSA-note.md` 不会被精确文件名误伤，正文哨兵还在。打开前跳过是整段文件名相等，或最后一段后缀命中，不是前缀。

### 2. 笔记里的密钥和口令仍整份拒绝

`secret_reason` 先去掉 NUL，再认私钥头、`PuTTY-User-Key-File`、口令赋值和中文「密码 / 口令」。命中后 `build_record` 和 `deep_read` 都丢掉整份，拒绝记录只有 `path` 和 `reason`，没有正文。

单独成篇，避免前面的头把后面的规则罩住。哨兵都写在头或赋值的后面，用来抓「只删匹配行、剩下的还进摘录」：

| 夹具 | 实际原因 |
| --- | --- |
| `-----BEGIN EC PRIVATE KEY-----` | `private_key` |
| `-----BEGIN ENCRYPTED PRIVATE KEY-----` | `private_key` |
| `-----BEGIN PGP PRIVATE KEY BLOCK-----` | `private_key` |
| `PuTTY-User-Key-File-2` | `private_key` |
| `{"password": "..."}`、`{ "password" : "..." }`、`{'password': '...'}` | `credential_assignment` |
| `密码：`（全角冒号） | `credential_assignment` |

另外一篇 `combined.md` 把这六类写在一起，拒绝原因是 `private_key`，合并哨兵不在样本 JSON 里。库里的 `个人总结.md` 同样六类都有，采样和深读都拒绝，`deep_reads` 里没有它，`rejected_deep_reads` 只有路径和 `private_key`。

这些哨兵，以及 `BEGIN EC PRIVATE KEY`、`BEGIN ENCRYPTED PRIVATE KEY`、`BEGIN PGP PRIVATE KEY BLOCK`、`PuTTY-User-Key-File` 这些头本身，都不在 `walk` 路径、样本 JSON、深读 JSON、证据 JSON、证据报告 HTML、带判断的 HTML 里。标题行只有 `BEGIN EC PRIVATE KEY` 或 `密码：` 的笔记也是整份拒绝，标题下面的普通句子没有留下。

### 3. `.key` 仍是 Keynote，不能改成私钥后缀

`skip_file_suffixes` 里没有 `.key`。`演示.key`、`方案.KEY`、`demo.pem.key` 都在 `walk` 里，扩展名计数是 3 个 `.key`。三份都进入样本：`body_skipped` 为 `keynote`，`excerpt` 和 `heading` 为空。打开记录里没有它们，幻灯片哨兵不在样本 JSON 或 HTML。

`demo.pem.key` 的最后后缀是 `.key`，所以按 Keynote 只留文件名。`demo.key.pem` 的最后后缀是 `.pem`，在打开前丢掉。这是对的。不要把 `.key` 收进私钥后缀。

### 4. 同路径深读正文不进报告，证据 JSON 仍留着

库内 `简历.md` 没有密钥。正文是标题哨兵、电话哨兵、邮箱哨兵和 `ZZK-DEEP-KEEP`。它同时出现在 `deep_reads` 和 `recent_files`，两条 `path` 相同。证据 JSON 里这四段都在，`deep_reads.text` 是全文。`render` 之后证据对象没有被改写。

两份 HTML 都没有这四段。有「仅判断 AI 可读，报告不展示」和「与深读为同一文件，正文不在报告中展示」。同一次 HTML 里还有旁边笔记、子目录笔记、库内普通笔记、密钥目录里的干净笔记，以及只写了「密码」和 `password is not assigned` 的那篇。4.1.1 的打码没有被这轮改坏。

### 5. 有私钥文件的目录不会被整目录丢掉

`with-note/` 里同时有 `login.ppk`、`id_rsa`、`旁边笔记.md`，下面还有 `sub/还有一篇.md`。两个私钥文件不在 `walk` 里，两篇笔记都在，摘录进了 HTML。`secrets/` 里全是会被拒绝的笔记，同目录的 `干净.md` 仍然有摘录。库里的 `个人总结.md` 被拒绝时，`普通笔记.md` 还在。跳过和拒绝都是按文件，不是按目录。

### 6. 私钥文件是打开前跳过，不是读完再丢

`walk` 先 `is_file`（这是 `stat`）再 `skip_file`。命中的文件不会放进结果。这一阶段的文件打开数是 0。对 `id_ecdsa` 单独调用 `is_file`，追踪器没有记到 `open`；同一次追踪能抓住普通文件的 `read_text`，所以不是追踪器失灵。

采样的 `consider_file` 在 `stat` 和 `extract_body` 之前就因 `skip_file` 返回。深读的 `find_self_docs` 也是先 `skip_file`，`deep_read` 只打开已经选中的自述。`.key` 在 `build_record` 里因 `BODY_SKIPPED` 直接返回，不会进 `extract_body`。

笔记里的密钥是另一条路：`.md` / `.txt` / `.docx` 会先读，再整份拒绝。这是这条边界要求的行为，不是「私钥文件读完再丢」。改过后缀、但仍带标准头的 `id_rsa.md` 和 `id_ecdsa.txt` 会读，然后整份拒绝，哨兵不进摘录或 HTML。它们不在「精确文件名或后缀、打开前跳过」的名单里。

### 已有的 `secret_reason` 没有变窄

走完采样、哨兵没有出现的还有：`BEGIN OPENSSH PRIVATE KEY`、双空格的 `BEGIN  RSA PRIVATE KEY`、NUL 隔开的 EC 头、UTF-16 的 EC 头、docx 里拆进多个 `w:t` 的 `BEGIN` / `EC` / `PRIVATE` / `KEY`、`DB_PASSWORD=`、`export SECRET=`、`api_key:`、`Password=`、`passwd=`、`口令=`。

只对 `secret_reason` 对过、原因仍然对的还有：单空格的 `BEGIN RSA PRIVATE KEY`、`BEGIN PRIVATE KEY`、`BEGIN DSA PRIVATE KEY`、`password=`、全角的「口令：」、冒号前带空格的「密码 ：」。这一组和上面那组都没有和 4.1.1 的期望原因不一致。

只写「密码」、未赋值的 `password is not assigned`、未赋值的 `api_key`，仍然留在摘录里，没有误伤。

下面这些现在也不拒绝，但 4.1.1 的规则本来就不是这样，这轮也没有要求扩大，不算变窄：小写的 `begin ec private key`、小写的 `putty-user-key-file`、英文 `password` 后面的全角冒号、`BEGIN PUBLIC KEY`。云厂商 token 格式没有当成缺陷。
