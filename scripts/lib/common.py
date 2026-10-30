#!/usr/bin/env python3
"""跨模块共享的小工具：噪声行判断、私钥识别、JSON 读写。"""

import json
import re
from pathlib import Path

SECRET_PATTERNS = (
    (re.compile(r"BEGIN\s+(?:[A-Z0-9]+\s+)*PRIVATE\s+KEY"), "private_key"),
    (re.compile(r"PuTTY-User-Key-File"), "private_key"),
    (
        re.compile(
            r"(?i)(?:^|[^A-Za-z0-9])(?:[A-Za-z0-9]+_)?[\"']?"
            r"(?:password|passwd|api_key|secret)[\"']?\s*[:=]"
        ),
        "credential_assignment",
    ),
    (re.compile(r"(?:密码|口令)\s*[:=：]"), "credential_assignment"),
)
def is_noise(text):
    if re.match(r"^#{1,6}\s", text):
        return True
    if re.match(r"^\|.*\|$", text):
        return True
    if re.match(r"^\*\*.*\*\*$", text):
        return True
    if re.match(r"^[-*_]{3,}$", text):
        return True
    return False


def secret_reason(text):
    if not text:
        return None
    # UTF-16 按错误编码读进来时，ASCII 之间会留下 NUL，先去掉再认。
    cleaned = text.replace("\x00", "")
    for pattern, reason in SECRET_PATTERNS:
        if pattern.search(cleaned):
            return reason
    return None


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, payload):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
