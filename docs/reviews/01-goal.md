# 目标交付审查

审查范围：`SKILL.md` 的判断准则、判断文件合同、校验规则；`scripts/lib/judgment.py` 的校验与渲染字段；`scripts/generate-final-report.sh`；`templates/final-report.html` 里画像、理解、建议、优先级、第一步；`tests/test-skill-behavior.sh` 行为 08、09、17、19、20。`generate-final-report.sh` 第 32–33 行只调用 `validate` 再 `render`，没有第二道检查。

### F1 校验放行套话：不点名用户的事、第一步可以没有可复制提示词、优先级可以不是快见效小事

- 严重度：blocker
- 位置：`scripts/lib/judgment.py` `validate`（约 203–236、263–292 行）；`SKILL.md` 约 51、100–101、115–116 行；行为 09（约 288、322–330 行）、行为 19（约 633–637 行）、行为 20（约 724–727、746–751 行）
- 目标如何失败：三件事可以被一份看起来完整的报告假完成。活动、角色、第一步、理由只要求非空字符串；有文件时第一步只要求任意一个文件名是子串；只有指标时第一步可以完全不写交给 AI 的内容；`quick_win` 由判断自己填，全是 false 时「第一条必须是快见效」不生效，`effort: high` 也可以标快见效并排第一。
- 证据：`REQUIRED_TEXT_FIELDS` 只含 `activity`、`ai_role`、`first_step`、`expected_saving`、`reason`。文件名检查是 `if file_names and not any(name in first_step for name in file_names)`。快见效检查是 `if priorities and quick_win_ids` 才看第一条的 id，不看 `effort`，也不看正文是否是一件小事。渲染只凭 `quick_win is True` 打上「快见效」徽章（约 428–429 行）。对照实验：`sources` 仅为 `counts.ebooks`、`first_step` 为「先做一下」、`activity` 为「处理一下文档」、`effort` 为 `high` 的判断通过校验；`quick_win: false` 的唯一建议也能通过。行为 09 的合格样本第一步就是「把《活动方案.md》交给 AI。」，没有开场提示词，也没有技能要求的「不要补充文件里没有的事实」；同段写出的 `mx-good-slow.json`（`quick_win` 为 false）没有参与断言。行为 19 把「把《周报.md》发给 AI。」锁成合格。行为 20 只断言指标路径存在，不断言第一步里有可交给 AI 的文件或目录。
- 如何确认：用一份真实证据跑 `judgment.py validate`：建议正文不出现用户的事，第一步写「先做一下」，`sources` 用 `{"type":"metric","ref":"counts.ebooks"}`，`quick_win` 全 false，`effort` 为 `high`。当前会通过。再把行为 09 的合格第一步改成不含「请……」和「不要补充文件里没有的事实」，现有测试仍然通过。
- 不成立的可能：会话 AI 若严格按 `SKILL.md` 写，正文仍可能具体。这次失败的是门禁：技能把「文件名落进第一步」当成挡住套话的校验，代码和测试都把只含文件名的句子当成合格。

### F2 开篇把用户指到没有第一步的活动；「最值得优先尝试」里没有要交的文件和提示词

- 严重度：blocker
- 位置：`judgment.py` `render` 约 595–599、619–630 行，`priority_block` 约 495–505 行，`chart_payload` 约 371–397 行；`templates/final-report.html` 约 218–226、237–300、270 行
- 目标如何失败：非技术用户从页面上方读到的「先做哪件」，和下面真正可执行的第一步不是同一件事。优先区块只有「为什么 / 如何开始 / 长期帮助」，不渲染 `first_step`。建议按判断数组原顺序输出，不按优先级排。画像对非 power 固定写「标『还没用 AI』的，是最先值得尝试的地方」，不要求该行有建议。图表和每日/每周/每月协作排在优先区块之前。
- 证据：`priority_block` 只用 `entry` 的 `why`、`how_to_start`、`long_term` 和对应建议的 `activity`。`how_to_start` 的校验只要求 1–4 条非空字符串（约 285–287 行）。对照一份能通过校验的判断：诊断第一行是「整理旧书 / 还没用 AI」且没有对应建议；第一条建议是高投入的「激活全部旧书」，第一步是「跟 AI 说：把书都分分类」；真正的快见效是第二条，提示词含《活动方案.md》和「不要补充文件里没有的事实」。渲染结果里，优先卡片不含文件名和这句提示词，只含「开始」；「时间分配」出现在该提示词之前。导航顺序是画像、整体理解、数据可视化、建议、协作方式、优先建议（模板约 218–226 行），没有「第一步」。`chart_payload` 的 `timeAllocation` 是 `activity_heat` 的文件数占比（`evidence_pack.py` 约 49–59 行按样本目录计数），标题却是「时间分配（活跃目录占比）」（模板约 270 行）。行为 17（约 584–595 行）只断言四个区块 id、四张图，以及页面上出现「第一步」「如何开始」这些标签，不断言优先区块里有文件名或提示词。
- 如何确认：渲染上述两建议判断，看 `#priorities` 内是否有 `活动方案.md` 或「不要补充」，并比较它和 `#charts`、第一条 `.suggestion-card` 的文档顺序。再搜 `render` 里 novice 导语，确认它不读取 `priorities[0]`。
- 不成立的可能：若只有一条建议，且模型把同一句提示词写进 `how_to_start`，用户在建议卡和优先卡都能看见。校验不要求这一点。图表标题后半句写了「活跃目录占比」，没有把未读的 PDF 正文说成已读；它仍会在第一步之前给出一个看起来像「时间花在哪」的图。

### F3 文件位置和指标引用可以不真实或不可执行，报告仍写成「用到的证据」

- 严重度：degrade
- 位置：`judgment.py` `ref_error` 约 90–104 行，`metric_lookup` 约 75–83 行，`suggestion_card` 约 430–437 行；`SKILL.md` 约 79、102 行
- 目标如何失败：「第一步把哪份文件交给 AI」可以被一个编出来的目录带偏；只靠指标的建议可以不指向任何打得开的文件。多文件时提示词里出现一个文件名即过关，其余文件不必出现在可复制的第一步里。
- 证据：文件引用只检查 `name` 是否出现在 `recent_files` 或 `deep_reads` 的文件名集合里，不检查 `parent`。渲染把 `parent/name` 拼成「用到的证据」。实验：`parent` 为「完全编造/不存在」、`name` 为证据里真实的「活动方案.md」，校验通过，报告写出「完全编造/不存在/活动方案.md」。`metric_lookup` 用 `is None` 判断，值为 `0` 的 `counts.ebooks` 仍算存在；实验里「请激活我的书库」配 `ebooks: 0` 通过。`knowledge_bases` 整段列表可以作为指标通过，报告写成「指标 knowledge_bases」。`knowledge_bases.0.notes`、`knowledge_bases.0.journals.0.span_days` 因路径走进列表而失败——技能要求引用日记持续天数这类聚合，这种写法会被拒。两个真实文件只在 `first_step` 里出现其中一个也通过。行为 20 的合格第一步只说「我有 435 本电子书」，没有目录或文件；测试不断言这句话必须存在。
- 如何确认：对真实证据把 `sources[0].parent` 改成证据里没有的目录再 `validate`，然后在 HTML 里搜该字符串。另用 `{"type":"metric","ref":"counts.ebooks"}` 且把该计数改为 0，看是否仍通过。
- 不成立的可能：模型若原样抄证据里的 `parent`，目录就是对的。文件名本身必须真实存在，用户仍可能靠文件名搜到文件。指标通道是技能明确允许的；坏的是它不要求第一步写出用户打得开的位置，以及 0 和整包对象也算「证据存在」。

### F4 画像和 basic/upgrade 由判断自填，深度使用仍可再推荐基础用法，没做过的事可以只有升级建议

- 严重度：degrade
- 位置：`SKILL.md` 约 83–85、98 行；`judgment.py` 约 245–261 行；行为 19 约 630–676、681–687 行
- 目标如何失败：技能要求痕迹密则 power、几乎没有则 novice，且只对 `none`/`occasional` 给 `basic`、对 `deep` 只给 `upgrade`。校验不读 `ai_usage_signals` 来核对 `persona`，也不把建议的 `kind` 对上诊断活动的 `ai_usage`。已经深度在用 AI 的事可以再标成「基础用法」并成为快见效第一条。装了 AI 应用但每件事都是 `none` 时，可以只给「升级用法」，没有从零开始的第一步。反过来，画像填 `power` 时，只有基础第一步的判断会被拒，必须再添一条升级建议才过。
- 证据：`has_ai_basis` 在诊断里任一活动被标成 `occasional` 或 `deep`，或 `marker_files > 0`，或 `ai_apps` 非空时为真。升级建议只在 `has_upgrade and not has_ai_basis` 时拒绝。`persona == "power"` 时只要求至少一条 `upgrade`，不禁止 `basic`。实验：证据里已有 `marker_files` 和 `ai_apps: ["ChatGPT"]`，活动 `ai_usage: deep`，建议 `kind: basic`，`persona: novice`，通过。把信号清空、活动自标 `occasional` 后，升级建议仍通过。活动全是 `none` 但 `ai_apps` 有 ChatGPT 时，针对该活动的升级建议通过。`persona: power` 且只有一条基础建议时失败，错误是「至少要有一条升级型建议」。行为 19 的合格样本是：摘录写「本周用 AI 写了周报」、`marker_files` 为 1、`ai_apps` 含 ZCode，画像仍是 novice，建议仍是 basic，第一步是「把《周报.md》发给 AI。」。它拒绝的是「信号空且诊断为 none 时的升级」和「power 完全没有升级」，没有「deep 活动配 basic」的反例。
- 如何确认：用带 `ai_apps` 的证据提交 `deep + basic + persona novice`，以及 `活动全 none + kind upgrade`，看 `validate` 是否返回 0。行为 19 不会因此失败。
- 不成立的可能：`occasional` 配 `basic` 是技能允许的，不能把行为 19 的周报样本直接说成违反「deep 只给 upgrade」。若模型同时写对画像、档位，并保留一条基础快见效，用户仍能得到第一步。门禁挡不住写错的那一份，也会在 power 只交基础第一步时逼模型多写一条升级建议。

### F5 答完三件事的判断会因理解卡不足两条被拒，补上空话才能过，空话排在建议前面

- 严重度：degrade
- 位置：`judgment.py` 约 296–329 行；`SKILL.md` 约 94、101、107 行；模板约 249–285 行
- 目标如何失败：一份已经写明要交的文件、可复制提示词和快见效优先级的判断，只要四张理解卡不是各 2–6 条，整份被拒，建议不会渲染。过关的办法是补非空短句。这些短句不要求引用，也不要求「把哪份文件交给 AI」。协作节奏同样只查非空。理解卡渲染在建议之前，节奏卡夹在建议和优先级之间，空话先被看见。
- 证据：有建议时，`activities` / `domains` / `work_style` / `structure` 每卡必须 2–6 条；`basis` 只有在字段出现时才检查。`cadence` 的 `items` 只要求 1–4 条非空字符串。实验：第一步同时点名两份真实文件并写上「不要补充文件里没有的事实」，优先级写「现在把文件交给 AI」，但每张理解卡只有 1 条，校验只报四条「需要 2–6 条要点」。同结构下节奏写成「问问 / 看看 / 复盘」不报错。技能要求重要论点挂 `basis`、节奏具体到哪份文件、第一步含那句固定提示（约 94、101、107 行），这三处校验都不查。
- 如何确认：拿一份三件事都写全、理解卡各 1 条的判断跑 `validate`，应失败；把每卡第二句改成「凑数」、节奏改成「问问」后应通过。再看 HTML 中 `#understanding` 是否在 `#suggestions` 之前。
- 不成立的可能：技能自己规定了四卡各 2–6 条，按技能写不会被这条拒。被拒的是比合同更瘦、但三件事已经答完的判断。补上的第二句可以仍是具体的；校验不区分具体和「凑数」。

### F6 零信号忽略深读自述：自述已经能引用，仍然禁止给出第一步

- 严重度：latent
- 位置：`scripts/lib/evidence_pack.py` 约 163 行；`judgment.py` 约 138–140、175–177 行；`SKILL.md` 约 89、117 行；行为 08 约 244–265 行
- 目标如何失败：技能把 `deep_reads` 当作「这个人是谁」的最强证据，也把深读文件名算进可引用文件。`zero_signal` 却只表示「没有近期文件且没有应用」，知识库和自述不算。标志为真时，即使第一步点名深读文件并写了提示词，也不许生成建议。这个人得不到「先做哪件、把哪份自述交给 AI」。
- 证据：`zero_signal` 赋值为 `not files and not app_names`。`known_files` 会并入 `deep_reads` 的 `name`。实验：`zero_signal: true`、`recent_files` 和 `apps` 为空、`deep_reads` 含「个人画像.md」，建议的 `sources` 和 `first_step` 都点名该文件并写了「不要补充文件里没有的事实」，唯一错误是「证据为零信号（无近期文件且无应用），不允许生成建议」。行为 08 的坏样本同时缺 `persona`、`diagnosis`、`kind`、真实文件、`how_to_start`、`long_term`、理解层和节奏层；把同一坏样本的 `zero_signal` 改成 false，仍然因这 9 类错误失败。测试只看退出码，不断言错误文本含「零信号」，也没有「零信号但有深读」的样本。
- 如何确认：构造 `zero_signal: true` 且 `deep_reads` 非空的证据，提交只引用该深读文件的完整判断。再临时去掉 `judgment.py` 里 `if evidence.get("zero_signal")` 那段后重跑行为 08，看测试是否仍绿。
- 不成立的可能：应用清单非空时 `zero_signal` 为 false，深读可以作为 `sources`，这条不触发。macOS 正常扫描 `/Applications` 时应用清单很少为空。近期文件和深读都空时，禁止编造建议是对的。
