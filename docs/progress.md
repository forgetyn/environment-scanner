# 进度日志

## 会话 2026-10-25（v4.1.0 Windows 适配器改造）

- [x] 对抗性审查完成（结论入 findings.md），用户确认「适配器拆分」方向（修正自其"全盘两套"提案）
- [x] 阶段 1 完成：`platforms.py` / `platform_mac.py` / `platform_win.py` 写入并 py_compile 通过
- [x] 建立本规划文件体系（task_plan / findings / progress），此后每阶段完成即更新
- [x] 阶段 2 完成：四采集模块全部接适配器；`tests/` 新路径下行为回归 21/21 全绿（mac 无回归）
- 备注：会话中发现仓库被外部整理（tests/ 目录、README.md、.gitignore、清理 dotdirs），已核对无冲突并吸收进计划
- [x] 阶段 3：`run-scan.sh` 分隔符改为 `;`，新增 `.gitattributes`
- [x] 阶段 4：`run-scan.ps1` + 归档 `collect-data.ps1`
- [x] 阶段 5：行为 24 平台适配器测试（计划写的 22 已被占用）
- [x] 阶段 6：真实复扫 `215203`，关键指标与 174604 一致
- [x] 阶段 7：文档同步 v4.1.0

### run-scan.ps1 人工审查（本机无 pwsh，未执行）

对照 `run-scan.sh` 逐段看过：

1. 扫描模式缺省读 `config.json` 的 `default_config.scan_depth`，非法值回退 deep。
2. 找 `python3`，没有再找 `python`。
3. 五个阶段调用 `scan_collect.py`、`sample_content.py`、`app_inventory.py`、`kb_discover.py`、`evidence_pack.py`、`judgment.py render`。不调用 bash，也不调用已归档的 `collect-data.ps1`。
4. `ENV_SCANNER_INSIGHT_DOCS` 按分号拆开，空段丢掉。额外位置参数接在后面，当作显式文档。
5. `ENV_SCANNER_KB_DISCOVER=0` 时跳过知识库发现，且不把 `--kb` 传给证据合并。
6. 检查 data / samples / apps / evidence / evidence-report 非空。知识库文件不在这份必查清单里，与 bash 一致。
7. 非零退出码会中断。文件为 UTF-8 BOM + CRLF。
8. 第 2 步最终报告仍提示运行 `generate-final-report.sh`（需要 bash）。这一步没有 ps1。

### 测试结果记录

- v4.3.0（2026-10-26）：工具自带 CPython 3.12.14。入口优先用能运行的系统 Python，否则离线解压到用户私有目录。Windows 增加 `generate-final-report.ps1`。ps1 未在真实 Windows 上执行。快速测试通过；行为 26/26；全量 46 通过 / 0 失败 / 0 警告。
- v4.2.0（2026-10-26）：日记改为读知识库配置；跳过安装包、压缩包、日志、私钥文件和软件数据目录。Logseq 图标记改为 `logseq/config.edn`。三路审查、核实、责任点校验后没有未处理的必须改项。快速测试通过；行为 25/25；全量 33 通过 / 0 失败 / 0 警告。报告见 `docs/reviews/07-test-report.md`。
- v4.1.1（2026-10-25）：对抗式审查后修了六条（自述词典、日记文件名、办公格式与整词跳过、空 OneDrive 与缺失根、密钥识别、深读摘录不进报告）。执行复审通过。快速测试通过；行为 25/25；全量 33 通过 / 0 失败 / 0 警告
- v4.1.0（2026-10-25）：快速测试通过；行为 24/24；全量 33 通过 / 0 失败 / 0 警告
- 真实复扫 215203：120 近期文件 / 46 应用 / 1 vault / 日记 83+60；证据报告九个区块都在
- v4.0.0 基线：行为 21 项 / 全量 29 项 / 0 失败 0 警告。其后未发布改动（行为 22、23）已并入 4.1.0
