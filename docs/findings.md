# 发现记录：Windows 兼容性对抗性审查（v4.1.0 改造输入）

## 对抗性审查结论（2026-10-25，针对 v4.0.0 代码逐行核查）

### 🔴 会直接出错

1. **冒号分隔符 × 2 处**
   - `run-scan.sh:58` `IFS=':' read ENV_SCANNER_INSIGHT_DOCS` — Windows 路径 `C:\Users\...` 被切成 `C` + `\Users\...`
   - `app_inventory.py` `env_roots.split(":")`（ENV_SCANNER_APPLICATIONS）— 同样问题
   - 修复：统一改 `;`（决策 D2）
2. **CRLF 杀死 bash 脚本**：开源后 Windows 用户 `git clone`（autocrlf=true）会把 `.sh` 转成 CRLF → `#!/bin/bash\r` → "bad interpreter"
   - 修复：`.gitattributes` 锁 `*.sh text eol=lf`；顺带 `*.ps1 text eol=crlf`
3. **主目录发现预算被 AppData 烧光**：`sample_content.DEFAULT_DISCOVER_SKIP` 与 `kb_discover.DISCOVER_SKIP_DIRS` 全是 mac 目录名（Library/Applications/…），Windows 家目录的 `AppData`（数万子目录）不在名单 → 6000 目录/20 秒预算耗尽在 AppData，走不到用户文档；且 `Application Data` 等 junction 会被 pathlib 穿透造成重复遍历
   - 修复：跳过名单进适配器（win 名单含 AppData + junction 名：Application Data/Cookies/NetHood/PrintHood/Recent/SendTo/Start Menu/Templates/My Documents/My Pictures/My Music/My Videos/OneDriveTemp/…）

### 🟡 会静默变弱

4. **OneDrive 重定向**：Windows Documents/Desktop 常被重定向，`~/Documents` 不存在 → 根不存在时静默空证据（不崩）
   - 修复：win 适配器 `default_user_roots()` 探测 `home/OneDrive*/Documents|Desktop`，存在则优先
5. **GBK 编码**：Windows 记事本类 txt/csv 是 GBK，按 utf-8 errors=ignore 读会乱码（不崩）。本轮不修，已记录（修复需 chardet 类依赖或 gb18030 回退，另行决策）

### 🟢 环境事实

- 本机（darwin）**无 pwsh / powershell**（已确认），`run-scan.ps1` 只能人工审查，必须如实标注「未实机验证」
- `collect-data.ps1` 未被主流水线引用（独立脚本），且无 v4 的 structure/采样 → 归档
- macOS 全链路已实机验证（v4.0.0，产物 environment-scanner-final-2026-10-25-174604.html）
- Windows 从未实机验证过任何版本

## 适配器接口（阶段 1 已实现，供重构参考）

```
adapter.name() -> "mac"|"windows"|"linux"
adapter.env_path_sep() -> mac":" win";"
adapter.app_roots(config) -> 扫描根列表
adapter.collect_app_names(warnings, config) -> 应用名列表（只读名字）
adapter.home_discover_skip_dirs() -> set[str]
adapter.default_user_roots(home) -> {documents, desktop, downloads, books}
adapter.os_version() -> 版本串
```

- 选择器 `platforms.get_platform()`：`ENV_SCANNER_PLATFORM` 强制覆盖 > `platform.system()`
- mac 适配器：`/Applications` + `~/Applications` 一级 `.app`；sw_vers
- win 适配器：winreg 三处卸载表（HKLM64/WOW6432Node/HKCU，QueryValueEx DisplayName）+ Program Files 一级目录；`win32_ver`；OneDrive glob `OneDrive*`
- win 注册表不可用时降级 `windows_registry_unavailable` 警告，不崩

## 重构注意（阶段 2 执行要点）

- `scan_collect.py` 的 `load_skip_rules()`（敏感目录规则）是**安全层**，与平台跳过名单是两回事，合并时不要互相覆盖：安全层规则照旧从 config `smart_filtering` 读，平台名单只用于「主目录发现」
- `sample_content.py` 的 config `discover_skip_dir_names`（用户可配）与 adapter 名单取**并集**
- `app_inventory.py` 重构后 config 键 `mac_dirs` / `windows_program_dirs` 保留，由 `adapter.app_roots(config)` 消费
- 测试夹具路径全是 `/tmp/...`（Git Bash 可映射），无需改
