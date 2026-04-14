#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
RUNTIME_ROOT="$PROJECT_DIR/tools/pjarczak_bambu_linux_host/runtime/linux-x86_64"

find_host_bin() {
    local name="$1"
    local candidate=""
    for candidate in         "$PROJECT_DIR/build/src/Release/$name"         "$PROJECT_DIR/build/$name"         "$PROJECT_DIR/build/src/$name"
    do
        if [[ -f "$candidate" ]]; then
            printf '%s
' "$candidate"
            return 0
        fi
    done
    find "$PROJECT_DIR/build" -type f -name "$name" 2>/dev/null | head -n 1
}

collect_runtime_libs() {
    local host_bin="$1"
    ldd "$host_bin" | awk '
        /=>/ && $3 ~ /^\// { print $3 }
        /^\// { print $1 }
    ' | sort -u
}

copy_runtime_libs() {
    local host_abi1="$1"
    local host_abi0="$2"
    mkdir -p "$RUNTIME_ROOT"
    mapfile -t libs < <({ collect_runtime_libs "$host_abi1"; collect_runtime_libs "$host_abi0"; } | sort -u)
    local lib base
    for lib in "${libs[@]}"; do
        base="$(basename -- "$lib")"
        case "$base" in
            ld-linux*|libc.so.*|libm.so.*|libpthread.so.*|librt.so.*|libdl.so.*|libresolv.so.*|libnsl.so.*|libutil.so.*)
                continue
                ;;
        esac
        cp -Lf "$lib" "$RUNTIME_ROOT/"
    done
}

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "this packaging script currently produces linux-x86_64 runtime only" >&2
    exit 1
fi

HOST_ABI1="$(find_host_bin pjarczak_bambu_linux_host_abi1 || true)"
HOST_ABI0="$(find_host_bin pjarczak_bambu_linux_host_abi0 || true)"
if [[ -z "$HOST_ABI1" || ! -f "$HOST_ABI1" || -z "$HOST_ABI0" || ! -f "$HOST_ABI0" ]]; then
    echo "failed to find built pjarczak_bambu_linux_host_abi1/abi0 under $PROJECT_DIR/build" >&2
    echo "build them first in the full Orca Linux build context, for example:" >&2
    echo "  cmake --build build --config Release --target pjarczak_bambu_linux_host" >&2
    exit 1
fi

rm -rf "$RUNTIME_ROOT"
mkdir -p "$RUNTIME_ROOT"

cp -f "$PROJECT_DIR/tools/pjarczak_bambu_runtime/wsl/pjarczak_bambu_linux_host" "$RUNTIME_ROOT/pjarczak_bambu_linux_host"
cp -f "$HOST_ABI1" "$RUNTIME_ROOT/pjarczak_bambu_linux_host_abi1"
cp -f "$HOST_ABI0" "$RUNTIME_ROOT/pjarczak_bambu_linux_host_abi0"
chmod +x "$RUNTIME_ROOT/pjarczak_bambu_linux_host" "$RUNTIME_ROOT/pjarczak_bambu_linux_host_abi1" "$RUNTIME_ROOT/pjarczak_bambu_linux_host_abi0"

copy_runtime_libs "$HOST_ABI1" "$HOST_ABI0"

echo "linux host runtime packaged into:"
echo "  $RUNTIME_ROOT"
find "$RUNTIME_ROOT" -maxdepth 1 -type f | sort
