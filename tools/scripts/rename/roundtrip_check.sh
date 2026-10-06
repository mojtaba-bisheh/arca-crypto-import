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

# shellcheck source=revinfo_lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/revinfo_lib.sh"

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
# a linked worktree has .git as a file, and a worktree is how you check out a
# second branch of the same clone -- which blocks that only exist on `future`
# need.
git -C "$UPSTREAM" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "need --upstream <caliptra-rtl checkout>" >&2; exit 2; }

blocks=()
if [ -n "$BLOCK" ]; then
    blocks=("$BLOCK")
else
    while read -r b _; do blocks+=("$b"); done < <(ri_find "$DEST")
fi

rc=0
for b in "${blocks[@]}"; do
    revinfo="$(ri_path "$DEST" "$b" || true)"
    [ -f "$revinfo" ] || { echo "missing $revinfo" >&2; rc=1; continue; }

    sha="$(sed -nE 's/^[[:space:]]*commit:[[:space:]]*"([0-9a-f]+)".*/\1/p' "$revinfo" | head -1)"
    prefix="$(sed -nE 's/^prefix:[[:space:]]*"(.*)"$/\1/p' "$revinfo" | head -1)"
    macro_prefix="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"

    git -C "$UPSTREAM" cat-file -e "$sha^{commit}" 2>/dev/null || {
        echo "upstream checkout does not contain $sha (fetch it first)" >&2; rc=1; continue; }

    # A block may vendor from more than one repository. ABR takes its coverage
    # bind from caliptra-rtl and all 153 RTL files from the adams-bridge
    # submodule, which has its own history -- so "what did this look like
    # upstream" has to be asked of the right repo at the right sha.
    sub_paths=(); sub_shas=()
    while IFS='|' read -r sp ssha; do
        [ -n "${ssha:-}" ] || continue
        sub_paths+=("$sp"); sub_shas+=("$ssha")
        git -C "$UPSTREAM/$sp" cat-file -e "$ssha^{commit}" 2>/dev/null || {
            echo "submodule $sp does not contain $ssha (git submodule update --init?)" >&2
            rc=1; }
    done < <(sed -nE '/^  submodules:/,/^  subtrees:/{
                 s/^[[:space:]]*-[[:space:]]*path:[[:space:]]*"([^"]+)".*/P \1/p
                 s/^[[:space:]]*commit:[[:space:]]*"([0-9a-f]+)".*/C \1/p
             }' "$revinfo" | paste -d'|' - - | sed -E 's/^P ([^|]*)\|C (.*)$/\1|\2/')

    # repo + sha to ask about an upstream path
    upstream_repo_for() {
        local up="$1" i
        for i in "${!sub_paths[@]}"; do
            case "$up" in "${sub_paths[$i]}"/*)
                printf '%s\t%s\t%s\n' "$UPSTREAM/${sub_paths[$i]}" "${sub_shas[$i]}" \
                       "${up#"${sub_paths[$i]}"/}"
                return 0 ;;
            esac
        done
        printf '%s\t%s\t%s\n' "$UPSTREAM" "$sha" "$up"
    }

    printf '\n== %s (upstream %s, prefix %s) ==\n' "$b" "${sha:0:12}" "$prefix"

    # upstream subtree -> ARCA subtree, as recorded at import time
    declare -A dirmap=()
    while IFS='|' read -r up ar; do
        [ -n "${ar:-}" ] || continue
        dirmap["$up"]="$ar"
    done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*\{[[:space:]]*upstream:[[:space:]]*"([^"]+)",[[:space:]]*arca:[[:space:]]*"([^"]+)".*/\1|\2/p' "$revinfo")

    # dirmap keys whole directories, which is enough for the delivery tier
    # (staged one level deep) but not for collateral, which is recursive. Keep
    # the roots separately and resolve by longest matching prefix.
    roots_up=(); roots_arca=()
    for up in "${!dirmap[@]}"; do
        roots_up+=("$up"); roots_arca+=("${dirmap[$up]}")
    done
    remap_path() {
        local up="$1" i best=-1 blen=0
        for i in "${!roots_up[@]}"; do
            case "$up" in "${roots_up[$i]}"/*)
                [ "${#roots_up[$i]}" -gt "$blen" ] && { blen="${#roots_up[$i]}"; best="$i"; } ;;
            esac
        done
        if [ "$best" -ge 0 ]; then
            printf '%s%s\n' "${roots_arca[$best]}" "${up#"${roots_up[$best]}"}"
        else
            printf '%s\n' "$up"
        fi
    }

    # Resolving upstream path -> ARCA path: both file names *and* directory
    # names may carry the prefix (UVMF names a directory after the package it
    # holds). Rather than re-deriving the rule, strip the prefix out of every
    # committed path and index by the result -- that is the upstream path.
    declare -A pathmap=()
    while read -r _ rpath; do
        [ -n "${rpath:-}" ] || continue
        pathmap["${rpath//${prefix}/}"]="$rpath"
    done < <(sed -nE '/^renamed_manifest:/,$ s/^[[:space:]]*-[[:space:]]*\{[[:space:]]*sha256:[[:space:]]*"([0-9a-f]+)",[[:space:]]*path:[[:space:]]*"(src\/[^"]+)".*/\1 \2/p' "$revinfo")

    checked=0
    binchecked=0
    while read -r _ upath; do
        [ -n "${upath:-}" ] || continue
        base="$(basename "$upath")"
        updir="$(dirname "$upath")"

        # Where upstream put it is not where ARCA puts it, for any block that
        # relocates a subtree. Translate first, then look the result up.
        mapped="$(remap_path "$upath")"
        renamed=""
        if [ -n "${pathmap[$mapped]:-}" ]; then
            renamed="$DEST/${pathmap[$mapped]}"
        elif [ -f "$DEST/$(dirname "$mapped")/${prefix}${base}" ]; then
            renamed="$DEST/$(dirname "$mapped")/${prefix}${base}"
        elif [ -f "$DEST/$mapped" ]; then
            renamed="$DEST/$mapped"
        else
            arcadir="${dirmap[$updir]:-}"
            [ -n "$arcadir" ] && renamed="$DEST/$arcadir/${prefix}${base}"
        fi
        [ -n "$renamed" ] && [ -f "$renamed" ] || { echo "  FAIL  missing renamed file for $upath"; rc=1; continue; }

        if ! grep -Iq . "$renamed" 2>/dev/null; then
            # binary collateral: must be carried through byte-for-byte
            IFS=$'\t' read -r urepo usha urel < <(upstream_repo_for "$upath")
            if git -C "$urepo" show "$usha:$urel" | cmp -s - "$renamed"; then
                binchecked=$((binchecked + 1))
            else
                printf '  FAIL  %s binary content changed\n' "$upath"
                rc=1
            fi
            continue
        fi

        IFS=$'\t' read -r urepo usha urel < <(upstream_repo_for "$upath")
        if diffout="$(diff <(sed "s/${prefix}//g; s/${macro_prefix}//g" "$renamed") \
                          <(git -C "$urepo" show "$usha:$urel"))"; then
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
    done < <(sed -nE '/^source_manifest:/,/^renamed_manifest:/ s/^[[:space:]]*-[[:space:]]*\{[[:space:]]*sha256:[[:space:]]*"([0-9a-f]+)",[[:space:]]*path:[[:space:]]*"([^"]+)".*/\1 \2/p' "$revinfo")

    # Code-generator inputs are held to a *stronger* contract than everything
    # else: byte-identical, not merely naming-equivalent. The loop above strips
    # the prefix before diffing, so a yaml that had wrongly been prefixed would
    # strip straight back to the upstream text and pass unnoticed -- and the
    # next regeneration would then emit names that disagree with what is
    # committed. Compare these against upstream directly.
    local_gi=0
    while IFS= read -r gi; do
        [ -n "$gi" ] || continue
        if [ ! -f "$DEST/$gi" ]; then
            printf '  FAIL  generator input %s declared but not imported\n' "$gi"; rc=1; continue
        fi
        if git -C "$UPSTREAM" show "$sha:$gi" 2>/dev/null | cmp -s - "$DEST/$gi"; then
            local_gi=$((local_gi + 1))
        else
            printf '  FAIL  generator input %s is not byte-identical to upstream\n' "$gi"
            printf '        regeneration would diverge from what is committed\n'
            rc=1
        fi
    done < <(sed -nE '/^[[:space:]]*generator_inputs:/,/^[[:space:]]*keep_list:/ s/^[[:space:]]*-[[:space:]]*"([^"]+)".*/\1/p' "$revinfo")
    [ "$local_gi" -eq 0 ] || printf '  ok    %d generator input(s) byte-identical to upstream\n' "$local_gi"

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
