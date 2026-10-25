#!/usr/bin/env python3
"""跨模块共享的小工具：噪声行判断、私钥识别、JSON 读写。"""

import json
import re
from pathlib import Path

SECRET_PATTERNS = (
    (re.compile(r"BEGIN (?:OPENSSH |RSA )?PRIVATE KEY"), "private_key"),
    (re.compile(r"(?i)\b(?:password|passwd|api_key|secret)\s*[:=]\s*\S+"), "credential_assignment"),
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
    for pattern, reason in SECRET_PATTERNS:
        if pattern.search(text):
            return reason
    return None


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path, payload):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
