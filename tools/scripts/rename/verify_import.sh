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
# workflow in .github/workflows/checks.yml additionally runs a real SV front end
# (slang / verilator --lint-only) over the generated filelists.

set -euo pipefail

# shellcheck source=revinfo_lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/revinfo_lib.sh"

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
    "caliptra_prim_module_name_macros.svh"
    "caliptra_reg_field_defines.svh"
    "caliptra_sva.svh"
    "uvm_macros.svh"
)

FAILURES=0
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
ok()   { printf '  ok    %s\n' "$*"; }

verify_block() {
    local block="$1"
    local revinfo map
    revinfo="$(ri_path "$DEST" "$block" || true)"
    map="${revinfo%/*}/revinfo.map"
    local prefix="$PREFIX" macro_prefix filelist

    printf '\n== %s ==\n' "$block"

    [ -n "$revinfo" ] && [ -f "$revinfo" ] || { fail "no revinfo.yml found for block '$block'"; return; }
    [ -f "$map" ]      || { fail "${map#$DEST/} missing"; return; }

    if [ -z "$prefix" ]; then
        prefix="$(sed -nE 's/^prefix:[[:space:]]*"(.*)"$/\1/p' "$revinfo" | head -1)"
    fi
    [ -n "$prefix" ] || { fail "could not determine prefix"; return; }
    macro_prefix="$(printf '%s' "$prefix" | tr '[:lower:]' '[:upper:]')"

    filelist="$(sed -nE 's/^[[:space:]]*filelist:[[:space:]]*(.*)$/\1/p' "$revinfo" | head -1)"

    # The block's source directories, mirroring the caliptra-rtl hierarchy.
    local dirs
    mapfile -t dirs < <(sed -nE '/^[[:space:]]*source_dirs:/,/^[[:space:]]*(collateral_dirs|filelist):/ s/^[[:space:]]*-[[:space:]]*(src\/.*)$/\1/p' "$revinfo")
    [ "${#dirs[@]}" -gt 0 ] || { fail "revinfo lists no source_dirs"; return; }
    local d
    for d in "${dirs[@]}"; do
        [ -d "$DEST/$d" ] || { fail "source dir missing: $d"; return; }
    done

    # Collateral directories: the rest of the block folder (tb/, formal/,
    # stimulus/, uvmf_*/). Imported whole, held to a looser contract -- see the
    # "Two tiers" section in rename_common.sh.
    local cdirs=() cfiles=()
    mapfile -t cdirs < <(sed -nE '/^[[:space:]]*collateral_dirs:/,/^[[:space:]]*filelist:/ s/^[[:space:]]*-[[:space:]]*(src\/.*)$/\1/p' "$revinfo")

    # Synthesizable subtrees: the only place new names are minted.
    local sdirs
    mapfile -t sdirs < <(sed -nE '/^[[:space:]]*synth_subtrees:/,/^[[:space:]]*excluded_globs:/ s/^[[:space:]]*-[[:space:]]*"(src\/[^"]+)".*/\1/p' "$revinfo")
    [ "${#sdirs[@]}" -gt 0 ] || { fail "revinfo lists no synth_subtrees"; return; }
    for d in "${sdirs[@]}"; do
        [ -d "$DEST/$d" ] || { fail "synth dir missing: $d"; return; }
    done

    # Every imported source, as a repo-relative path.
    local files
    mapfile -t files < <(cd "$DEST" && find "${dirs[@]}" -maxdepth 1 -type f \
                          \( -name '*.sv' -o -name '*.svh' -o -name '*.v' \) | sort)
    [ "${#files[@]}" -gt 0 ] || { fail "no sources under ${dirs[*]}"; return; }
    if [ "${#cdirs[@]}" -gt 0 ]; then
        mapfile -t cfiles < <(cd "$DEST" && find "${cdirs[@]}" -type f \
                              \( -name '*.sv' -o -name '*.svh' -o -name '*.v' \) 2>/dev/null | sort)
    fi
    # Checks 4-6 cover both tiers: a testbench that still says `ecc_top` would
    # silently bind to whatever other ecc_top is in the simulation.
    local allfiles=("${files[@]}" "${cfiles[@]}")

    # Synthesizable sources only -- the subset that is renamed.
    local synthfiles=()
    mapfile -t synthfiles < <(cd "$DEST" && find "${sdirs[@]}" -maxdepth 1 -type f \
                              \( -name '*.sv' -o -name '*.svh' -o -name '*.v' \) | sort)
    [ "${#synthfiles[@]}" -gt 0 ] || { fail "no sources under ${sdirs[*]}"; return; }

    # 1. every *synthesizable* file name carries the prefix. Non-synth delivery
    #    files (coverage binds) keep their upstream names along with the rest of
    #    the verification collateral -- see check 10.
    local f b bad=0
    for f in "${synthfiles[@]}"; do
        b="$(basename "$f")"
        case "$b" in "$prefix"*) ;; *) fail "unprefixed synthesizable file name: $f"; bad=1 ;; esac
    done
    [ "$bad" -eq 0 ] && ok "all ${#synthfiles[@]} synthesizable file names carry '$prefix'"

    # 1b. the ARCA layout mirrors the upstream layout
    bad=0
    local up ar
    while IFS=' ' read -r up ar; do
        [ -n "${ar:-}" ] || continue
        if [ "$up" != "$ar" ]; then
            printf '  note  layout override: upstream %s -> arca %s\n' "$up" "$ar"
        fi
        case " ${dirs[*]} " in *" $ar "*) ;; *) fail "revinfo subtree '$ar' not in source_dirs"; bad=1 ;; esac
    done < <(sed -nE 's/^[[:space:]]*-[[:space:]]*\{[[:space:]]*upstream:[[:space:]]*"([^"]+)",[[:space:]]*arca:[[:space:]]*"([^"]+)".*/\1 \2/p' "$revinfo")
    [ "$bad" -eq 0 ] && ok "ARCA layout mirrors the caliptra-rtl hierarchy"

    # 2. every global-namespace declaration in synthesizable RTL carries the
    #    prefix.
    #
    # module/package/interface/program are the compilation-unit-scope names --
    # the ones that collide if ARCA and an unprefixed caliptra-rtl end up in one
    # netlist. That risk belongs to the synthesized design, so the rename is
    # scoped to it. SystemVerilog *classes* are never renamed anywhere: a class
    # is scoped by the package that declares it, so ECC_in_pkg::ECC_in_agent
    # cannot clash across compiles.
    bad=0
    local name
    while IFS= read -r decl; do
        [ -n "$decl" ] || continue
        name="${decl##* }"
        case "$name" in "$prefix"*) ;; *) fail "unprefixed declaration in synthesizable RTL: $decl"; bad=1 ;; esac
    done < <(cd "$DEST" && grep -hoE '^[[:space:]]*(module|package|interface|program)[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*' "${synthfiles[@]}" \
             | sed -E 's/^[[:space:]]*//; s/[[:space:]]+/ /')
    [ "$bad" -eq 0 ] && ok "all synthesizable module/package/interface/program declarations carry '$prefix'"

    # 2b. the converse, and the thing that actually pins the policy down:
    #     nothing *outside* synthesizable RTL may have been given a new name.
    #     Without this the scope could silently widen again and the only symptom
    #     would be a UVMF tree that no longer matches its generator inputs.
    bad=0
    local nonsynth=()
    for f in "${allfiles[@]}"; do
        local issynth=0 d2
        for d2 in "${sdirs[@]}"; do case "$f" in "$d2"/*) issynth=1 ;; esac; done
        [ "$issynth" -eq 0 ] && nonsynth+=("$f")
    done
    if [ "${#nonsynth[@]}" -gt 0 ]; then
        while IFS= read -r decl; do
            [ -n "$decl" ] || continue
            name="${decl##* }"
            case "$name" in
                "$prefix"*) fail "non-synthesizable declaration was renamed: $decl"; bad=1 ;;
            esac
        done < <(cd "$DEST" && grep -hoE '^[[:space:]]*(module|package|interface|program)[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*' "${nonsynth[@]}" \
                 | sed -E 's/^[[:space:]]*//; s/[[:space:]]+/ /')
        [ "$bad" -eq 0 ] && ok "no verification-tier declaration was renamed (${#nonsynth[@]} file(s) checked)"
    fi

    # 3. every `define carries the macro prefix
    bad=0
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$name" in "$macro_prefix"*) ;; *) fail "unprefixed \`define: $name"; bad=1 ;; esac
    done < <(cd "$DEST" && grep -hoE '^[[:space:]]*`define[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*' "${synthfiles[@]}" \
             | sed -E 's/.*`define[[:space:]]+//')
    [ "$bad" -eq 0 ] && ok "all \`define macros carry '$macro_prefix'"

    # 4. no double prefixing (idempotency of the rename engine)
    if (cd "$DEST" && grep -qE "(${prefix}){2}|(${macro_prefix}){2}" "${allfiles[@]}"); then
        (cd "$DEST" && grep -nE "(${prefix}){2}|(${macro_prefix}){2}" "${allfiles[@]}" | head -5)
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
        if (cd "$DEST" && perl -ne 'exit 0 if /(?<![A-Za-z0-9_\$\\])\Q'"$orig"'\E(?![A-Za-z0-9_\$])/; END{exit 1}' "${allfiles[@]}"); then
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

    # 7. every `include target resolves, from the including file's own directory
    #    or from one of the block's include directories
    bad=0
    local inc src incdirs=() platform_seen=()
    mapfile -t incdirs < <(sed -nE 's#^\+incdir\+\$\{ARCA_ROOT\}/(.*)$#\1#p' "$DEST/$filelist" 2>/dev/null || true)
    while IFS='|' read -r src inc; do
        [ -n "${inc:-}" ] || continue
        local found=0 p
        [ -f "$DEST/$(dirname "$src")/$inc" ] && found=1
        for p in "${incdirs[@]}"; do [ -f "$DEST/$p/$inc" ] && found=1; done
        [ "$found" -eq 1 ] && continue
        local allowed=0
        for p in "${PLATFORM_HEADERS[@]}"; do [ "$inc" = "$p" ] && allowed=1; done
        if [ "$allowed" -eq 1 ]; then
            # Report each platform header once, not once per including file.
            case " ${platform_seen[*]-} " in
                *" $inc "*) ;;
                *) platform_seen+=("$inc")
                   printf '  note  `include "%s" resolved from the shared ARCA platform library\n' "$inc" ;;
            esac
        else
            fail "unresolved \`include target: $inc (from $src)"
            bad=1
        fi
    done < <(cd "$DEST" && grep -HoE '^[[:space:]]*`include[[:space:]]+"[^"]+"' "${files[@]}" \
             | sed -E 's/^([^:]+):.*"([^"]+)".*/\1|\2/' | sort -u)
    [ "$bad" -eq 0 ] && ok "all \`include targets resolve in the delivery tier"

    # 8. filelist is complete, lives in the block's config/ dir, and resolves
    if [ -z "$filelist" ] || [ ! -f "$DEST/$filelist" ]; then
        fail "filelist missing"
    else
        case "$filelist" in
            */config/*) ok "filelist mirrors upstream config/ location: $filelist" ;;
            *) fail "filelist is not under a config/ directory: $filelist" ;;
        esac
        bad=0
        local n=0 line
        while IFS= read -r line; do
            line="${line#\$\{ARCA_ROOT\}/}"
            [ -f "$DEST/$line" ] || { fail "filelist entry not found: $line"; bad=1; }
            n=$((n + 1))
        done < <(grep -vE '^\s*(//|\+|$)' "$DEST/$filelist")
        for f in "${files[@]}"; do
            grep -q "/$f\$" "$DEST/$filelist" || { fail "source not in filelist: $f"; bad=1; }
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
    done < <(sed -nE '/^renamed_manifest:/,$ s/^[[:space:]]*-[[:space:]]*\{[[:space:]]*sha256:[[:space:]]*"([0-9a-f]+)",[[:space:]]*path:[[:space:]]*"([^"]+)".*/\1 \2/p' "$revinfo")
    [ "$bad" -eq 0 ] && ok "renamed manifest matches working tree"

    # 10. collateral tier -- imported whole, keeps its upstream names.
    #
    # Checks 4-6 already proved its *references* follow the renamed RTL, and
    # check 2b proved its own declarations were left alone. What is deliberately
    # not asserted here:
    #   * file names do not carry the prefix -- nothing here is synthesized, so
    #     nothing here needs a new name;
    #   * `include targets need not resolve inside the block -- testbenches
    #     reach into caliptra-rtl verification headers and UVM, neither of which
    #     this import vendors. Those are reported, not failed.
    if [ "${#cdirs[@]}" -eq 0 ]; then
        printf '  note  no collateral imported for this block\n'
    else
        local nall ninc=0 bad
        nall="$(cd "$DEST" && find "${cdirs[@]}" -type f 2>/dev/null | wc -l)"

        # No collateral file name may have been prefixed. Renaming them would
        # desynchronise the UVMF tree from the generator inputs it was produced
        # from, for no netlist benefit.
        bad="$(cd "$DEST" && find "${cdirs[@]}" -name "${prefix}*" -type f 2>/dev/null)"
        if [ -n "$bad" ]; then
            fail "collateral file name(s) were prefixed but should keep upstream names:"
            printf '%s\n' "$bad" | sed 's/^/          /'
        else
            ok "all collateral file names kept their upstream names"
        fi
        while IFS='|' read -r src inc; do
            [ -n "${inc:-}" ] || continue
            [ -f "$DEST/$(dirname "$src")/$inc" ] && continue
            local hit=0 p2
            for p2 in "${incdirs[@]}"; do [ -f "$DEST/$p2/$inc" ] && hit=1; done
            [ "$hit" -eq 1 ] && continue
            for p2 in "${PLATFORM_HEADERS[@]}"; do [ "$inc" = "$p2" ] && hit=1; done
            [ "$hit" -eq 1 ] && continue
            ninc=$((ninc + 1))
        done < <(cd "$DEST" && [ "${#cfiles[@]}" -gt 0 ] && grep -HoE '^[[:space:]]*`include[[:space:]]+"[^"]+"' "${cfiles[@]}" \
                 | sed -E 's/^([^:]+):.*"([^"]+)".*/\1|\2/' | sort -u)
        ok "collateral tier: $nall file(s) in ${#cdirs[@]} dir(s), ${#cfiles[@]} SystemVerilog, identifiers consistent with the delivery"
        [ "$ninc" -gt 0 ] && printf '  note  %d collateral `include target(s) resolve outside the block (UVM / caliptra-rtl verification headers, not vendored)\n' "$ninc"
    fi
    # ------------------------------------------------------------------
    # 11. no path string may name a directory that does not exist.
    #
    # The identifier pass is a text pass and cannot distinguish the module
    # "hmac_drbg" from the directory "src/hmac_drbg". Without a repair pass it
    # silently emits dangling paths like
    #   ${CALIPTRA_ROOT}/src/arca_hmac_drbg/rtl/arca_hmac_drbg.sv
    # in .vf lists, compile.do and stimulus YAML. Neither check_filelists.sh
    # (skips externally-rooted entries) nor the round-trip (strips the prefix
    # before diffing) can see them, so they need their own check.
    # ------------------------------------------------------------------
    local pathbad=() comp
    while IFS= read -r comp; do
        [ -n "$comp" ] || continue
        find "$DEST" -type d -name "$comp" -print -quit | grep -q . && continue
        pathbad+=("$comp")
    done < <(cd "$DEST" && find "${dirs[@]}" ${cdirs[0]:+"${cdirs[@]}"} -type f 2>/dev/null \
             | xargs grep -hoE "/${prefix}[A-Za-z0-9_]+/" 2>/dev/null \
             | sed -E "s|^/||; s|/$||" | sort -u)
    if [ "${#pathbad[@]}" -gt 0 ]; then
        fail "path string(s) name a prefixed directory that does not exist:"
        printf '          %s\n' "${pathbad[@]}"
    else
        ok "every prefixed path component names a directory that exists"
    fi

    return 0
}

if [ -n "$BLOCK" ]; then
    verify_block "$BLOCK"
else
    found=0
    while read -r b r; do
        found=1
        verify_block "$b"
    done < <(ri_find "$DEST")
    [ "$found" -eq 1 ] || { echo "no imported blocks found under $DEST/src" >&2; exit 1; }
fi

printf '\n'
if [ "$FAILURES" -ne 0 ]; then
    printf 'verify_import: %d check(s) FAILED\n' "$FAILURES"
    exit 1
fi
printf 'verify_import: all checks passed\n'
