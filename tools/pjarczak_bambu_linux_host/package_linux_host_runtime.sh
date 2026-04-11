#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
RUNTIME_ROOT="$PROJECT_DIR/tools/pjarczak_bambu_linux_host/runtime/linux-x86_64"
RUNTIME_LIB_DIR="$RUNTIME_ROOT/pjarczak_bambu_linux_host.runtime"

find_host_bin() {
    if [[ $# -gt 0 && -n "${1:-}" ]]; then
        if [[ -f "$1" ]]; then
            printf '%s\n' "$1"
            return 0
        fi
        if [[ -d "$1" ]]; then
            find "$1" -type f -name pjarczak_bambu_linux_host | head -n 1
            return 0
        fi
    fi

    local candidate=""
    for candidate in \
        "$PROJECT_DIR/build/src/Release/pjarczak_bambu_linux_host" \
        "$PROJECT_DIR/build/pjarczak_bambu_linux_host" \
        "$PROJECT_DIR/build/src/pjarczak_bambu_linux_host"
    do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    find "$PROJECT_DIR/build" -type f -name pjarczak_bambu_linux_host 2>/dev/null | head -n 1
}

copy_runtime_libs() {
    local host_bin="$1"
    mkdir -p "$RUNTIME_LIB_DIR"

    mapfile -t libs < <(
        ldd "$host_bin" | awk '
            /=>/ && $3 ~ /^\// { print $3 }
            /^\// { print $1 }
        ' | sort -u
    )

    local lib=""
    local base=""
    for lib in "${libs[@]}"; do
        base="$(basename -- "$lib")"
        case "$base" in
            ld-linux*|libc.so.*|libm.so.*|libpthread.so.*|librt.so.*|libdl.so.*|libresolv.so.*|libnsl.so.*|libutil.so.*|libgcc_s.so.*)
                continue
                ;;
        esac
        cp -Lf "$lib" "$RUNTIME_LIB_DIR/"
    done
}

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "this packaging script currently produces linux-x86_64 runtime only" >&2
    exit 1
fi

HOST_BIN="$(find_host_bin "${1:-}" || true)"
if [[ -z "$HOST_BIN" || ! -f "$HOST_BIN" ]]; then
    echo "failed to find built pjarczak_bambu_linux_host under $PROJECT_DIR/build" >&2
    echo "build it first in the full Orca Linux build context, for example:" >&2
    echo "  cmake --build build --config Release --target pjarczak_bambu_linux_host" >&2
    exit 1
fi

rm -rf "$RUNTIME_ROOT"
mkdir -p "$RUNTIME_ROOT" "$RUNTIME_LIB_DIR"

cp -f "$HOST_BIN" "$RUNTIME_ROOT/pjarczak_bambu_linux_host"
chmod +x "$RUNTIME_ROOT/pjarczak_bambu_linux_host"

copy_runtime_libs "$HOST_BIN"

echo "linux host runtime packaged into:"
echo "  $RUNTIME_ROOT"
