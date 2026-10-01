#!/usr/bin/env bash
#
# roundtrip_check.sh -- prove the rename is a *pure token substitution*.
#
#   ./tools/scripts/rename/roundtrip_check.sh [--block ecc] --upstream <dir>
#
# For every imported file this strips the ARCA prefix back off and diffs the
# result against the exact upstream blob recorded in revinfo/<block>.revinfo.yml.
# A clean run means the vendored RTL differs from caliptra-rtl by nothing but
# names -- no accidental logic edits, no dropped lines, no mangled strings.
#
# The only differences tolerated are `include redirections, which the import
# performs on purpose when it captures environment configuration macros into a
# block-private header.

set -euo pipefail

DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
UPSTREAM=""
BLOCK=""

while [ $# -gt 0 ]; do
    case "$1" in
        --upstream) UPSTREAM="${2:?}"; shift 2 ;;
        --block)    BLOCK="${2:?}";    shift 2 ;;
        --dest)     DEST="${2:?}";     shift 2 ;;
        --help|-h)  sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$UPSTREAM" ]; then
    UPSTREAM="$DEST/.upstream-cache/caliptra-rtl"
fi
[ -d "$UPSTREAM/.git" ] || { echo "need --upstream <caliptra-rtl checkout>" >&2; exit 2; }

blocks=()
if [ -n "$BLOCK" ]; then
    blocks=("$BLOCK")
else
    for r in "$DEST"/revinfo/*.revinfo.yml; do
        [ -e "$r" ] || continue
        blocks+=("$(basename "$r" .revinfo.yml)")
    done
fi

rc=0
for b in "${blocks[@]}"; do
    revinfo="$DEST/revinfo/$b.revinfo.yml"
    [ -f "$revinfo" ] || { echo "missing $revinfo" >&2; rc=1; continue; }

    sha="$(sed -nE 's/^[[:space:]]*commit:[[:space:]]*"([0-9a-f]+)".*/\1/p' "$revinfo" | head -1)"
    prefix="$(sed -nE 's/^prefix:[[:space:]]*"(.*)"$/\1/p' "$revinfo" | head -1)"
    macro_prefix="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"

    git -C "$UPSTREAM" cat-file -e "$sha^{commit}" 2>/dev/null || {
        echo "upstream checkout does not contain $sha (fetch it first)" >&2; rc=1; continue; }

    printf '\n== %s (upstream %s, prefix %s) ==\n' "$b" "${sha:0:12}" "$prefix"

    # upstream subtree -> ARCA subtree, as recorded at import time
    declare -A dirmap=()
    while IFS='|' read -r up ar; do
        [ -n "${ar:-}" ] || continue
        dirmap["$up"]="$ar"
    done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*\{[[:space:]]*upstream:[[:space:]]*"([^"]+)",[[:space:]]*arca:[[:space:]]*"([^"]+)".*/\1|\2/p' "$revinfo")

    # collateral subtrees are identity-mapped (imported in place), so their
    # ARCA directory is the upstream directory; only the basename may change.
    cdirs=()
    while read -r d; do
        [ -n "${d:-}" ] || continue
        cdirs+=("$d")
    done < <(sed -nE '/^[[:space:]]*collateral_dirs:/,/^[[:space:]]*filelist:/ s/^[[:space:]]*-[[:space:]]*(src\/.*)$/\1/p' "$revinfo")

    checked=0
    binchecked=0
    while read -r _ upath; do
        [ -n "${upath:-}" ] || continue
        base="$(basename "$upath")"
        updir="$(dirname "$upath")"

        arcadir="${dirmap[$updir]:-}"
        if [ -z "$arcadir" ]; then
            for d in "${cdirs[@]:-}"; do
                case "$upath" in "$d"/*) arcadir="$updir"; break ;; esac
            done
        fi
        [ -n "$arcadir" ] || { echo "  FAIL  no ARCA directory recorded for $updir"; rc=1; continue; }

        # the collateral tier renames a file only when its stem is itself a
        # renamed identifier, so accept either spelling
        renamed="$DEST/$arcadir/${prefix}${base}"
        [ -f "$renamed" ] || renamed="$DEST/$arcadir/${base}"
        [ -f "$renamed" ] || { echo "  FAIL  missing renamed file for $upath"; rc=1; continue; }

        if ! grep -Iq . "$renamed" 2>/dev/null; then
            # binary collateral: must be carried through byte-for-byte
            if git -C "$UPSTREAM" show "$sha:$upath" | cmp -s - "$renamed"; then
                binchecked=$((binchecked + 1))
            else
                printf '  FAIL  %s binary content changed\n' "$upath"
                rc=1
            fi
            continue
        fi

        if diffout="$(diff <(sed "s/${prefix}//g; s/${macro_prefix}//g" "$renamed") \
                          <(git -C "$UPSTREAM" show "$sha:$upath"))"; then
            checked=$((checked + 1))
            continue
        fi

        # tolerate deliberate `include redirections only
        if [ -z "$(printf '%s\n' "$diffout" | grep -E '^[<>]' | grep -vE '`include')" ]; then
            printf '  ok    %s (include redirected on purpose)\n' "$upath"
            checked=$((checked + 1))
        else
            printf '  FAIL  %s differs beyond renaming:\n' "$upath"
            printf '%s\n' "$diffout" | sed 's/^/        /'
            rc=1
        fi
    done < <(sed -nE '/^source_manifest:/,/^renamed_manifest:/ s/^[[:space:]]*-[[:space:]]*\{[[:space:]]*sha256:[[:space:]]*"([0-9a-f]+)",[[:space:]]*path:[[:space:]]*"(src\/[^"]+)".*/\1 \2/p' "$revinfo")

    [ "$binchecked" -eq 0 ] || printf '  ok    %d binary file(s) carried byte-for-byte\n' "$binchecked"
    printf '  -- %d file(s) round-tripped\n' "$checked"
    [ "$checked" -gt 0 ] || { echo "  FAIL  nothing checked"; rc=1; }
done

printf '\n'
if [ "$rc" -ne 0 ]; then
    echo "roundtrip_check: FAILED"
else
    echo "roundtrip_check: imported RTL differs from upstream by naming only"
fi
exit $rc
