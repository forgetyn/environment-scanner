#!/usr/bin/env python3
"""校验 AI 判断并把最终报告渲染出来。

validate: 判断必须通过确定性校验，防止编造文件和空洞建议。
render:   有判断时渲染最终报告；无判断时渲染证据报告（降级形态）。
合同 v4：恢复综合层（整体理解/资产发现/协作节奏），引用支持文件与
聚合指标双通道，图表数据全部由渲染器从证据确定性注入，判断不许手填数字。
"""

import argparse
import html
import json
import sys
from datetime import datetime
from pathlib import Path

from common import load_json

VERSION = "4.0.0"
DEFAULT_MAX_SUGGESTIONS = 10
DEFAULT_MAX_PRIORITIES = 3
DEFAULT_MAX_ACTIVITIES = 8
DEFAULT_MAX_ASSETS = 6
DEFAULT_MAX_ADVICE = 4
EFFORT_LEVELS = {"low", "medium", "high"}
PERSONAS = {"novice", "power"}
AI_USAGE_LEVELS = {"none", "occasional", "deep"}
SUGGESTION_KINDS = {"basic", "upgrade"}
REQUIRED_TEXT_FIELDS = ("activity", "ai_role", "first_step", "expected_saving", "reason")
UNDERSTANDING_CARDS = (
    ("activities", "主要活动类型"),
    ("domains", "关注的主要领域"),
    ("work_style", "工作或学习方式"),
    ("structure", "文件结构特点"),
)
CADENCE_PERIODS = ("daily", "weekly", "monthly")
REQUIRED_SECTIONS = (
    "profile", "understanding", "charts", "suggestions",
    "cadence", "priorities", "assets", "advice", "evidence",
)

AI_USAGE_TEXT = {
    "none": "还没用 AI",
    "occasional": "偶尔用 AI",
    "deep": "已经在深度用",
}


def config_path():
    return Path(__file__).resolve().parents[2] / "config.json"


def load_report_config():
    limits = {
        "max_suggestions": DEFAULT_MAX_SUGGESTIONS,
        "max_priorities": DEFAULT_MAX_PRIORITIES,
        "max_activities": DEFAULT_MAX_ACTIVITIES,
        "max_assets": DEFAULT_MAX_ASSETS,
        "max_advice": DEFAULT_MAX_ADVICE,
    }
    path = config_path()
    if not path.is_file():
        return limits
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return limits
    block = raw.get("features", {}).get("report", {})
    for key in limits:
        if block.get(key):
            limits[key] = int(block[key])
    return limits


def metric_lookup(evidence, ref):
    """按 dotted path 在证据里找聚合指标，找不到返回 None。"""
    node = evidence
    for part in str(ref).split("."):
        if isinstance(node, dict) and part in node:
            node = node[part]
        else:
            return None
    return node


def is_metric_ref(item):
    return isinstance(item, dict) and item.get("type") == "metric"


def ref_error(item, known_files, evidence):
    """校验单个引用（文件名或聚合指标），返回错误描述或 None。"""
    if is_metric_ref(item):
        ref = str(item.get("ref") or "")
        if not ref or metric_lookup(evidence, ref) is None:
            return f"指标引用「{ref}」在证据里不存在"
        return None
    if not isinstance(item, dict):
        return "引用必须是对象"
    name = str(item.get("name") or "")
    if not name.strip():
        return "文件引用缺少 name"
    if name not in known_files:
        return f"引用的「{name}」不在证据的近期文件里"
    return None


def non_empty_strings(value, limit):
    return (
        isinstance(value, list)
        and 1 <= len(value) <= limit
        and all(isinstance(item, str) and item.strip() for item in value)
    )


def validate(evidence, judgment):
    """返回错误列表。空列表代表判断可以渲染。"""
    limits = load_report_config()
    errors = []
    if not isinstance(judgment, dict):
        return ["判断必须是 JSON 对象"]

    suggestions = judgment.get("suggestions")
    if not isinstance(suggestions, list):
        return ["suggestions 必须是列表"]
    if not 0 <= len(suggestions) <= limits["max_suggestions"]:
        errors.append(f"建议数量必须在 0 到 {limits['max_suggestions']} 之间，现在是 {len(suggestions)}")

    insufficient = judgment.get("insufficient_evidence")
    if not isinstance(insufficient, bool):
        errors.append("insufficient_evidence 必须是布尔值")
        insufficient = None

    if not suggestions and insufficient is not True:
        errors.append("没有建议时 insufficient_evidence 必须是 true")
    if suggestions and insufficient is not False:
        errors.append("有建议时 insufficient_evidence 必须是 false")

    if evidence.get("zero_signal"):
        if suggestions:
            errors.append("证据为零信号（无近期文件且无应用），不允许生成建议")

    persona = judgment.get("persona")
    if persona not in PERSONAS:
        errors.append("persona 必须是 novice（新手档）或 power（重度用户档）")

    diagnosis = judgment.get("diagnosis")
    diag_activities = []
    if not isinstance(diagnosis, dict):
        errors.append("缺少 diagnosis 全局诊断层（summary + activities）")
    else:
        summary = diagnosis.get("summary")
        if not isinstance(summary, str) or not summary.strip():
            errors.append("diagnosis.summary（一句话整体结论）不能为空")
        acts = diagnosis.get("activities")
        if not isinstance(acts, list):
            errors.append("diagnosis.activities 必须是列表")
        else:
            if len(acts) > limits["max_activities"]:
                errors.append(f"诊断活动最多 {limits['max_activities']} 条，现在是 {len(acts)}")
            if suggestions and not acts:
                errors.append("有建议时 diagnosis.activities 不能为空")
            for index, act in enumerate(acts):
                tag = f"诊断活动[{index + 1}]"
                if not isinstance(act, dict):
                    errors.append(f"{tag}: 必须是对象")
                    continue
                if not isinstance(act.get("activity"), str) or not str(act.get("activity")).strip():
                    errors.append(f"{tag}: activity 不能为空")
                if act.get("ai_usage") not in AI_USAGE_LEVELS:
                    errors.append(f"{tag}: ai_usage 必须是 none/occasional/deep")
                if not isinstance(act.get("time_note"), str) or not str(act.get("time_note")).strip():
                    errors.append(f"{tag}: time_note（时间占用粗估）不能为空")
            diag_activities = acts

    known_files = {str(item.get("name") or "") for item in evidence.get("recent_files") or []}
    known_files.update(str(item.get("name") or "") for item in evidence.get("deep_reads") or [])
    known_files.discard("")
    known_apps = {str(name) for name in evidence.get("apps") or []}
    seen_ids = set()

    def check_refs(tag, refs):
        if not isinstance(refs, list):
            errors.append(f"{tag}: basis/引用必须是列表")
            return
        for item in refs:
            problem = ref_error(item, known_files, evidence)
            if problem:
                errors.append(f"{tag}: {problem}")

    for index, item in enumerate(suggestions):
        tag = f"建议[{index + 1}]"
        if not isinstance(item, dict):
            errors.append(f"{tag}: 必须是对象")
            continue
        item_id = str(item.get("id") or "")
        if item_id:
            tag = f"建议 {item_id}"
            if item_id in seen_ids:
                errors.append(f"{tag}: id 重复")
            seen_ids.add(item_id)
        else:
            errors.append(f"{tag}: 缺少 id")
        for field in REQUIRED_TEXT_FIELDS:
            value = item.get(field)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{tag}: {field} 不能为空")
        if item.get("effort") not in EFFORT_LEVELS:
            errors.append(f"{tag}: effort 必须是 low/medium/high")
        if item.get("kind") not in SUGGESTION_KINDS:
            errors.append(f"{tag}: kind 必须是 basic（基础用法）或 upgrade（升级用法）")
        if not isinstance(item.get("quick_win"), bool):
            errors.append(f"{tag}: quick_win 必须是布尔值")
        sources = item.get("sources")
        if not isinstance(sources, list) or not sources:
            errors.append(f"{tag}: sources 至少要引用一个证据（文件或指标）")
            sources = sources if isinstance(sources, list) else []
        file_names = []
        metric_refs = 0
        for source in sources:
            if is_metric_ref(source):
                problem = ref_error(source, known_files, evidence)
                if problem:
                    errors.append(f"{tag}: {problem}")
                else:
                    metric_refs += 1
                continue
            problem = ref_error(source, known_files, evidence)
            if problem:
                errors.append(f"{tag}: {problem}")
                continue
            file_names.append(str(source.get("name")))
        if sources and not file_names and not metric_refs:
            errors.append(f"{tag}: sources 里没有任何有效引用")
        first_step = item.get("first_step") if isinstance(item.get("first_step"), str) else ""
        if file_names and not any(name in first_step for name in file_names):
            errors.append(f"{tag}: first_step 里必须出现 sources 点名的文件名")
        app_refs = item.get("app_refs") or []
        if not isinstance(app_refs, list):
            errors.append(f"{tag}: app_refs 必须是列表")
            app_refs = []
        for app in app_refs:
            if str(app) not in known_apps:
                errors.append(f"{tag}: app_refs 里的「{app}」不在应用清单里")

    signals = evidence.get("ai_usage_signals") or {}
    marker_files = signals.get("marker_files") or 0
    has_ai_basis = (
        any(
            isinstance(act, dict) and act.get("ai_usage") in {"occasional", "deep"}
            for act in diag_activities
        )
        or marker_files > 0
        or bool(signals.get("ai_apps"))
    )
    has_upgrade = any(
        isinstance(item, dict) and item.get("kind") == "upgrade" for item in suggestions
    )
    if has_upgrade and not has_ai_basis:
        errors.append("证据里没有任何 AI 使用痕迹（诊断活动和 ai_usage_signals 都是空），不允许出现升级型建议")
    if persona == "power" and suggestions and not has_upgrade:
        errors.append("画像为 power（重度用户档）时，至少要有一条升级型建议")

    priorities = judgment.get("priorities")
    if not isinstance(priorities, list):
        errors.append("priorities 必须是列表")
        priorities = []
    if len(priorities) > limits["max_priorities"]:
        errors.append(f"优先级最多 {limits['max_priorities']} 条，现在是 {len(priorities)}")
    quick_win_ids = {
        str(item.get("id"))
        for item in suggestions
        if isinstance(item, dict) and item.get("quick_win") is True
    }
    for index, entry in enumerate(priorities):
        tag = f"优先级[{index + 1}]"
        if not isinstance(entry, dict):
            errors.append(f"{tag}: 必须是对象")
            continue
        ref = str(entry.get("id") or "")
        if ref not in seen_ids:
            errors.append(f"{tag}: 引用的 id「{ref}」不在建议里")
        why = entry.get("why")
        if not isinstance(why, str) or not why.strip():
            errors.append(f"{tag}: why 不能为空")
        if not non_empty_strings(entry.get("how_to_start"), 4):
            errors.append(f"{tag}: how_to_start 需要 1-4 条非空步骤")
        if not non_empty_strings(entry.get("long_term"), 4):
            errors.append(f"{tag}: long_term 需要 1-4 条非空长期帮助")
    if priorities and quick_win_ids:
        first_ref = priorities[0].get("id") if isinstance(priorities[0], dict) else None
        if str(first_ref) not in quick_win_ids:
            errors.append("存在快见效建议时，优先级第一条必须是快见效项")
    if suggestions and not priorities:
        errors.append("有建议时 priorities 不能为空")

    understanding = judgment.get("understanding")
    if suggestions:
        if not isinstance(understanding, dict):
            errors.append("有建议时缺少 understanding 整体理解层（四张卡）")
        else:
            for key, label in UNDERSTANDING_CARDS:
                card = understanding.get(key)
                if not isinstance(card, list) or not 2 <= len(card) <= 6:
                    errors.append(f"整体理解「{label}」需要 2-6 条要点")
                    continue
                for index, point in enumerate(card):
                    tag = f"整体理解·{label}[{index + 1}]"
                    if not isinstance(point, dict) or not isinstance(point.get("text"), str) or not point.get("text").strip():
                        errors.append(f"{tag}: text 不能为空")
                        continue
                    if "basis" in point and point.get("basis") is not None:
                        check_refs(tag, point.get("basis"))

    cadence = judgment.get("cadence")
    if suggestions:
        if not isinstance(cadence, dict):
            errors.append("有建议时缺少 cadence 长期协作层（daily/weekly/monthly）")
        else:
            period_names = {"daily": "每日", "weekly": "每周", "monthly": "每月"}
            for period in CADENCE_PERIODS:
                block = cadence.get(period)
                tag = f"协作节奏·{period_names[period]}"
                if not isinstance(block, dict):
                    errors.append(f"{tag}: 必须是对象")
                    continue
                if not isinstance(block.get("summary"), str) or not block.get("summary").strip():
                    errors.append(f"{tag}: summary 不能为空")
                if not non_empty_strings(block.get("items"), 4):
                    errors.append(f"{tag}: items 需要 1-4 条非空事项")

    assets = judgment.get("assets") or []
    if not isinstance(assets, list):
        errors.append("assets 必须是列表")
        assets = []
    if len(assets) > limits["max_assets"]:
        errors.append(f"资产发现最多 {limits['max_assets']} 条，现在是 {len(assets)}")
    for index, asset in enumerate(assets):
        tag = f"资产[{index + 1}]"
        if not isinstance(asset, dict):
            errors.append(f"{tag}: 必须是对象")
            continue
        for field in ("title", "what", "why_valuable"):
            if not isinstance(asset.get(field), str) or not str(asset.get(field)).strip():
                errors.append(f"{tag}: {field} 不能为空")
        if not non_empty_strings(asset.get("how_to_use"), 4):
            errors.append(f"{tag}: how_to_use 需要 1-4 条非空用法")
        if "basis" in asset and asset.get("basis") is not None:
            check_refs(tag, asset.get("basis"))

    advice = judgment.get("structure_advice") or []
    if not isinstance(advice, list):
        errors.append("structure_advice 必须是列表")
        advice = []
    if len(advice) > limits["max_advice"]:
        errors.append(f"结构建议最多 {limits['max_advice']} 条，现在是 {len(advice)}")
    for index, entry in enumerate(advice):
        tag = f"结构建议[{index + 1}]"
        if not isinstance(entry, dict):
            errors.append(f"{tag}: 必须是对象")
            continue
        for field in ("title", "detail"):
            if not isinstance(entry.get(field), str) or not str(entry.get(field)).strip():
                errors.append(f"{tag}: {field} 不能为空")
    return errors


def esc(value):
    return html.escape(str(value if value is not None else ""))


def chart_payload(evidence):
    """图表数据只来自证据聚合，判断文件不参与，杜绝手填数字。"""
    extensions = [
        (item.get("extension", "?"), item.get("files", 0))
        for item in (evidence.get("structure", {}) or {}).get("extensions", [])[:6]
    ]
    heat = [(item.get("dir", "?"), item.get("files", 0)) for item in evidence.get("activity_heat", [])[:6]]
    heat_max = max((count for _, count in heat), default=0) or 1
    heat_total = sum(count for _, count in heat) or 1
    weekly = evidence.get("weekly_counts", [])
    return {
        "fileDist": {
            "labels": [name for name, _ in extensions],
            "data": [count for _, count in extensions],
        },
        "focusRadar": {
            "labels": [name for name, _ in heat],
            "data": [round(count / heat_max * 100) for _, count in heat],
        },
        "activityTrend": {
            "labels": [f"-{item.get('weeks_ago', 0)}周" for item in reversed(weekly)],
            "data": [item.get("files", 0) for item in reversed(weekly)],
        },
        "timeAllocation": {
            "labels": [name for name, _ in heat[:5]],
            "data": [round(count / heat_total * 100) for _, count in heat[:5]],
        },
    }


def kpi_html(evidence):
    counts = evidence.get("counts", {})

    def cell(label, value):
        return f'<div class="stat-item"><div class="stat-label">{esc(label)}</div><div class="stat-value">{esc(value)}</div></div>'

    disk_percent = (evidence.get("scan", {}).get("disk", {}) or {}).get("percent", "-")
    cells = [
        cell("近期文件", len(evidence.get("recent_files") or [])),
        cell("笔记总数", counts.get("obsidian_notes", 0)),
        cell("电子书", counts.get("ebooks", 0)),
        cell("桌面文件", counts.get("desktop_files", 0)),
        cell("应用数量", evidence.get("app_count", 0)),
    ]
    for vault in evidence.get("knowledge_bases") or []:
        cells.append(cell(f"{vault.get('app')} 笔记", vault.get("notes", 0)))
    cells.append(cell("磁盘使用", disk_percent))
    return "".join(cells)


def suggestion_card(item):
    badges = []
    kind = item.get("kind")
    if kind == "upgrade":
        badges.append('<span class="badge badge-upgrade">升级用法</span>')
    else:
        badges.append('<span class="badge">基础用法</span>')
    if item.get("quick_win"):
        badges.append('<span class="badge badge-win">快见效</span>')
    files = []
    for source in item.get("sources") or []:
        if not isinstance(source, dict):
            continue
        if is_metric_ref(source):
            files.append(f"指标 {source.get('ref')}")
        else:
            files.append("/".join(part for part in [source.get("parent"), source.get("name")] if part))
    apps = "、".join(str(app) for app in item.get("app_refs") or [])
    apps_html = f'<p><strong>相关应用：</strong>{esc(apps)}</p>' if apps else ""
    evidence_text = str(item.get("evidence") or "").strip()
    evidence_html = f'<p><strong>证据：</strong>{esc(evidence_text[:180])}</p>' if evidence_text else ""
    return (
        '<div class="suggestion-card">'
        f"<h3>{esc(item.get('activity'))}</h3>"
        f'<p class="badges">{"".join(badges)}</p>'
        f"<p><strong>AI 能替你做：</strong>{esc(item.get('ai_role'))}</p>"
        f'<p><strong>第一步：</strong>{esc(item.get("first_step"))}</p>'
        f"<p><strong>能省掉：</strong>{esc(item.get('expected_saving'))}</p>"
        f'<p><strong>为什么是现在：</strong>{esc(item.get("reason"))}</p>'
        f'<p><strong>用到的证据：</strong>{esc("、".join(files))}</p>'
        f"{apps_html}{evidence_html}"
        "</div>"
    )


def understanding_html(judgment):
    understanding = judgment.get("understanding") or {}
    icons = {
        "activities": ("📌", "主要活动类型"),
        "domains": ("🎯", "关注的主要领域"),
        "work_style": ("💼", "工作或学习方式"),
        "structure": ("📁", "文件结构特点"),
    }
    cards = []
    for key, (icon, label) in icons.items():
        points = understanding.get(key) or []
        if not points:
            continue
        items = "".join(f"<li>{esc(point.get('text'))}</li>" for point in points if isinstance(point, dict))
        cards.append(
            '<div class="suggestion-card">'
            f"<h3>{icon} {esc(label)}</h3><ul>{items}</ul></div>"
        )
    return "".join(cards)


def cadence_html(judgment):
    cadence = judgment.get("cadence") or {}
    icons = {"daily": ("🟢", "每日协作（轻量）"), "weekly": ("🟡", "每周协作（中等深度）"), "monthly": ("🔴", "每月协作（深度）")}
    blocks = []
    for period, (icon, label) in icons.items():
        block = cadence.get(period)
        if not isinstance(block, dict):
            continue
        items = "".join(f'<div class="timeline-item"><p>{esc(item)}</p></div>' for item in block.get("items") or [])
        blocks.append(
            '<div class="timeline-detailed">'
            f"<h3>{icon} {esc(label)}</h3>"
            f'<p style="color: var(--text-secondary); margin-bottom: 12px;">{esc(block.get("summary"))}</p>'
            f"{items}</div>"
        )
    return "".join(blocks)


def priority_block(entry, suggestion_map, rank_icon):
    item = suggestion_map.get(str(entry.get("id"))) or {}
    steps = "".join(f"<li>{esc(step)}</li>" for step in entry.get("how_to_start") or [])
    long_terms = "".join(f"<li>{esc(line)}</li>" for line in entry.get("long_term") or [])
    return (
        '<div class="priority-card">'
        f"<h3>{rank_icon} {esc(item.get('activity') or entry.get('id'))}</h3>"
        f'<div class="priority-section"><h4>为什么最有价值</h4><p>{esc(entry.get("why"))}</p></div>'
        f'<div class="priority-section"><h4>如何开始</h4><ul>{steps}</ul></div>'
        f'<div class="priority-section"><h4>可以带来什么长期帮助</h4><ul>{long_terms}</ul></div>'
        "</div>"
    )


def asset_html(judgment):
    cards = []
    for asset in judgment.get("assets") or []:
        uses = "".join(f"<li>{esc(line)}</li>" for line in asset.get("how_to_use") or [])
        cards.append(
            '<div class="suggestion-card">'
            f"<h3>💎 {esc(asset.get('title'))}</h3>"
            f'<p><strong>这是什么：</strong>{esc(asset.get("what"))}</p>'
            f'<p><strong>为什么有价值：</strong>{esc(asset.get("why_valuable"))}</p>'
            f"<ul>{uses}</ul></div>"
        )
    return "".join(cards)


def advice_html(judgment):
    cards = []
    for entry in judgment.get("structure_advice") or []:
        cards.append(
            '<div class="suggestion-card">'
            f"<h3>🔧 {esc(entry.get('title'))}</h3>"
            f'<p>{esc(entry.get("detail"))}</p></div>'
        )
    return "".join(cards)


def file_table(files, limit=30):
    rows = []
    for item in files[:limit]:
        skipped = str(item.get("body_skipped") or "")
        note = {"pdf": "（PDF 正文未读）", "xlsx": "（表格正文未读）", "too_large": "（文件太大未读）"}.get(skipped, "")
        rows.append(
            "<tr>"
            f"<td>{esc(item.get('name'))}{esc(note)}</td>"
            f"<td>{esc(item.get('parent'))}</td>"
            f"<td>{esc(item.get('mtime'))}</td>"
            "</tr>"
        )
    if not rows:
        return '<p class="muted">没有读到近期文件。</p>'
    return (
        '<table class="files"><thead><tr><th>文件</th><th>位置</th><th>修改时间</th></tr></thead>'
        f"<tbody>{''.join(rows)}</tbody></table>"
    )


def app_chips(apps, limit=60):
    if not apps:
        return '<p class="muted">没有收集到应用清单。</p>'
    chips = "".join(f'<span class="chip">{esc(name)}</span>' for name in apps[:limit])
    more = f'<span class="chip">+{len(apps) - limit} 个</span>' if len(apps) > limit else ""
    return f'<p class="chips">{chips}{more}</p>'


def kb_html(evidence):
    blocks = []
    for vault in evidence.get("knowledge_bases") or []:
        journals = vault.get("journals") or []
        journal_text = "、".join(
            f"「{j.get('dir')}」{j.get('files')} 篇/持续 {j.get('span_days')} 天" for j in journals
        )
        deep_names = "、".join(
            f"《{item.get('name')}》" for item in evidence.get("deep_reads") or []
        )
        parts = [
            f"<p><strong>{esc(vault.get('app'))} 知识库：</strong>{esc(vault.get('path'))}</p>",
            f'<p class="muted">笔记 {vault.get("notes", 0)} 篇，近 7 天改 {vault.get("recent_notes_7d", 0)} 篇</p>',
        ]
        if journal_text:
            parts.append(f'<p class="muted">日记习惯：{esc(journal_text)}</p>')
        if deep_names:
            parts.append(f'<p class="muted">深读自述：{esc(deep_names)}</p>')
        blocks.append('<div class="suggestion-card">' + "".join(parts) + "</div>")
    return "".join(blocks)


def render(evidence, judgment, template_text):
    scan = evidence.get("scan", {})
    has_judgment = judgment is not None
    counts = evidence.get("counts", {})

    if has_judgment:
        title = "AI 提效机会报告"
        diagnosis = judgment.get("diagnosis") or {}
        activities = diagnosis.get("activities") or []
        summary = str(diagnosis.get("summary") or "").strip()
        role_labels = [str(act.get("activity")) for act in activities if isinstance(act, dict)][:3]
        intro = (
            "从这次扫描看，你已经大量在用 AI。这份报告的重点不是教你从零开始，而是把零散的用法变成系统。"
            if judgment.get("persona") == "power"
            else "从这次扫描看，你最近在做下面这些事。标「还没用 AI」的，是最先值得尝试的地方。"
        )
        usage_rows = "".join(
            "<tr>"
            f"<td>{esc(act.get('activity'))}</td>"
            f'<td><span class="badge badge-{esc(act.get("ai_usage"))}">{esc(AI_USAGE_TEXT.get(act.get("ai_usage"), act.get("ai_usage")))}</span></td>'
            f"<td>{esc(act.get('time_note'))}</td>"
            "</tr>"
            for act in activities
            if isinstance(act, dict)
        )
        profile_body = (
            f'<div class="role">{esc(" · ".join(role_labels))}</div>'
            f"<p>{intro}</p>"
            + (f'<p class="callout"><strong>整体结论：</strong>{esc(summary)}</p>' if summary else "")
            + (
                '<table class="diag"><thead><tr><th>在做的事</th><th>AI 使用程度</th><th>时间占用（粗估）</th></tr></thead>'
                f"<tbody>{usage_rows}</tbody></table>"
                if usage_rows else ""
            )
        )
        suggestions_html = "".join(suggestion_card(item) for item in judgment.get("suggestions") or [])
        if not suggestions_html:
            suggestions_html = '<p class="muted">证据不足，这次没有生成建议。</p>'
        suggestion_map = {
            str(item.get("id")): item
            for item in judgment.get("suggestions") or []
            if isinstance(item, dict)
        }
        rank_icons = ["🥇", "🥈", "🥉"]
        priorities_html = "".join(
            priority_block(entry, suggestion_map, rank_icons[index] if index < 3 else "🎯")
            for index, entry in enumerate(judgment.get("priorities") or [])
        ) or '<p class="muted">证据不足，暂不排序。</p>'
        understanding_cards = understanding_html(judgment) or '<p class="muted">等待更充分的证据。</p>'
        cadence_blocks = cadence_html(judgment) or '<p class="muted">证据不足，暂不安排节奏。</p>'
        assets_blocks = asset_html(judgment) or '<p class="muted">这次没有发现明显的高价值资产。</p>'
        advice_blocks = advice_html(judgment) or '<p class="muted">文件结构暂时没有明显问题。</p>'
    else:
        title = "环境扫描 · 证据报告"
        profile_body = (
            "<p>证据已经收集完成。建议还没有生成：把证据文件交给本会话的 AI，"
            "按 SKILL.md 的判断准则写判断文件，再运行 generate-final-report.sh。</p>"
        )
        suggestions_html = '<p class="muted">等待 AI 判断。这一页不会用固定模板凑建议。</p>'
        priorities_html = '<p class="muted">等待 AI 判断。</p>'
        understanding_cards = '<p class="muted">等待 AI 判断。</p>'
        cadence_blocks = '<p class="muted">等待 AI 判断。</p>'
        assets_blocks = '<p class="muted">等待 AI 判断。</p>'
        advice_blocks = '<p class="muted">等待 AI 判断。</p>'

    charts = chart_payload(evidence)
    raw_payload = json.loads(json.dumps(evidence, ensure_ascii=False))
    for item in raw_payload.get("deep_reads") or []:
        item["text"] = f"（{item.get('line_count', 0)} 行正文，仅判断 AI 可读，报告不展示）"
    raw_json = html.escape(json.dumps(raw_payload, ensure_ascii=False, indent=2))
    chart_data_json = json.dumps(charts, ensure_ascii=False)
    kb_blocks = kb_html(evidence)
    deep_summary = (
        '<div class="suggestion-card"><h3>📖 深读的自述文档</h3>'
        + "".join(
            f'<p class="muted"><strong>{esc(item.get("name"))}</strong>（{esc(item.get("mtime"))}，{item.get("line_count", 0)} 行）</p>'
            for item in evidence.get("deep_reads") or []
        )
        + "</div>"
        if evidence.get("deep_reads")
        else ""
    )
    mapping = {
        "TITLE": esc(title),
        "VERSION": VERSION,
        "GENERATED_AT": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "SCAN_TIME": esc(scan.get("scan_time", "-")),
        "SCAN_MODE": esc(scan.get("scan_mode", "-")),
        "PLATFORM": esc(scan.get("platform", "-")),
        "NOTES_TOTAL": esc(counts.get("obsidian_notes", 0)),
        "PROFILE_BODY": profile_body,
        "KPI_HTML": kpi_html(evidence),
        "UNDERSTANDING_HTML": understanding_cards,
        "SUGGESTIONS_HTML": suggestions_html,
        "CADENCE_HTML": cadence_blocks,
        "PRIORITIES_HTML": priorities_html,
        "ASSETS_HTML": assets_blocks,
        "ADVICE_HTML": advice_blocks,
        "KB_HTML": kb_blocks,
        "DEEP_READS_HTML": deep_summary,
        "EVIDENCE_HTML": file_table(evidence.get("recent_files") or []),
        "APPS_HTML": app_chips(evidence.get("apps") or []),
        "RAW_JSON": raw_json,
        "CHART_DATA_JSON": chart_data_json,
    }
    rendered = template_text
    for key, value in mapping.items():
        rendered = rendered.replace("{{" + key + "}}", value)
    return rendered


def main():
    if len(sys.argv) < 2:
        print("用法: judgment.py validate <evidence.json> <judgment.json>", file=sys.stderr)
        print("      judgment.py render <evidence.json> [judgment.json] <template.html> <output.html>", file=sys.stderr)
        return 1
    command = sys.argv[1]
    if command == "validate":
        if len(sys.argv) < 4:
            print("用法: judgment.py validate <evidence.json> <judgment.json>", file=sys.stderr)
            return 1
        errors = validate(load_json(sys.argv[2]), load_json(sys.argv[3]))
        if errors:
            print(f"❌ 判断未通过校验，共 {len(errors)} 个问题:")
            for error in errors:
                print(f"  - {error}")
            return 1
        print("✅ 判断通过校验")
        return 0
    if command == "render":
        if len(sys.argv) == 6:
            evidence_path, judgment_path, template_path, output_path = sys.argv[2:6]
            judgment = load_json(judgment_path)
        elif len(sys.argv) == 5:
            evidence_path, template_path, output_path = sys.argv[2:5]
            judgment = None
        else:
            print("用法: judgment.py render <evidence.json> [judgment.json] <template.html> <output.html>", file=sys.stderr)
            return 1
        rendered = render(load_json(evidence_path), judgment, Path(template_path).read_text(encoding="utf-8"))
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        Path(output_path).write_text(rendered, encoding="utf-8")
        mode = "最终报告" if judgment is not None else "证据报告"
        print(f"✅ {mode}生成完成: {output_path}")
        return 0
    print(f"未知命令: {command}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
