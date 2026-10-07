#!/usr/bin/env bash
#
# roundtrip_check.sh -- prove the rename is a *pure token substitution*.
#
#   ./tools/scripts/rename/roundtrip_check.sh [--block ecc] --upstream <dir>
#
# For every imported file this strips the Tessera prefix back off and diffs the
# result against the exact upstream blob recorded in revinfo/<block>.revinfo.yml.
# A clean run means the vendored RTL differs from caliptra-rtl by nothing but
# names -- no accidental logic edits, no dropped lines, no mangled strings.
#
# The only differences tolerated are `include redirections, which the import
# performs on purpose when it captures environment configuration macros into a
# block-private header.
#
# "Stripping the prefix" is not quite the whole inverse. A block may also carry
# a *stem* rewrite (src/hmac -> src/hmac512, hmac_core -> hmac512_core), which
# this has to undo as well or every file in that block reads as a difference.
# The policy is read back out of the block's own revinfo.yml rather than
# hard-coded, so the check stays an inverse of whatever the import declared.

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
    # The file lists live beside revinfo.yml. They are what says which files the
    # import actually took, i.e. the effect of excluded_globs/artifact_globs, so
    # they are read rather than re-derived from the upstream tree.
    manifest="$(dirname "$revinfo")/revinfo.manifest"
    [ -f "$manifest" ] || { echo "missing $manifest" >&2; rc=1; continue; }

    sha="$(sed -nE 's/^[[:space:]]*commit:[[:space:]]*"([0-9a-f]+)".*/\1/p' "$revinfo" | head -1)"
    prefix="$(sed -nE 's/^prefix:[[:space:]]*"(.*)"$/\1/p' "$revinfo" | head -1)"
    macro_prefix="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"

    # policy.stem_renames / policy.stem_keep, as recorded at import time
    stem_renames=()
    while IFS= read -r tok; do [ -n "$tok" ] && stem_renames+=("$tok"); done \
        < <(sed -nE '/^[[:space:]]*stem_renames:/,/^[[:space:]]*stem_keep:/ s/^[[:space:]]*-[[:space:]]*"([^"]+)".*/\1/p' "$revinfo")

    # Undo the stem on one name: hmac512_core -> hmac_core, hmac512.sv -> hmac.sv.
    # Only an exact match or a "<to>_" / "<to>." lead is inverted, which is the
    # same shape rc_stem applied going the other way.
    unstem() {
        local n="$1" r from to
        for r in "${stem_renames[@]}"; do
            from="${r%%=*}"; to="${r#*=}"
            case "$n" in
                "$to"|"$to"_*|"$to".*) printf '%s%s' "$from" "${n#"$to"}"; return 0 ;;
            esac
        done
        printf '%s' "$n"
    }

    stem_keep=()
    while IFS= read -r tok; do [ -n "$tok" ] && stem_keep+=("$tok"); done \
        < <(sed -nE '/^[[:space:]]*stem_keep:/,/^[[:space:]]*synth_subtrees:/ s/^[[:space:]]*-[[:space:]]*"([^"]+)".*/\1/p' "$revinfo")

    # Forward direction, for the "guess the renamed path" fallbacks below.
    restem() {
        local n="$1" r from to
        for r in "${stem_keep[@]}"; do
            case "$n" in "$r"|"$r"_*|"$r".*) printf '%s' "$n"; return 0 ;; esac
        done
        for r in "${stem_renames[@]}"; do
            from="${r%%=*}"; to="${r#*=}"
            case "$n" in
                "$from"|"$from"_*|"$from".*) printf '%s%s' "$to" "${n#"$from"}"; return 0 ;;
            esac
        done
        printf '%s' "$n"
    }

    # The full inverse of the import, applied to file *content*: undo the stem,
    # then drop the prefix. The stem half has to be *anchored*, because unlike
    # "tessera_" -- which can only ever be something this toolchain put there --
    # the string "hmac512" occurs in upstream of its own accord (hmac512_op in
    # the UVMF enums). Blindly inverting it would rewrite upstream's own names
    # and report a difference that is not there.
    #
    # The rename only ever produces the stem in two shapes, so only those two
    # are inverted:
    #   1. directly behind the prefix   tessera_hmac512_core -> hmac_core
    #                                   TESSERA_HMAC512_PARAM_PKG -> HMAC_PARAM_PKG
    #   2. as a whole path component    src/hmac512/rtl -> src/hmac/rtl
    #      (rc_fix_path_components strips the prefix back off these)
    # Anything else -- hmac512_op, hmac512 in a comment upstream wrote -- is
    # left exactly as found. Token boundaries make this perl rather than sed.
    uninvert() {
        perl -e '
            my ($prefix, $mprefix, $nstem, @rest) = @ARGV;
            my @stems = splice(@rest, 0, $nstem);
            open(my $in, "<", $rest[0]) or die "$rest[0]: $!";
            local $/; my $t = <$in>; close $in;
            for my $s (@stems) {
                my ($from, $to) = split /=/, $s, 2;
                next unless defined $to and length $to;
                my ($ufrom, $uto) = (uc $from, uc $to);
                $t =~ s/\Q$prefix$to\E(?![A-Za-z0-9])/$from/g;
                $t =~ s/\Q$mprefix$uto\E(?![A-Za-z0-9])/$ufrom/g;
                $t =~ s{(?<=/)\Q$to\E(?![A-Za-z0-9_])}{$from}g;
            }
            $t =~ s/\Q$prefix\E//g;
            $t =~ s/\Q$mprefix\E//g;
            print $t;
        ' "$prefix" "$macro_prefix" "${#stem_renames[@]}" ${stem_renames[@]+"${stem_renames[@]}"} "$1"
    }

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

    # upstream subtree -> Tessera subtree, as recorded at import time
    declare -A dirmap=()
    while IFS='|' read -r up ar; do
        [ -n "${ar:-}" ] || continue
        dirmap["$up"]="$ar"
    done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*\{[[:space:]]*upstream:[[:space:]]*"([^"]+)",[[:space:]]*tessera:[[:space:]]*"([^"]+)".*/\1|\2/p' "$revinfo")

    # dirmap keys whole directories, which is enough for the delivery tier
    # (staged one level deep) but not for collateral, which is recursive. Keep
    # the roots separately and resolve by longest matching prefix.
    roots_up=(); roots_tessera=()
    for up in "${!dirmap[@]}"; do
        roots_up+=("$up"); roots_tessera+=("${dirmap[$up]}")
    done
    remap_path() {
        local up="$1" i best=-1 blen=0
        for i in "${!roots_up[@]}"; do
            case "$up" in "${roots_up[$i]}"/*)
                [ "${#roots_up[$i]}" -gt "$blen" ] && { blen="${#roots_up[$i]}"; best="$i"; } ;;
            esac
        done
        if [ "$best" -ge 0 ]; then
            printf '%s%s\n' "${roots_tessera[$best]}" "${up#"${roots_up[$best]}"}"
        else
            printf '%s\n' "$up"
        fi
    }

    # Resolving upstream path -> Tessera path: both file names *and* directory
    # names may carry the prefix (UVMF names a directory after the package it
    # holds). Rather than re-deriving the rule, strip the prefix out of every
    # committed path and index by the result -- that is the upstream path.
    #
    # The stem is the second half of the inverse, and it has to be undone
    # *below* the Tessera subtree root, never on the root itself: the key is
    # compared against remap_path's output, which already speaks Tessera
    # directories. For src/hmac512/rtl/tessera_hmac512_core.sv the key wanted is
    # src/hmac512/rtl/hmac_core.sv -- Tessera directory, upstream file name.
    tessera_key() {
        local rp="${1//${prefix}/}" i best=-1 blen=0 root rest comp out
        for i in "${!roots_tessera[@]}"; do
            case "$rp" in "${roots_tessera[$i]}"/*)
                [ "${#roots_tessera[$i]}" -gt "$blen" ] && { blen="${#roots_tessera[$i]}"; best="$i"; } ;;
            esac
        done
        if [ "$best" -lt 0 ]; then printf '%s' "$rp"; return 0; fi
        root="${roots_tessera[$best]}"; rest="${rp#"$root"/}"; out="$root"
        local -a comps=()
        IFS='/' read -r -a comps <<< "$rest"
        for comp in "${comps[@]}"; do out="$out/$(unstem "$comp")"; done
        printf '%s' "$out"
    }

    declare -A pathmap=()
    while read -r _ rpath; do
        [ -n "${rpath:-}" ] || continue
        pathmap["$(tessera_key "$rpath")"]="$rpath"
    done < <(sed -nE '/^renamed_manifest:/,$ s/^[[:space:]]*-[[:space:]]*\{[[:space:]]*sha256:[[:space:]]*"([0-9a-f]+)",[[:space:]]*path:[[:space:]]*"(src\/[^"]+)".*/\1 \2/p' "$manifest")

    checked=0
    binchecked=0
    while read -r _ upath; do
        [ -n "${upath:-}" ] || continue
        base="$(basename "$upath")"
        updir="$(dirname "$upath")"

        # Where upstream put it is not where Tessera puts it, for any block that
        # relocates a subtree. Translate first, then look the result up.
        mapped="$(remap_path "$upath")"
        renamed=""
        if [ -n "${pathmap[$mapped]:-}" ]; then
            renamed="$DEST/${pathmap[$mapped]}"
        elif [ -f "$DEST/$(dirname "$mapped")/${prefix}$(restem "$base")" ]; then
            renamed="$DEST/$(dirname "$mapped")/${prefix}$(restem "$base")"
        elif [ -f "$DEST/$mapped" ]; then
            renamed="$DEST/$mapped"
        else
            tesseradir="${dirmap[$updir]:-}"
            [ -n "$tesseradir" ] && renamed="$DEST/$tesseradir/${prefix}$(restem "$base")"
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
        if diffout="$(diff <(uninvert "$renamed") \
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
    done < <(sed -nE '/^source_manifest:/,/^renamed_manifest:/ s/^[[:space:]]*-[[:space:]]*\{[[:space:]]*sha256:[[:space:]]*"([0-9a-f]+)",[[:space:]]*path:[[:space:]]*"([^"]+)".*/\1 \2/p' "$manifest")

    # Code-generator inputs are held to a *stronger* contract than everything
    # else: byte-identical, not merely naming-equivalent. The loop above strips
    # the prefix before diffing, so a yaml that had wrongly been prefixed would
    # strip straight back to the upstream text and pass unnoticed -- and the
    # next regeneration would then emit names that disagree with what is
    # committed. Compare these against upstream directly.
    local_gi=0
    while IFS= read -r gi; do
        [ -n "$gi" ] || continue
        # declared by upstream path; committed at the Tessera path for that subtree
        gi_tessera="$(remap_path "$gi")"
        if [ ! -f "$DEST/$gi_tessera" ]; then
            printf '  FAIL  generator input %s declared but not imported (looked for %s)\n' "$gi" "$gi_tessera"
            rc=1; continue
        fi
        if git -C "$UPSTREAM" show "$sha:$gi" 2>/dev/null | cmp -s - "$DEST/$gi_tessera"; then
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
