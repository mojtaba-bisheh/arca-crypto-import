#!/usr/bin/env bash
#
# verify_import.sh -- structural checks on an imported, renamed crypto block.
#
#   ./tools/scripts/rename/verify_import.sh [--block ecc] [--dest <repo root>]
#
# With no --block, every block listed under revinfo/ is checked.
#
# These checks are deliberately *structural*, not semantic: no SystemVerilog
# parser is assumed to be present on a developer machine. The GitHub Actions
# workflow in .github/workflows/lint.yml additionally runs a real SV front end
# (slang / verilator --lint-only) over the generated filelists.

set -euo pipefail

DEST=""
BLOCK=""
PREFIX=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dest)   DEST="${2:?}";   shift 2 ;;
        --block)  BLOCK="${2:?}";  shift 2 ;;
        --prefix) PREFIX="${2:?}"; shift 2 ;;
        --help|-h)
            sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$DEST" ]; then
    DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

# Headers that ARCA supplies as a shared, separately version-pinned platform
# library. `include of these from a vendored block is expected and allowed.
PLATFORM_HEADERS=(
    "kv_macros.svh"
    "kv_defines.svh"
    "caliptra_prim_assert.sv"
    "caliptra_sva.svh"
    "uvm_macros.svh"
)

FAILURES=0
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
ok()   { printf '  ok    %s\n' "$*"; }

verify_block() {
    local block="$1"
    local rtl="$DEST/rtl/$block"
    local revinfo="$DEST/revinfo/$block.revinfo.yml"
    local map="$DEST/revinfo/$block.map"
    local prefix="$PREFIX" macro_prefix filelist

    printf '\n== %s ==\n' "$block"

    [ -d "$rtl" ]      || { fail "rtl/$block missing"; return; }
    [ -f "$revinfo" ]  || { fail "revinfo/$block.revinfo.yml missing"; return; }
    [ -f "$map" ]      || { fail "revinfo/$block.map missing"; return; }

    if [ -z "$prefix" ]; then
        prefix="$(sed -nE 's/^prefix:[[:space:]]*"(.*)"$/\1/p' "$revinfo" | head -1)"
    fi
    [ -n "$prefix" ] || { fail "could not determine prefix"; return; }
    macro_prefix="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"

    local files
    mapfile -t files < <(cd "$rtl" && ls *.sv *.svh *.v 2>/dev/null | sort || true)
    [ "${#files[@]}" -gt 0 ] || { fail "no sources in rtl/$block"; return; }

    # 1. every file name carries the prefix
    local f bad=0
    for f in "${files[@]}"; do
        case "$f" in "$prefix"*) ;; *) fail "unprefixed file name: $f"; bad=1 ;; esac
    done
    [ "$bad" -eq 0 ] && ok "all ${#files[@]} file names carry '$prefix'"

    # 2. every declaration carries the prefix
    bad=0
    while IFS= read -r decl; do
        [ -n "$decl" ] || continue
        local name="${decl##* }"
        case "$name" in "$prefix"*) ;; *) fail "unprefixed declaration: $decl"; bad=1 ;; esac
    done < <(cd "$rtl" && grep -hoE '^[[:space:]]*(module|package|interface)[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*' "${files[@]}" \
             | sed -E 's/^[[:space:]]*//; s/[[:space:]]+/ /')
    [ "$bad" -eq 0 ] && ok "all module/package/interface declarations carry '$prefix'"

    # 3. every `define carries the macro prefix
    bad=0
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$name" in "$macro_prefix"*) ;; *) fail "unprefixed \`define: $name"; bad=1 ;; esac
    done < <(cd "$rtl" && grep -hoE '^[[:space:]]*`define[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*' "${files[@]}" \
             | sed -E 's/.*`define[[:space:]]+//')
    [ "$bad" -eq 0 ] && ok "all \`define macros carry '$macro_prefix'"

    # 4. no double prefixing (idempotency of the rename engine)
    if (cd "$rtl" && grep -qE "(${prefix}){2}|(${macro_prefix}){2}" "${files[@]}"); then
        (cd "$rtl" && grep -nE "(${prefix}){2}|(${macro_prefix}){2}" "${files[@]}" | head -5)
        fail "double-prefixed identifiers present"
    else
        ok "no double-prefixed identifiers"
    fi

    # 5. no original (unprefixed) block identifier survives anywhere
    bad=0
    local kind orig new
    while IFS=$'\t' read -r kind orig new; do
        [ -n "${new:-}" ] || continue
        [ "$kind" = "file" ] && continue
        if (cd "$rtl" && perl -ne 'exit 0 if /(?<![A-Za-z0-9_\$\\])\Q'"$orig"'\E(?![A-Za-z0-9_\$])/; END{exit 1}' "${files[@]}"); then
            fail "original identifier still present: $orig"
            bad=1
        fi
    done < <(grep -vE '^\s*(#|$)' "$map")
    [ "$bad" -eq 0 ] && ok "no unprefixed block identifiers remain"

    # 6. reverse collisions in the map
    if [ "$(cut -f3 "$map" | grep -vE '^\s*$' | sort | uniq -d | wc -l)" -ne 0 ]; then
        cut -f3 "$map" | sort | uniq -d | head -5
        fail "two originals map onto the same renamed identifier"
    else
        ok "rename map is injective"
    fi

    # 7. every `include target resolves
    bad=0
    local inc
    while IFS= read -r inc; do
        [ -n "$inc" ] || continue
        [ -f "$rtl/$inc" ] && continue
        local allowed=0 p
        for p in "${PLATFORM_HEADERS[@]}"; do [ "$inc" = "$p" ] && allowed=1; done
        if [ "$allowed" -eq 1 ]; then
            printf '  note  `include "%s" resolved from the shared ARCA platform library\n' "$inc"
        else
            fail "unresolved \`include target: $inc"
            bad=1
        fi
    done < <(cd "$rtl" && grep -hoE '^[[:space:]]*`include[[:space:]]+"[^"]+"' "${files[@]}" \
             | sed -E 's/.*"([^"]+)".*/\1/' | sort -u)
    [ "$bad" -eq 0 ] && ok "all \`include targets resolve"

    # 8. filelist is complete and points at real files
    filelist="$(sed -nE 's#^[[:space:]]*filelist:[[:space:]]*rtl/[^/]+/(.*)$#\1#p' "$revinfo" | head -1)"
    if [ -z "$filelist" ] || [ ! -f "$rtl/$filelist" ]; then
        fail "filelist missing"
    else
        bad=0
        local n=0
        while IFS= read -r line; do
            line="${line##*/}"
            [ -f "$rtl/$line" ] || { fail "filelist entry not found: $line"; bad=1; }
            n=$((n + 1))
        done < <(grep -vE '^\s*(//|\+|$)' "$rtl/$filelist")
        # every source must be referenced by the filelist
        for f in "${files[@]}"; do
            [ "$f" = "$filelist" ] && continue
            grep -q "/$f\$" "$rtl/$filelist" || { fail "source not in filelist: $f"; bad=1; }
        done
        [ "$bad" -eq 0 ] && ok "filelist covers $n file(s), all resolve"
    fi

    # 9. committed files still match the revinfo manifest (drift detection)
    bad=0
    local sha path
    while read -r sha path; do
        [ -n "${path:-}" ] || continue
        if [ ! -f "$DEST/$path" ]; then
            fail "manifest references missing file: $path"; bad=1; continue
        fi
        if [ "$(sha256sum "$DEST/$path" | cut -d' ' -f1)" != "$sha" ]; then
            fail "file modified since import: $path"; bad=1
        fi
    done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*\{[[:space:]]*sha256:[[:space:]]*"([0-9a-f]+)",[[:space:]]*path:[[:space:]]*"(rtl\/[^"]+)".*/\1 \2/p' "$revinfo")
    [ "$bad" -eq 0 ] && ok "renamed manifest matches working tree"
}

if [ -n "$BLOCK" ]; then
    verify_block "$BLOCK"
else
    found=0
    for r in "$DEST"/revinfo/*.revinfo.yml; do
        [ -e "$r" ] || continue
        found=1
        b="$(basename "$r" .revinfo.yml)"
        verify_block "$b"
    done
    [ "$found" -eq 1 ] || { echo "no imported blocks found under $DEST/revinfo" >&2; exit 1; }
fi

printf '\n'
if [ "$FAILURES" -ne 0 ]; then
    printf 'verify_import: %d check(s) FAILED\n' "$FAILURES"
    exit 1
fi
printf 'verify_import: all checks passed\n'
