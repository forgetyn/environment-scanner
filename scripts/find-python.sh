#!/bin/bash

# 选出扫描要用的 Python，只把绝对路径打到标准输出。
# 顺序：ENV_SCANNER_PYTHON → 已解压的私有运行环境 → 系统解释器 → 解压工具自带的压缩包。
# 测试可设 ENV_SCANNER_IGNORE_SYSTEM_PYTHON=1、ENV_SCANNER_RUNTIME_HOME、ENV_SCANNER_VENDOR_DIR。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="${ENV_SCANNER_VENDOR_DIR:-$REPO_ROOT/runtime/vendor}"
RUNTIME_HOME="${ENV_SCANNER_RUNTIME_HOME:-$HOME/.environment-scanner/runtime}"

is_store_stub() {
    local lower
    lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
        *windowsapps*) return 0 ;;
    esac
    return 1
}

probe() {
    local bin="$1"
    [ -n "$bin" ] || return 1
    [ -f "$bin" ] || return 1
    [ -x "$bin" ] || return 1
    if is_store_stub "$bin"; then
        return 1
    fi
    "$bin" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1
}

platform_id() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)
    case "$os" in
        Darwin)
            case "$arch" in
                arm64) printf '%s' "mac-arm64" ;;
                x86_64) printf '%s' "mac-x86_64" ;;
                *) return 1 ;;
            esac
            ;;
        MINGW*|MSYS*|CYGWIN*)
            case "$arch" in
                x86_64|amd64) printf '%s' "windows-amd64" ;;
                aarch64|arm64) printf '%s' "windows-arm64" ;;
                *) return 1 ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
}

manifest_value() {
    local key="$1"
    awk -v key="$key" '
        $0 ~ /^[[:space:]]*#/ { next }
        $1 == key { print; exit }
    ' "$VENDOR_DIR/manifest.txt"
}

fix_embeddable_pth() {
    local dest="$1"
    local pth base
    for pth in "$dest"/python*._pth; do
        [ -f "$pth" ] || continue
        base=$(basename "$pth")
        base="${base%._pth}.zip"
        printf '%s\n.\n\nimport site\n' "$base" > "$pth"
    done
}

sha256_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print tolower($1)}'
    else
        sha256sum "$1" | awk '{print tolower($1)}'
    fi
}

use_existing_private() {
    local id="$1"
    local line version rel dest marker
    [ -f "$VENDOR_DIR/manifest.txt" ] || return 1
    line=$(manifest_value "$id" || true)
    [ -n "$line" ] || return 1
    # shellcheck disable=SC2086
    set -- $line
    rel="$4"
    version=$(awk '$1 == "version" { print $2; exit }' "$VENDOR_DIR/manifest.txt")
    dest="$RUNTIME_HOME/$id"
    marker="$dest/VERSION"
    [ -f "$marker" ] || return 1
    [ "$(tr -d '[:space:]' < "$marker")" = "$version" ] || return 1
    probe "$dest/$rel" || return 1
    printf '%s\n' "$dest/$rel"
}

extract_private() {
    local id="$1"
    local line sha file rel strip archive actual version dest tmp py
    [ -f "$VENDOR_DIR/manifest.txt" ] || {
        echo "这台电脑没有可用的 Python，工具里也没有 ${id} 的运行环境。" >&2
        return 1
    }
    line=$(manifest_value "$id" || true)
    if [ -z "$line" ]; then
        echo "这台电脑没有可用的 Python，工具里也没有 ${id} 的运行环境。" >&2
        return 1
    fi
    # shellcheck disable=SC2086
    set -- $line
    sha=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
    file="$3"
    rel="$4"
    strip="$5"
    archive="$VENDOR_DIR/$file"
    if [ ! -f "$archive" ]; then
        echo "运行环境压缩包不存在: $file" >&2
        return 1
    fi
    actual=$(sha256_file "$archive")
    if [ "$actual" != "$sha" ]; then
        echo "运行环境压缩包校验失败，没有解压: $file" >&2
        return 1
    fi
    version=$(awk '$1 == "version" { print $2; exit }' "$VENDOR_DIR/manifest.txt")
    mkdir -p "$RUNTIME_HOME"
    tmp=$(mktemp -d "$RUNTIME_HOME/.extract.XXXXXX")
    if [ "$strip" = "0" ]; then
        tar -xzf "$archive" -C "$tmp"
    else
        tar -xzf "$archive" -C "$tmp" --strip-components="$strip"
    fi
    fix_embeddable_pth "$tmp"
    printf '%s\n' "$version" > "$tmp/VERSION"
    dest="$RUNTIME_HOME/$id"
    rm -rf "$dest"
    mv "$tmp" "$dest"
    py="$dest/$rel"
    if ! probe "$py"; then
        echo "解压后的 Python 无法运行: $py" >&2
        return 1
    fi
    printf '%s\n' "$py"
}

search_system() {
    local rest="$PATH"
    local dir name candidate
    while [ -n "$rest" ]; do
        dir="${rest%%:*}"
        case "$rest" in
            *:*) rest="${rest#*:}" ;;
            *) rest="" ;;
        esac
        [ -n "$dir" ] || continue
        for name in python3 python; do
            candidate="$dir/$name"
            if [ -f "$candidate" ] && [ -x "$candidate" ] && probe "$candidate"; then
                printf '%s\n' "$candidate"
                return 0
            fi
        done
    done
    return 1
}

main() {
    local id
    if [ -n "${ENV_SCANNER_PYTHON:-}" ]; then
        if probe "$ENV_SCANNER_PYTHON"; then
            printf '%s\n' "$ENV_SCANNER_PYTHON"
            return 0
        fi
        echo "ENV_SCANNER_PYTHON 指向的程序不能用: $ENV_SCANNER_PYTHON" >&2
        return 1
    fi
    if ! id=$(platform_id); then
        echo "这个系统没有自带的运行环境。" >&2
        return 1
    fi
    if use_existing_private "$id"; then
        return 0
    fi
    if [ "${ENV_SCANNER_IGNORE_SYSTEM_PYTHON:-}" != "1" ]; then
        if search_system; then
            return 0
        fi
    fi
    extract_private "$id"
}

main
