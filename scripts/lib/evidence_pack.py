#!/usr/bin/env python3
"""把计数、近期文档样本和应用清单合并成一份证据文件，供 AI 判断使用。

除了合并原始产物，还计算几个结构信号（活动热度、周分布、扩展名分布、
AI 使用痕迹），让判断层能看见整体结构，而不只是单个文件片段。
"""

import argparse
import re
import sys
import time
from datetime import datetime
from pathlib import Path

from common import load_json, write_json

VERSION = "4.3.0"

AI_TEXT_MARKERS = (
    (re.compile(r"\bAI\b"), "AI"),
    (re.compile(r"人工智能"), "人工智能"),
    (re.compile(r"\b(?:GPT|Claude|Kimi|Gemini|DeepSeek|Copilot|Opus|FunASR)\b", re.I), "模型/工具名"),
    (re.compile(r"智能体|agent", re.I), "智能体/agent"),
    (re.compile(r"提示词|prompt", re.I), "提示词/prompt"),
    (re.compile(r"skill", re.I), "skill"),
    (re.compile(r"自动化"), "自动化"),
    (re.compile(r"引擎[:：]"), "引擎"),
)
AI_APP_KEYWORDS = (
    "chatgpt", "claude", "cursor", "codex", "zcode", "trae",
    "grok", "deepseek", "doubao", "kimi", "gemini", "copilot",
)
WEEK_SECONDS = 7 * 86400
HEAT_LIMIT = 10
WEEK_BUCKETS = 26


def merged_warnings(parts):
    seen = set()
    merged = []
    for part in parts:
        for item in part if isinstance(part, list) else []:
            if item not in seen:
                seen.add(item)
                merged.append(item)
    return merged


def activity_heat(files, limit=HEAT_LIMIT):
    now = time.time()
    groups = {}
    for item in files:
        key = str(item.get("parent_name") or "")
        if not key:
            continue
        group = groups.setdefault(key, {"dir": key, "files": 0, "newest": 0.0})
        group["files"] += 1
        group["newest"] = max(group["newest"], float(item.get("mtime_epoch") or 0))
    ranked = sorted(groups.values(), key=lambda g: (g["files"], g["newest"]), reverse=True)[:limit]
    for group in ranked:
        group["last_active_days"] = round((now - group["newest"]) / 86400, 1)
        del group["newest"]
    return ranked


def weekly_counts(files, weeks=WEEK_BUCKETS):
    now = time.time()
    buckets = {}
    for item in files:
        mtime = float(item.get("mtime_epoch") or 0)
        if mtime <= 0:
            continue
        weeks_ago = int((now - mtime) // WEEK_SECONDS)
        if weeks_ago >= weeks:
            continue
        buckets[weeks_ago] = buckets.get(weeks_ago, 0) + 1
    return [{"weeks_ago": key, "label": f"近第{key + 1}周", "files": buckets[key]} for key in sorted(buckets)]


def sample_extensions(files, limit=8):
    counts = {}
    for item in files:
        suffix = str(item.get("extension") or "(无扩展名)")
        counts[suffix] = counts.get(suffix, 0) + 1
    ranked = sorted(counts.items(), key=lambda kv: kv[1], reverse=True)[:limit]
    return [{"extension": name, "files": count} for name, count in ranked]


def ai_usage_signals(files, apps):
    marker_counts = {}
    marker_files = 0
    for item in files:
        text = f"{item.get('heading') or ''}\n{item.get('excerpt') or ''}"
        hit = False
        for pattern, label in AI_TEXT_MARKERS:
            found = len(pattern.findall(text))
            if found:
                hit = True
                marker_counts[label] = marker_counts.get(label, 0) + found
        if hit:
            marker_files += 1
    ai_apps = [
        app for app in apps
        if any(keyword in str(app).casefold() for keyword in AI_APP_KEYWORDS)
    ]
    return {
        "marker_files": marker_files,
        "file_ratio": round(marker_files / len(files), 4) if files else 0.0,
        "markers": dict(sorted(marker_counts.items(), key=lambda kv: kv[1], reverse=True)),
        "ai_apps": ai_apps,
    }


def build_evidence(data, samples, apps, kb=None):
    files = samples.get("files") or []
    rejected = samples.get("rejected_documents") or []
    app_names = apps.get("apps") or []
    kb = kb or {}
    counts = {
        key: data.get("files", {}).get(key, 0)
        for key in (
            "obsidian_notes",
            "ebooks",
            "desktop_files",
            "desktop_dirs",
            "recent_notes_7d",
        )
    }
    return {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "version": VERSION,
        "scan": {
            "scan_time": data.get("scan_time", "-"),
            "scan_mode": data.get("scan_mode", "-"),
            "platform": data.get("platform", "-"),
            "system": data.get("system", {}),
            "disk": data.get("disk", {}),
        },
        "counts": counts,
        "storage": data.get("storage", {}),
        "structure": data.get("structure") or {},
        "recent_files": files,
        "rejected_documents": rejected,
        "apps": app_names,
        "app_count": len(app_names),
        "app_sources": apps.get("sources") or [],
        "sample_recent_days": samples.get("recent_days"),
        "activity_heat": activity_heat(files),
        "weekly_counts": weekly_counts(files),
        "sample_extensions": sample_extensions(files),
        "ai_usage_signals": ai_usage_signals(files, app_names),
        "knowledge_bases": kb.get("knowledge_bases") or [],
        "deep_reads": kb.get("deep_reads") or [],
        "rejected_deep_reads": kb.get("rejected_deep_reads") or [],
        "scan_warnings": merged_warnings(
            [
                data.get("scan_warnings"),
                samples.get("scan_warnings"),
                apps.get("scan_warnings"),
                kb.get("scan_warnings"),
            ]
        ),
        "zero_signal": not files and not app_names,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True)
    parser.add_argument("--samples", required=True)
    parser.add_argument("--apps", default="")
    parser.add_argument("--kb", default="")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    data = load_json(args.data)
    samples = load_json(args.samples)
    apps = load_json(args.apps) if args.apps and Path(args.apps).is_file() else {}
    kb = load_json(args.kb) if args.kb and Path(args.kb).is_file() else {}
    evidence = build_evidence(data, samples, apps, kb)
    write_json(args.output, evidence)
    signals = evidence["ai_usage_signals"]
    print(f"证据文件: {args.output}")
    print(
        f"近期文件: {len(evidence['recent_files'])}  应用: {evidence['app_count']}  "
        f"知识库: {len(evidence['knowledge_bases'])}  深读自述: {len(evidence['deep_reads'])}  "
        f"AI痕迹文件: {signals['marker_files']}  零信号: {evidence['zero_signal']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
