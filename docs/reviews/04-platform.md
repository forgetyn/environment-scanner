# 平台与失败模式审查

对照 `SKILL.md` / `README.md` 的平台合同，以及 `scripts/run-scan.sh`、`scripts/run-scan.ps1`、适配器和最终报告的失败路径。未执行 `pwsh`。`.gitattributes` 在当前工作区是生效的：`*.sh` / `*.py` 为 LF（`run-scan.sh`、`generate-final-report.sh`、`collect-data.sh` 的字节里没有 CR），`run-scan.ps1` 为 UTF-8 BOM + CRLF。这不是下面任何一条的原因。

按 `SKILL.md` 第 123、146 行和 `README.md` 环境变量表，macOS 上 `ENV_SCANNER_APPLICATIONS` 用冒号、`ENV_SCANNER_INSIGHT_DOCS` 用分号，代码也是这样拆的。只按这个写法、且分隔符两侧没有空格时，不会把普通 macOS 路径切成盘符和剩余段。下面第 8 条是这条合同里仍然会丢路径的地方，不是「两套分隔符互相切错」。

### P1 注册表没有名字时，和「没有 winreg」是同一条警告，Program Files 缺失则不留警告
- 严重度：degrade
- 位置：`scripts/lib/platform_win.py` `_registry_names`（约第 14–49 行）、`WindowsAdapter.app_roots`（约第 59–64 行）、`collect_app_names`（约第 66–85 行）；`scripts/lib/app_inventory.py` `collect`（约第 83–111 行）；`scripts/lib/evidence_pack.py` `build_evidence`（约第 144–163 行）；`scripts/lib/judgment.py` `kpi_html`（约第 414 行）、`app_chips`（约第 554–555 行）
- 目标如何失败：`SKILL.md` 把 `windows_registry_unavailable` 定义成「没有 winreg，不中断，仍读 Program Files 目录名」。`import winreg` 成功之后，三个卸载键全部 `OpenKey` 失败会被 `continue` 掉，不另记警告；只要 `DisplayName` 一个都没收集到，仍然追加同一条 `windows_registry_unavailable`。`app_roots` 只保留 `Path.is_dir()` 为真的配置路径。系统不在 `C:`、目录不存在时，`C:\Program Files` 与 `C:\Program Files (x86)` 直接从 `sources` 消失，没有 `unreadable:`。目录能 `stat` 但不能 `iterdir` 时才会记下 `unreadable:`，名字列表仍为空。`app_inventory.py` 无论名单是否为空都写 JSON 并返回 0。证据里 `apps` 为 `[]`、`app_count` 为 0；`zero_signal` 只看「没有近期文件且没有应用名」，不看警告。证据报告和最终报告的 KPI 渲染「应用数量 0」，应用区渲染「没有收集到应用清单。」`scan_warnings` 不进这两个可见区块，只躺在原始 JSON 里。有文件、没有应用名时，判断仍可引用文件，但应用数已经是一次成功的 0。文件和名单都空时，`zero_signal` 为真，校验会拒绝任何建议，扫描失败被写成「没有可判断的证据」。
- 证据：`if not names: warnings.append("windows_registry_unavailable")` 在 `ImportError` 分支之外还有一次；`if Path(path).is_dir()` 过滤 `windows_program_dirs`；`return 0` 在写出名单之后；`app_chips` 在 `if not apps` 时返回「没有收集到应用清单。」
- 如何确认：在能导入 `winreg` 的解释器上，让三处 `OpenKey` 失败或卸载项都没有 `DisplayName`，并把 Program Files 指到不存在的盘符。断言进程退出码为 0、`app_count` 为 0，且警告能区分「模块不存在」和「键打不开 / 没有 DisplayName」。再断言 `is_dir()` 为假的根出现在 `sources` 或单独的警告里，而不是从证据里消失。可见 HTML 在这种警告存在时不应只显示应用数量 0。
- 不成立的可能：64 位 Windows 上卸载表通常有 `DisplayName`，Program Files 也能列出，这时名单不是空的，这条警告不会出现。`Path.is_dir()` 在当前 Python 文档里对权限错误是抛出而不是返回假；若 `stat` 本身抛 `PermissionError`，`app_roots` 没有接住，阶段 3 非零退出，不会写成一份 `app_count: 0` 的证据（阶段 1、2 的 JSON 会留下，证据文件还没写）。能列出的 Program Files 子目录无权限只跳过该子项，不会把整份名单清空。

### P2 文档根不存在，或几个 OneDrive 里字典序靠前的那个是空的，扫描仍成功
- 严重度：degrade
- 位置：`scripts/lib/platform_win.py` `default_user_roots`（约第 99–124 行）；`scripts/lib/scan_collect.py` `assert_root_readable`（约第 87–95 行）、`walk`（约第 140–143 行）、`main`（约第 313–321 行）；`scripts/lib/sample_content.py` `collect_samples`（约第 447–454 行）、`main`（约第 545–554 行）
- 目标如何失败：`SKILL.md` 只要求扫描根不可读时停止且不写输出。根不存在时 `assert_root_readable` 直接返回，`walk` 返回空列表，计数文件照写，进程返回 0。采样同样不把「根不存在」当成 `RootUnreadable`。Windows 适配器用 `sorted(home.glob("OneDrive*"))`，命中第一个含有 `Documents` 或 `Desktop` 的目录就返回。`OneDrive` 排在 `OneDrive - 公司名` 前面。个人 OneDrive 客户端只要建了一个空的 `Documents`，公司重定向里的文档不会进入计数和采样。桌面同理。下载目录不参与这次探测，仍是 `~/Downloads`。两条路都通过结尾的非空检查：文件是合法 JSON，内容是空的或是另一棵树。证据报告会写「没有读到近期文件。」需要时再叠上 P1，变成 `zero_signal`。
- 证据：`if not root.exists(): return`；`for base in candidates: ... if target.is_dir(): return target`；`sorted(home.glob("OneDrive*"))`。
- 如何确认：临时主目录里同时放空的 `OneDrive/Documents` 和有 `.md` 的 `OneDrive - Contoso/Documents`，强制 `ENV_SCANNER_PLATFORM=windows`，不要设置 `ENV_SCANNER_DOCUMENTS`。断言计数和 `recent_files` 来自公司目录，而不是空的个人目录。再断言四个根都不存在时进程非零且不写输出文件。不要用已经把文档重定向到唯一一个 `OneDrive/Documents` 的夹具来否定前一种情况。
- 不成立的可能：只有一个 `OneDrive*`，且它的 `Documents` 就是真正的文档根时，字典序没有第二种选择。根存在但不可读时，现有代码会抛 `RootUnreadable`，不写该阶段输出，这和声明一致。macOS 适配器不跑这段 glob，默认扫描仍是 `~/Documents` 等四个路径。

### P3 父进程留下的 ENV_SCANNER_PLATFORM 会换掉 macOS 适配器，证据里的平台字段仍写 darwin
- 严重度：latent
- 位置：`scripts/lib/platforms.py` `get_platform`（约第 58–72 行）；`scripts/run-scan.sh`（约第 52–75 行，未清理该变量）；`scripts/lib/scan_collect.py` `collect` 的 `platform` 字段（约第 268 行）与 `system_info`（约第 131–132 行）；`scripts/lib/app_inventory.py` `collect`（约第 80、106 行）；`scripts/lib/open_report.py` `main`（约第 31–35 行）；`scripts/generate-final-report.sh`（约第 35–38 行）
- 目标如何失败：选择器规定该变量优先于本机系统。`run-scan.sh` 不取消它，五个阶段的 Python 都继承父环境。在 macOS 上若值为 `windows`，应用清单走 Windows 适配器（本机没有 `winreg`，`C:\Program Files` 也不是目录，于是落到 P1 的空名单），主目录跳过名单和文档/桌面根改走 OneDrive 规则。证据里的 `scan.platform` 却是 `platform.system().lower()`，仍是 `darwin`，报告平台行不会显示走了 Windows 适配器。最终报告打开同样读这个变量：macOS 上会去调不存在的 `os.startfile`，`open_report.py` 返回 1，壳脚本只打印「没有自动打开」并以 0 结束。默认扫描的应用名单和文档根已经错了，退出码仍表示成功。
- 证据：`key = forced or system`；`"platform": platform.system().lower()`；`generate-final-report.sh` 用 `if ! open_report.py` 吃掉非零退出。行为测试只在 `tests/test-skill-behavior.sh` 第 9 行 `unset` 这个变量，产品入口没有对应动作。
- 如何确认：在 macOS 上 `export ENV_SCANNER_PLATFORM=windows` 后不带该变量的覆盖去跑 `run-scan.sh`，夹具主目录同时有普通 `Documents` 和 `OneDrive/Documents`。断言 `scan.platform` 与实际适配器一致，应用名单仍来自 `.app`，文档根仍是夹具 `Documents`，并且最终报告会调用 `open` 而不是在退出码 0 的情况下只留下打不开的提示。变量未设置时不应改变现有 darwin 路径。
- 不成立的可能：干净环境里这个变量不存在，`platform.system()` 为 `Darwin`，会进 `MacAdapter`。单次 `env VAR=... command` 不会写进父进程。打开失败不把已写好的 HTML 判失败，这是 `generate-final-report.sh` 第 35–38 行的既定行为；坏的是打开动作和采集适配器跟着泄漏的变量走，不是「打开失败却返回 0」本身。

### P4 同一次失败不会把半截样本并进证据；最新的截断证据文件会被下一步当成完整输入
- 严重度：latent
- 位置：`scripts/run-scan.sh`（约第 7、95–99 行）；`scripts/run-scan.ps1`（约第 14、57–62、162–166 行）；`scripts/lib/common.py` `write_json`（约第 45–47 行）；`scripts/lib/scan_collect.py`、`sample_content.py`、`app_inventory.py`、`kb_discover.py` 的 `write_text`；`scripts/lib/evidence_pack.py` `main`（约第 176–181 行）；`SKILL.md` 约第 20 行
- 目标如何失败：各阶段都是把完整 JSON 字符串一次 `write_text` 到最终文件名，没有临时文件再改名。`write_text` 以截断方式打开。进程在写入中途被杀掉时，目标路径上会留下非空但不是合法 JSON 的半截文件。`set -euo pipefail` 和 ps1 的 `Invoke-Py` 只在子进程非零时停止后续阶段，所以「采样抛错、文件还没写完」不会进入同一次的 `evidence_pack.py`。停在阶段 2 时，磁盘上有完整的计数文件，没有新的 `environment-scanner-evidence-*.json`。若死在阶段 5 的 `write_text` 中途，新的证据文件已经是目录里时间戳最新的那个。`SKILL.md` 要求只读最新的 `environment-scanner-evidence-*.json`，不看本次退出码，也不要求删掉失败产物。下一步会把截断 JSON 当成证据。成功路径的完整性检查只看文件非空（sh 的 `[ ! -s ]`，ps1 的 `Length -eq 0`），不解析 JSON。P1、P2 那种合法空壳能过这一关。知识库文件不在这份清单里；知识库阶段若写出空文件并返回 0，检查不会拦。
- 证据：`Path(path).write_text(...)`；结尾循环只测存在和非空；`SKILL.md`「只读输出目录里最新的 `environment-scanner-evidence-*.json`」。
- 如何确认：对 `evidence_pack.py` 的输出路径在 `write_text` 中途杀掉进程，断言该路径不是合法 JSON，且按技能说明选出的「最新证据」不会是这份文件，或者选出后校验会因解析失败而停止，而不是进入判断。再断言 P2 的合法空 JSON 不能只靠非空检查算通过。同一次运行里，让 `sample_content.py` 在写文件前返回 1，断言不会生成新的证据文件。
- 不成立的可能：`write_text` 正常返回时，内容是一次 `json.dumps` 的完整字符串，不是写到一半仍返回 0。`RootUnreadable` 发生在写文件之前，该阶段目标不会被写成空壳。时间戳到秒，同秒重入才会撞同一路径；这不是默认单次扫描的路径。

### P5 ps1 打印的 Win32 路径直接交给 bash 时，第二步可以在渲染前退出
- 严重度：degrade
- 位置：`scripts/run-scan.ps1`（约第 71–75、170–174 行）；`scripts/generate-final-report.sh`（约第 19–23、32–33 行）；`scripts/lib/open_report.py`（约第 23–38 行）
- 目标如何失败：ps1 用 `Join-Path` 写出 `C:\Users\...\.environment-scanner\reports\environment-scanner-evidence-*.json`，成功信息让下一步去跑 `bash scripts/generate-final-report.sh`。该脚本先 `[ -f ]` 三个输入，失败则 exit 1，不会渲染。脚本不做 `cygpath`，也不把反斜杠换成当前 bash 认的路径。WSL 里的 `bash` 对 `C:\Users\...` 的 `stat` 失败，第二步稳定停在「文件不存在」，尽管 ps1 已经用 Windows 上的 Python 写好了证据。Git Bash 若把参数原样交给内建 `[`，同样失败。即便文件检查通过，随后启动的若是 MSYS 版 Python，`platform.system()` 往往不是 `Windows`，打开报告会走 `xdg-open` 或 Linux 兜底，而不是 `os.startfile`。`open_report.py` 返回 1 时壳脚本仍以 0 结束，HTML 已经落盘；这条只说明「打开失败不会回滚报告」，不说明路径一定打得开。
- 证据：ps1 的 `$EvidenceFile = Join-Path ...` 与「再运行 bash scripts/generate-final-report.sh」；sh 的 `if [ ! -f "$required" ]`。
- 如何确认：在 Windows 上用 ps1 跑完收集，把终端打印的证据路径原样作为 `bash scripts/generate-final-report.sh` 的第一个参数（分别用 WSL 的 bash 和 Git Bash）。断言要么脚本自己把该路径转成当前 bash 能 `stat` 的路径并完成渲染，要么在转换失败时不要以「文件不存在」结束一次已经成功的收集。不要手改成 `/mnt/c/...` 或 `C:/...` 之后再声称原路径可用。
- 不成立的可能：操作者已经把路径转成 Git Bash 的 `/c/...` 或 `C:/...`，或者 MSYS 的 `stat` 直接接受 `C:\...`，并且 `python3` 是 Windows 版 Python。那样 `[ -f ]` 和随后的渲染可以成功。本仓库没有在 Windows 上跑这条交接，不能把「MSYS stat 一定失败」写成已观察到的事实。

### P6 跳过名单漏了 Local Settings，junction 又不是 is_symlink
- 严重度：latent
- 位置：`scripts/lib/platform_win.py` `home_discover_skip_dirs`（约第 87–97 行）；`scripts/lib/sample_content.py` `discover_files`（约第 186–204 行）；`scripts/lib/kb_discover.py` `enter`（约第 103–126 行）；`scripts/lib/scan_collect.py` `walk`（约第 152–161 行）
- 目标如何失败：注释写明 pathlib 会穿透 junction，必须按名字跳过。名单里有 `AppData`、`Application Data`，没有用户配置文件根上指向 `AppData\Local` 的 `Local Settings`。`Contact` 对不上实际的 `Contacts`，`{31C248AC-742E-4EEE-A-DEL}` 不是目录名。`is_symlink()` 对 junction 为假，发现循环会把 `Local Settings` 当普通目录进入。库存 ACL 拒绝列出这些 junction 时，`iterdir` 抛权限错误，记一条 `unreadable:` 后返回，不烧目录预算，兄弟目录仍会扫到。名单只用于主目录发现。四根 `walk` 不用这套名字，`Documents` 里的 `My Music` / `My Pictures` / `My Videos` junction 仍会进入 `walk`；ACL 拒绝列出时每个都变成 `unreadable:`，Windows 证据的警告列表因此稳定地带上兼容性 junction。若列出被允许（提权、ACL 被改掉，或运行时跟着 reparse 点走进目标），采样发现按名字排序后深度优先进入 `Local Settings`，也就是 `AppData\Local`。8000 目录或 15 秒预算耗尽后，排序更后的 `OneDrive`、用户项目目录不再进入发现。知识库发现不排序，但是深度优先，同样会在预算内停住。两边都返回 0。结果是成功的证据里没有本来该发现的 vault，或者文档计数混入 junction 另一头的文件。
- 证据：返回的集合字面量没有 `Local Settings`；发现循环只在 `entry.is_symlink()` 时跳过；`walk` 只调用 `skip_dir`。
- 如何确认：在 Windows 夹具的主目录放一个可列出的 junction，名为 `Local Settings`，指向一棵超过目录预算的目录树，其后再放一个带 `.obsidian` 的目录。断言该 vault 出现在 `knowledge_bases`，且 `scan_warnings` 里没有因这次穿透产生的 `kb_budget_reached` / `sample_budget_reached`。对照：ACL 拒绝列出时，只允许有 `unreadable:`，不得把目标树里的文件算进 `files`。
- 不成立的可能：默认用户权限列这些 junction 会 Access Denied，现有 `except PermissionError` 不会递归进 `AppData\Local`，预算不会被烧掉。`AppData` 这个真目录本身在名单里，不会从它的名字走进去。因此「每次 Windows 扫描都丢知识库」不成立，只有 junction 可列出时才成立。

### P7 行为 15、16、22、24 把 macOS 上的替身和源码子串锁成平台合同
- 严重度：degrade
- 位置：`tests/test-skill-behavior.sh` 行为 15（约第 485–495 行）、行为 16（约第 512–530 行）、行为 22（约第 803–858 行）、行为 24（约第 970–1016 行）
- 目标如何失败：行为 24 在 macOS 上 `ENV_SCANNER_PLATFORM=windows` 且 `collect_app_names(warnings, {})`。空 config 没有 `windows_program_dirs`，Program Files 分支不运行。没有 `winreg` 时警告来自 `ImportError`，测试断言这串 `windows_registry_unavailable` 存在。P1 里「模块在、名单为空、路径被 `is_dir()` 丢掉」走同一串警告，这条断言不会失败。通过条件还要求 `run-scan.ps1` 源码里能 grep 到 `-split ';'` 和「未实机验证」，以及 `.gitattributes` 里有 `eol=lf` / `eol=crlf`。ps1 不执行。注释里留下这些子串也会过。行为 22 用 `PATH` 里的假 `open` 覆盖 macOS，Windows 路径是在同一次 Python 里给 `os.startfile` 打补丁再调用 `open_report.main`。假 `open` 和假 `xdg-open` 往同一个日志写同样的一行，日志内容不能证明 linux 强制覆盖真的调用了 `xdg-open`。删除 `os.startfile` 后断言返回码 1，但没有经 `generate-final-report.sh` 断言「打开失败时脚本仍退出 0 且 HTML 仍在」。行为 15 只在当前适配器上用冒号拆两个临时目录，并断言无 `.app` 后缀的 `Microsoft Excel` 进入名单。行为 16 只跑 `run-scan.sh`，检查文件名存在、日志含「扫描模式: deep」，不读 `scan_warnings`，也不跑 ps1。测试文件第 9 行先 `unset ENV_SCANNER_PLATFORM`，所以 P3 的继承不会让 15 或 16 变红。
- 证据：`win.collect_app_names(warnings, {})` 后 `assert "windows_registry_unavailable" in warnings`；`grep -q "未实机验证"` 与 `grep -q -- "-split ';'"` 在同一个 `if` 里；行为 22 的 `os.startfile = lambda` 与 `assert rc == 1`。
- 如何确认：让 `_registry_names` 在成功导入 `winreg` 后返回空名单并仍写 `windows_registry_unavailable`，Program Files 路径不存在。现有行为 24 在 macOS 上仍然通过。把 ps1 的 `-split ';'` 从可执行语句改到注释里，行为 24 也仍然通过。让 `generate-final-report.sh` 在 `open_report.py` 返回 1 时以非零退出，行为 22 仍然通过。这三件事都应使对应用例失败。
- 不成立的可能：行为 24 对「macOS 分隔符是冒号、强制 windows 时分号能拆开两个目录、OneDrive/Documents 被选中、无 winreg 时出现那条警告」这些断言是真的执行了的，不是只 grep。行为 22 的补丁也确实要求成功路径调用 `startfile`。缺的是 P1 的另一条分支、ps1 进程，以及壳脚本在打开失败时的退出码。文档写了 ps1 未在真实 Windows 上执行，测试把「未实机验证」这几个字当成通过条件，并没有额外声称实机已通过。

### P8 文档规定的分隔符不会把 macOS 路径切成盘符；空格会被静默丢掉，覆盖根的收集规则也换了
- 严重度：degrade
- 位置：`scripts/run-scan.sh`（约第 57–60 行）；`scripts/run-scan.ps1`（约第 94–100 行）；`scripts/lib/app_inventory.py` `names_from_dirs`（约第 52–76 行）与 `collect`（约第 83–89 行）；`scripts/lib/sample_content.py`（约第 475–478 行）；`scripts/collect-data.sh`（约第 24 行）；`scripts/run-scan.sh`（约第 29–33、52–53 行）
- 目标如何失败：`ENV_SCANNER_INSIGHT_DOCS=/a.md; /b.md` 或 `ENV_SCANNER_APPLICATIONS=/Applications: ~/Applications` 时，第二段保留前导空格。`Path(" ~/x").expanduser()` 不会展开波浪号，`is_file` / `is_dir` 为假。洞察文档在采样里 `continue`，没有警告。应用根在 `names_from_dirs` 里同样 `continue`，没有 `unreadable:`。进程返回 0，证据里只是少了这份文档或第二个根。sh 的 `IFS=';' read` 会保留中间空段（`;` 开头或 `a;;b`），ps1 的 `-split ';'` 会丢掉空段；空段变成 `Path("")` 即 `.`，不是文件，所以采样结果通常仍一样。一旦设置了 `ENV_SCANNER_APPLICATIONS`，就不再调用 `MacAdapter.collect_app_names` 的「只收 `.app`」，而走 `names_from_dirs`：普通目录也算应用。注释写的是测试根。行为 15 断言 `Microsoft Excel` 这种无后缀目录在名单里，把这条锁死。按 README 把扫描根设成 `/Applications:~/Applications` 时，`Utilities` 这类目录会变成应用名，和默认扫描不是同一份名单。两入口在当前 `config.json`（`scan_depth` 为 `deep`、知识库默认开）且路径没有多余空格时，成功路径都调用同一批 Python，证据不会因为深度或知识库开关分叉。分叉在边上：`run-scan.sh` 找到 `python` 就能过预检，阶段 1 的 `collect-data.sh` 仍写死 `python3`，只有 `python` 时阶段 1 失败，输出目录已经 `mkdir`，没有证据文件；ps1 的 `Find-Python` 会改用 `python` 跑完。没有 `jq` 时 sh 不读 `config.json` 的 `scan_depth`，直接用硬编码 `deep`；ps1 用 `ConvertFrom-Json` 读配置。今天配置值也是 `deep`，所以这条还不会让两边产物不同。ps1 用法行把模式和额外文档都写成可选；只传一个文档路径时，它绑到 `$ScanMode`，未知模式回退 `deep`，该路径不会进 `--explicit`。sh 对 `$1` 同样吃掉。`SKILL.md` 的示例没有把单个文档放在第一个参数，ps1 文件头的用法有。
- 证据：`env_roots.split(adapter.env_path_sep())` 不 `strip`；`if not path.is_file() or path.is_symlink(): continue`；`if not root.is_dir(): continue`；`collect-data.sh` 的 `python3 "$SCRIPT_DIR/lib/scan_collect.py"`；ps1 头注释「`[quick|standard|deep] [额外文档路径...]`」。
- 如何确认：macOS 上按 README 设置 `ENV_SCANNER_INSIGHT_DOCS` 为两段、分号后有一个空格，以及 `ENV_SCANNER_APPLICATIONS=/Applications:~/Applications`（冒号后有无空格各一次）。断言两份洞察文档都在 `recent_files`，应用名单与不设该变量时一样只有一级 `.app`，且第二个根缺失时有警告、退出码非零。再在 `PATH` 里只有 `python`、没有 `python3` 时跑 `run-scan.sh`，断言预检失败发生在 `mkdir` 之前，或者阶段 1 使用同一个解释器。
- 不成立的可能：分隔符两侧没有空格、洞察文档用分号、应用根在 macOS 上用冒号时，`read -r` 与 `split(":")` 不会把 `/Users/...` 切碎（已在本机 bash 3 上对 `a;b`、`/Users/a/文档.md;/Users/a/b.md` 看过字段）。默认不设 `ENV_SCANNER_APPLICATIONS` 时仍只收 `.app`。本机有 `python3` 时，sh 的预检和 `collect-data.sh` 用的是同一个解释器，阶段 1 不会因为这行写死而失败。

读过：`SKILL.md` 平台节与工作流、`README.md` 环境变量表、`config.json` 的 `app_inventory.windows_program_dirs`、`scripts/lib/platforms.py`、`platform_mac.py`、`platform_win.py`、`app_inventory.py`、`open_report.py`、`scan_collect.py`、`sample_content.py`、`kb_discover.py`、`evidence_pack.py`、`judgment.py` 的应用区与 KPI、`scripts/run-scan.sh`、`scripts/run-scan.ps1`、`scripts/collect-data.sh`、`scripts/generate-final-report.sh`、`.gitattributes`、`tests/test-skill-behavior.sh` 行为 15、16、22、24。未执行 ps1。
