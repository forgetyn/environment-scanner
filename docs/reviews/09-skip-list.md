# 跳过名单审查（v4.2.0）

只看跳过名单：软件自己的目录、运行日志、安装包和压缩包不应计数、也不应读；用户自己的文档还要在。没有改业务代码、测试或配置。夹具在系统临时目录，调用的是 `walk`、`collect`、`collect_samples`。没有扫真实家目录，没有读 `~/.environment-scanner/reports`。下面的文件名都是夹具里的假名。

临时卷不分大小写，同一层不能同时放 `QQ` 和 `qq`。磁盘上的目录用了另一种大小写（`qq`、`wechat`、`wechat files`、`dingtalk`、`wxwork`、`tencent files`、`LOG`、`CRASH`、`crashreporter`、`crashpad`、`cache`、`TEMP`）。配置里的原样拼写（含 `Caches`、`WeChat Files`、`CrashReporter`、`Keychains`）另外对 `skip_dir` 各调用了一次。

打开轨迹包住了 `open`。应跳过的文件，以及 Keynote / PDF，都没有被打开。打开记录里没有夹具和仓库 `config.json` 以外的文件。

## 结论

没有必须改。

## 成立的问题

无。没有必须改，没有应该改，也没有需要单独记录的跳过名单缺陷。

## 查过但没有问题的点

### 1. 软件目录整段相等，忽略大小写

`skip_dir` 用目录名整段 `casefold`，不是前缀，也不是子串。`walk` 对四个根都不设深度上限。

跳过，且正文哨兵不在样本里：`qq`、`wechat`、`wechat files`、`xwechat_files`、`微信`、`dingtalk`、`wxwork`、`tencent files`，以及桌面的 `wechat`、下载里的 `qq`、20 层深处的 `qq`、主目录发现里的 `outside/qq`。`skip_dir` 对 `QQ`、`WeChat`、`WeChat Files`、`DingTalk`、`WXWork`、`Tencent Files` 也返回跳过。

仍被 `walk` 到，而且摘录里有正文：

- `QQ笔记/方案.md`（「用户方案正文标记」）
- `关于QQ.md`（「关于QQ正文标记」）
- `我的QQ/记录.md`、`微信备份/备忘.md`、`WeChat Files Backup/纪要.md`、`xwechat_files_extra/纪要.md`
- 下载里的 `QQ笔记/下载笔记.md`，主目录发现里的 `outside/QQ笔记/发现.md`

同名文件不是目录：`QQ.md`、`log.md` 都在，正文也在。

### 2. 日志、缓存、构建、点开头、应用包

这些目录里的 `隐藏.md` 不在 `walk` 里，也不在样本里：`LOG`、`logs`、`CRASH`、`crashes`、`crashreporter`、`crashpad`、`cache`、`tmp`、`TEMP`、`__MACOSX`、`venv`、`dist`、`build`、`target`、`vendor`，外加原来的 `node_modules`、`__pycache__`、`keychains`。`skip_dir("Caches")` 为真。桌面的 `LOG`、下载的 `log` 和 `__MACOSX`、书籍里的 `log` 同样不进入。

点开头目录不进入：`.venv`、`.hidden`、`.git`、`.ssh`、`.笔记`，以及桌面的 `.hidden`。以 `.app` 结尾的目录不进入：`Demo.app`、`Tool.APP`，桌面再放了一个 `Demo.app`。`my.app.files/还在.md` 不是应用包，正文还在。

近义目录没有被误伤：`my-logs`、`my_cache`、`build-notes` 的笔记都在摘录里。

普通文本不当日志：`debug.txt`、`notes.txt`、`notes.log.txt` 都进了摘录。这是指定行为，不是漏跳。

### 3. 后缀和私钥文件名不计数、不进样本、不读

文档根 `dropped/` 里放了这些后缀，每种一份，正文是哨兵：`.dmg` `.pkg` `.exe` `.msi` `.msix` `.apk` `.deb` `.rpm` `.appimage` `.zip` `.rar` `.7z` `.tar` `.gz` `.tgz` `.bz2` `.xz` `.iso` `.cab` `.log`，以及 `.ppk` `.pfx` `.cer` `.crt` `.p8` `.keystore` `.pem` `.p12` `.kdbx`。另有 `archive.tar.gz`（最后一段是 `.gz`）、`SETUP.EXE`、`DATA.ZIP`、`RUN.LOG`、`KEY.PEM`。

私钥文件名：`id_ecdsa`、`id_dsa`、`id_rsa`、`id_ed25519`、`Id_Ecdsa`、`ID_DSA`，主目录发现里再放了 `id_ecdsa`、`id_dsa`、`secret.pem`。

`walk` 结果正好是应保留的 75 个文件，上面这些一个都不在。样本 JSON 里没有它们的哨兵。打开轨迹里没有这些路径。下载体积与 `walk` 到的文件字节数一致（499 字节），40 个 `.zip`、10 个 `.exe`、`.dmg` 和深层 `.zip` 没有算进去。书籍计数是 2，不含 `资料.zip`。

`id_ecdsa.txt` 不是这份文件名名单，`skip_file` 不跳过它。夹具没有把它放进目录。精确文件名这一条按合同工作，不另算缺陷。

### 4. `.key` 仍是 Keynote

`.key` 不在私钥后缀里。`office/演示.key` 和 `office2/演示.KEY` 都在 `walk` 结果里。样本里两份都有，`body_skipped` 都是 `keynote`，`excerpt` 和 `heading` 为空，文件里的句子不在样本 JSON 里，也没有被打开。

### 5. 下载目录没有因为安装包被整段丢掉

下载根里同时有 40 个 zip、10 个 exe、一个 dmg、`cache/隐藏.pdf`、`qq/聊天.md`、`log/运行.md`、两处 `__MACOSX`。仍按下载名额出现在样本里的是：`报告.pdf`（`body_skipped` 为 `pdf`，摘录空）、`方案.docx`（摘录有「下载文档正文标记」）、`说明.md`、`nested/笔记.md`、`导出/讲义.pdf`、`QQ笔记/下载笔记.md`、8 层深处的 `深层下载.md`。这 7 份都在 12 的下载名额以内。`cache` 里的 pdf 不在。没有为这次审查改 120、日记 8、每目录 3、下载 12、书籍 4。

### 6. 四个根和主目录发现用同一份名单；配置没有把默认值吃死

`collect_samples` 只 `load_skip_rules()` 一次。采样阶段所有 `skip_dir` / `skip_file` 调用看到的是同一个 rules 对象（四个根的 `walk`，以及 `discover_files`）。`discover_files` 先走 `skip_dir`，文件再走 `consider_file` → `skip_file`。

主目录 `outside/` 不在四个根里：`项目说明.md`、`QQ笔记/发现.md`、`普通.txt` 进了摘录；`setup.exe`、`app.log`、`qq/聊天.md`、`cache/笔记.md`、两个密钥文件名和 `.pem` 不在样本里，也没打开。

`config.json` 里某个 `skip_*` 键非空时会整份替换默认集合，不是合并。用一份临时配置验证过：只写 `skip_dir_names: ["QQ"]` 之后，`log` 不在目录名单里；只写 `.dmg` 之后，`.zip` 不在后缀名单里；只写 `id_rsa` 之后，`id_ecdsa` 不在文件名名单里。没写的 `skip_file_substrings` 仍是默认的 `wallet` / `crypto` / `seed`。空列表在 `if filtering.get(...)` 下会被当成没写，不会替换。

当前仓库的三份名单和代码里的 `DEFAULT_SKIP_DIR_NAMES`、`DEFAULT_SKIP_FILE_NAMES`、`DEFAULT_SKIP_FILE_SUFFIXES` 集合相等（目录 33 个，后缀 29 个，差集都是空）。子串同样一致。因此加载真实 `config.json` 时，默认集合不是一套被配置换掉的死值。`quick` / `standard` / `deep` 三次 `collect` 各加载一份内容相同的 rules。

平台跳过没有套进四个扫描根。扫描根里的 `Library/用户库.md`、`Movies/观影笔记.md`、`AppData/四根笔记.md` 都在摘录里。主目录顶层的 `Library`、`Movies` 不进样本。强制 Windows 适配器再跑一次 `collect_samples`：扫描根里的 AppData 笔记仍在，主目录的 `AppData/主目录笔记.md` 不在，哨兵也不在。macOS 适配器的主目录发现没有 AppData 这一项，所以同一次 darwin 采样能看到那份主目录笔记。这是两份名单的边界，不是扫描根漏看。

`skip_system_files`、`skip_app_data`、`skip_cache_logs`、`skip_sensitive_dirs` 仍然没有读者。生效的是上面三份名单（外加代码里的点开头和 `.app` 判断）。当前名单已经盖住缓存、日志和 `Keychains`，布尔值不会把软件目录算进用户行为，这次不单列。

### 7. `count_is_total` 和整词

`quick`、`standard`、`deep` 的 `files` 和 `storage_bytes` 完全一样，`count_is_total` 都是 true。文档根 markdown 计数 54，其中一份改到 400 天前：`recent_notes_7d` 是 53，总量仍含它，近期样本不含它，正文也不在样本里。三种模式都没有按 quick 的「不读正文」去截断计数。`scan_warnings` 为空。`scan_scope.excluded` 含 `installers`、`archives`、`logs`、`cache`、`app_data_dirs`。

整词仍按空格或下划线切开，连字符不切开。在样本摘录里：`seed-round.docx`（「种子轮正文标记」）、`seed-round/计划.md`、`crypto-wallet.docx`、`my-seed.txt`、`Keyboard.md`、`Keyboard/键位.md`、`cryptocurrency.txt`、`seeds.txt`、`wallets/keep.md`、`wallet-backup/keep.md`、`seedling.md`。

不在 `walk`、哨兵不在样本里：`seed.txt`、`Seed.txt`、`my_seed.txt`、`my seed.txt`、`crypto.txt`、`WALLET.md`、`seed_round.docx`，以及目录 `wallet`、`crypto`、`my_seed`、`my seed`。没有因为这些名字写 `scan_warnings`。

### 8. `SKILL.md` 没有把计数说反

安全边界那一条写的是：安装包、压缩包、运行日志、软件数据目录「说明不了用户在做什么，所以不进入计数，也不读正文」；`QQ笔记` 这种用户目录不在名单里；`.key` 是 Keynote，只留文件名；下载目录里的 pdf、docx、md 仍按下载名额采样；`count_is_total` 为 true 表示计数不按模式截断，跳过名单仍然生效；计数是「用来判断用户在做什么的文件」。没有「安装包也计入」或「计数包括所有文件」这类反话。

它没有把每个后缀和「忽略大小写」逐项写全，用了「等」。方向和代码一致，不算说反。

### 另外核对过、不当作缺陷的行为

- 不打开主目录的 `Library`。没有按已安装软件名去扫。
- 不解压 zip。`.tar.gz` 只因最后后缀 `.gz` 被跳过，没有读包里的内容。
- 没有做 GBK 探测，这次夹具全是 UTF-8。
- 四个根的主 `walk`（计数体积、笔记数、书籍数、采样）没有深度上限：文档根 20 层的 `深层笔记.md`，以及桌面、下载、书籍各 8 层的笔记，都在样本摘录里。`files.desktop_files` 单独用了 `max_depth=2`，夹具里是 1，无上限的桌面 `walk` 是 2。深层桌面笔记仍在体积和样本里。这不是跳过名单，不把它算成缺陷。
- 点开头目录、以及正好叫 `log` / `build` / `tmp` / `cache` 的用户目录，会被整段跳过。这是本轮要的规则。名字不完全相同的目录已经留在上面的夹具里。
