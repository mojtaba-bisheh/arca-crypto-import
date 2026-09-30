#!/usr/bin/env bash
#
# rename_common.sh -- shared library for the ARCA crypto-block import/rename flow.
#
# This file is NOT executable on its own. Each crypto block has its own driver
# script (rename_ecc.sh, rename_hmac.sh, ...) that declares the block-specific
# configuration and then calls `rc_run`.
#
# The blocks are similar but not identical: different directory hierarchies,
# different include-guard macro names, different environment-supplied
# configuration macros, and different cross-block dependencies. Keeping the
# common machinery here and the quirks in the per-block driver keeps each
# driver short and auditable.
#
# ---------------------------------------------------------------------------
# Contract for a per-block driver
# ---------------------------------------------------------------------------
# Required variables:
#   BLOCK                 short block name, e.g. "ecc"
#   UPSTREAM_SUBTREES     array of upstream dirs to import (repo-relative)
#
# Optional variables:
#   VF_FILELIST           upstream .vf filelist used to derive compile order
#   VF_FILTER             egrep pattern selecting this block's lines in VF_FILELIST
#   EXCLUDE_GLOBS         array of basename globs never imported
#   EXTRA_RENAME_IDENTS   array of "kind:name" tokens that are declared outside
#                         this block but must still be renamed (cross-block deps)
#   ENV_MACRO_SPECS       array of "MACRO@upstream/path/to/header.svh" -- macros
#                         the *environment* applies to configure the block
#   ENV_HEADER_REPLACE    array of header basenames whose `include is redirected
#                         to the generated block-private config header
#   KEEP_IDENTS           array of identifiers that must NOT be prefixed
#                         (shared platform libraries owned by ARCA, not by the block)
#
# Optional hook functions:
#   block_pre_rename      run after staging, before the map is applied
#   block_post_rename     run after the map is applied, before files are renamed
# ---------------------------------------------------------------------------

set -euo pipefail

RC_SCRIPT_VERSION="1.1.0"

rc_log()  { printf '[%s] %s\n' "${BLOCK:-rename}" "$*"; }
rc_warn() { printf '[%s] WARNING: %s\n' "${BLOCK:-rename}" "$*" >&2; }
rc_die()  { printf '[%s] ERROR: %s\n' "${BLOCK:-rename}" "$*" >&2; exit 1; }

rc_usage() {
    cat <<EOF
usage: $(basename "$0") --upstream <caliptra-rtl-checkout> [options]

  --upstream  <dir>   path to a caliptra-rtl git checkout (required)
  --dest      <dir>   ARCA repo root (default: repo root of this script)
  --prefix    <str>   identifier prefix, lowercase, trailing underscore
                      (default: \$ARCA_PREFIX or "arca_")
  --keep-work         do not delete the temporary staging directory
  --help              show this message
EOF
}

# ---------------------------------------------------------------------------
# rc_init -- argument parsing and environment discovery
# ---------------------------------------------------------------------------
rc_default_array() {
    local name
    for name in "$@"; do
        declare -p "$name" >/dev/null 2>&1 || eval "$name=()"
    done
}

rc_init() {
    rc_default_array EXCLUDE_GLOBS EXTRA_RENAME_IDENTS ENV_MACRO_SPECS \
                     ENV_HEADER_REPLACE KEEP_IDENTS

    UPSTREAM=""
    DEST=""
    PREFIX="${ARCA_PREFIX:-arca_}"
    KEEP_WORK=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --upstream) UPSTREAM="${2:?--upstream needs a value}"; shift 2 ;;
            --dest)     DEST="${2:?--dest needs a value}";         shift 2 ;;
            --prefix)   PREFIX="${2:?--prefix needs a value}";     shift 2 ;;
            --keep-work) KEEP_WORK=1; shift ;;
            --help|-h)  rc_usage; exit 0 ;;
            *) rc_usage >&2; rc_die "unknown argument: $1" ;;
        esac
    done

    [ -n "$UPSTREAM" ] || { rc_usage >&2; rc_die "--upstream is required"; }
    [ -d "$UPSTREAM/.git" ] || rc_die "'$UPSTREAM' is not a git checkout"

    RC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -z "$DEST" ]; then
        DEST="$(cd "$RC_LIB_DIR/../../.." && pwd)"
    fi
    [ -d "$DEST" ] || rc_die "destination '$DEST' does not exist"

    UPSTREAM="$(cd "$UPSTREAM" && pwd)"
    DEST="$(cd "$DEST" && pwd)"

    case "$PREFIX" in
        *_) : ;;
        *)  rc_die "prefix '$PREFIX' must end with an underscore" ;;
    esac
    MACRO_PREFIX="$(printf '%s' "$PREFIX" | tr '[:lower:]' '[:upper:]')"

    OUT_RTL="$DEST/rtl/$BLOCK"
    OUT_REVINFO="$DEST/revinfo"
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/arca-import-$BLOCK-XXXXXX")"
    STAGE="$WORK/stage"
    MAP="$WORK/map.tsv"
    mkdir -p "$STAGE" "$OUT_REVINFO"

    if [ "$KEEP_WORK" -eq 0 ]; then
        trap 'rm -rf "$WORK"' EXIT
    else
        rc_log "staging dir kept at $WORK"
    fi

    UPSTREAM_URL="$(git -C "$UPSTREAM" config --get remote.origin.url || echo 'unknown')"
    UPSTREAM_SHA="$(git -C "$UPSTREAM" rev-parse HEAD)"
    UPSTREAM_DESC="$(git -C "$UPSTREAM" log -1 --format='%s' HEAD)"
    UPSTREAM_DATE="$(git -C "$UPSTREAM" log -1 --format='%cI' HEAD)"
    UPSTREAM_BRANCH="$(git -C "$UPSTREAM" rev-parse --abbrev-ref HEAD)"
    if [ -n "$(git -C "$UPSTREAM" status --porcelain -- $(printf '%s ' "${UPSTREAM_SUBTREES[@]}"))" ]; then
        UPSTREAM_DIRTY="true"
        rc_warn "upstream working tree is dirty for the imported subtrees"
    else
        UPSTREAM_DIRTY="false"
    fi

    rc_log "upstream : $UPSTREAM @ $UPSTREAM_SHA"
    rc_log "dest     : $DEST"
    rc_log "prefix   : $PREFIX (macros: $MACRO_PREFIX)"
}

# ---------------------------------------------------------------------------
# rc_stage -- copy the upstream subtrees into a flat staging directory
# ---------------------------------------------------------------------------
rc_stage() {
    local subtree src base skip glob
    STAGED_FILES=()
    SRC_MANIFEST="$WORK/src_manifest.txt"
    : > "$SRC_MANIFEST"

    for subtree in "${UPSTREAM_SUBTREES[@]}"; do
        [ -d "$UPSTREAM/$subtree" ] || rc_die "upstream subtree '$subtree' not found"
        while IFS= read -r src; do
            base="$(basename "$src")"
            skip=0
            for glob in "${EXCLUDE_GLOBS[@]}"; do
                [ -n "$glob" ] || continue
                # shellcheck disable=SC2053
                if [[ "$base" == $glob ]]; then skip=1; break; fi
            done
            if [ "$skip" -eq 1 ]; then
                rc_log "  excluded  $subtree/$base"
                continue
            fi
            [ -e "$STAGE/$base" ] && rc_die "basename collision while staging: $base"
            cp "$src" "$STAGE/$base"
            STAGED_FILES+=("$base")
            printf '%s  %s/%s\n' "$(sha256sum "$src" | cut -d' ' -f1)" "$subtree" "$base" >> "$SRC_MANIFEST"
        done < <(find "$UPSTREAM/$subtree" -maxdepth 1 -type f | sort)
    done

    [ "${#STAGED_FILES[@]}" -gt 0 ] || rc_die "nothing staged"
    rc_log "staged ${#STAGED_FILES[@]} file(s)"
}

# ---------------------------------------------------------------------------
# rc_build_map -- collect every identifier this block owns and build the
#                 original -> renamed mapping table.
# ---------------------------------------------------------------------------
rc_build_map() {
    local f kind name tok keep hit
    : > "$MAP.raw"

    pushd "$STAGE" >/dev/null
    for f in "${STAGED_FILES[@]}"; do
        # Declarations owned by the block.
        grep -hoE '^[[:space:]]*(module|package|interface)[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*' "$f" 2>/dev/null \
            | sed -E 's/^[[:space:]]*//; s/[[:space:]]+/\t/' >> "$MAP.raw" || true
        # Include-guard / helper macros defined inside the block.
        grep -hoE '^[[:space:]]*`define[[:space:]]+[A-Za-z_][A-Za-z0-9_$]*' "$f" 2>/dev/null \
            | sed -E 's/^[[:space:]]*`define[[:space:]]+/macro\t/' >> "$MAP.raw" || true
    done
    popd >/dev/null

    # Cross-block dependencies declared by the driver (e.g. ECC instantiating
    # hmac_drbg, which is owned by the HMAC import).
    for tok in "${EXTRA_RENAME_IDENTS[@]}"; do
        [ -n "$tok" ] || continue
        printf '%s\t%s\n' "${tok%%:*}" "${tok#*:}" >> "$MAP.raw"
    done

    # Environment-supplied configuration macros.
    for tok in "${ENV_MACRO_SPECS[@]}"; do
        [ -n "$tok" ] || continue
        printf 'macro\t%s\n' "${tok%%@*}" >> "$MAP.raw"
    done

    : > "$MAP"
    {
        printf '# ARCA identifier rename map\n'
        printf '# block=%s prefix=%s generator=rename_common.sh/%s\n' "$BLOCK" "$PREFIX" "$RC_SCRIPT_VERSION"
        printf '# kind\toriginal\trenamed\n'
    } >> "$MAP"

    while IFS=$'\t' read -r kind name; do
        [ -n "${name:-}" ] || continue
        keep=0
        for tok in "${KEEP_IDENTS[@]}"; do
            [ -n "$tok" ] || continue
            [ "$tok" = "$name" ] && { keep=1; break; }
        done
        if [ "$keep" -eq 1 ]; then
            rc_log "  keep-list $kind $name (shared platform identifier)"
            continue
        fi
        case "$name" in
            "$PREFIX"*|"$MACRO_PREFIX"*)
                rc_warn "'$name' already carries the prefix; skipped"
                continue ;;
        esac
        if [ "$kind" = "macro" ]; then
            printf '%s\t%s\t%s%s\n' "$kind" "$name" "$MACRO_PREFIX" "$name" >> "$MAP"
        else
            printf '%s\t%s\t%s%s\n' "$kind" "$name" "$PREFIX" "$name" >> "$MAP"
        fi
    done < <(sort -u "$MAP.raw")

    # File renames are recorded for traceability; apply_map.pl ignores them.
    for f in "${STAGED_FILES[@]}"; do
        printf 'file\t%s\t%s%s\n' "$f" "$PREFIX" "$f" >> "$MAP"
    done

    hit="$(grep -cvE '^\s*(#|$)' "$MAP" || true)"
    [ "$hit" -gt 0 ] || rc_die "rename map is empty"
    rc_log "map contains $hit entry(ies)"
}

# ---------------------------------------------------------------------------
# rc_apply -- one perl pass per file using the full map
# ---------------------------------------------------------------------------
rc_apply() {
    local f
    rc_log "applying rename map"
    pushd "$STAGE" >/dev/null
    perl "$RC_LIB_DIR/lib/apply_map.pl" "$MAP" "${STAGED_FILES[@]}"
    popd >/dev/null

    # Idempotency guard: a double prefix means the map was applied twice or an
    # entry overlapped another entry.
    if grep -rqE "(${PREFIX}){2}|(${MACRO_PREFIX}){2}" "$STAGE"; then
        grep -rnE "(${PREFIX}){2}|(${MACRO_PREFIX}){2}" "$STAGE" | head >&2
        rc_die "double-prefixed identifiers detected"
    fi
}

# ---------------------------------------------------------------------------
# rc_env_macros -- materialise a block-private configuration header holding the
#                  (now prefixed) macros the environment used to supply, and
#                  redirect the corresponding `include directives to it.
# ---------------------------------------------------------------------------
rc_env_macros() {
    ENV_HEADER=""
    [ "${#ENV_MACRO_SPECS[@]}" -gt 0 ] || return 0

    local spec macro src line guard hdr
    hdr="${PREFIX}${BLOCK}_config.svh"
    ENV_HEADER="$hdr"
    guard="$(printf '%s%s_CONFIG_SVH' "$MACRO_PREFIX" "$(printf '%s' "$BLOCK" | tr '[:lower:]' '[:upper:]')")"

    {
        printf '// SPDX-License-Identifier: Apache-2.0\n'
        printf '//\n'
        printf '// GENERATED by tools/scripts/rename/rename_%s.sh -- do not edit by hand.\n' "$BLOCK"
        printf '//\n'
        printf '// Configuration macros that the caliptra-rtl *environment* used to apply to\n'
        printf '// the %s block. They are captured here, under the ARCA prefix, so the imported\n' "$BLOCK"
        printf '// block no longer depends on caliptra-rtl global headers.\n'
        printf '//\n'
        printf '`ifndef %s\n' "$guard"
        printf '`define %s\n\n' "$guard"
    } > "$STAGE/$hdr"

    for spec in "${ENV_MACRO_SPECS[@]}"; do
        [ -n "$spec" ] || continue
        macro="${spec%%@*}"
        src="${spec#*@}"
        [ -f "$UPSTREAM/$src" ] || rc_die "env-macro source '$src' not found upstream"
        line="$(grep -E "^[[:space:]]*\`define[[:space:]]+${macro}\b" "$UPSTREAM/$src" | head -1 || true)"
        [ -n "$line" ] || rc_die "macro '$macro' not found in $src"
        printf '// from %s\n' "$src" >> "$STAGE/$hdr"
        printf '%s\n\n' "$(printf '%s' "$line" \
            | sed -E "s/\`define[[:space:]]+${macro}\b/\`define ${MACRO_PREFIX}${macro}/")" >> "$STAGE/$hdr"
        rc_log "  env macro ${macro} -> ${MACRO_PREFIX}${macro} (from $src)"
    done

    printf '`endif // %s\n' "$guard" >> "$STAGE/$hdr"
    STAGED_FILES+=("$hdr")
    printf 'file\t(generated)\t%s\n' "$hdr" >> "$MAP"

    local old
    for old in "${ENV_HEADER_REPLACE[@]}"; do
        [ -n "$old" ] || continue
        pushd "$STAGE" >/dev/null
        # shellcheck disable=SC2046
        sed -i -E "s|(\`include[[:space:]]+\")${old}(\")|\1${hdr}\2|g" $(ls *.sv *.svh *.v 2>/dev/null || true)
        popd >/dev/null
        rc_log "  redirected \`include \"$old\" -> \"$hdr\""
    done
}

# ---------------------------------------------------------------------------
# rc_rename_files -- prefix every staged file name (the generated config header
#                    is already prefixed).
# ---------------------------------------------------------------------------
rc_rename_files() {
    local f new out=()
    pushd "$STAGE" >/dev/null
    for f in "${STAGED_FILES[@]}"; do
        case "$f" in
            "$PREFIX"*) out+=("$f"); continue ;;
        esac
        new="${PREFIX}${f}"
        [ -e "$new" ] && rc_die "rename collision: $new already exists"
        mv "$f" "$new"
        out+=("$new")
    done
    popd >/dev/null
    STAGED_FILES=("${out[@]}")
    rc_log "renamed ${#STAGED_FILES[@]} file(s)"
}

# ---------------------------------------------------------------------------
# rc_emit_filelist -- compile-ordered filelist.
#
# The order is derived from the upstream .vf filelist when the driver provides
# one; the imported block keeps the upstream package/module compile order and
# we do not have to reinvent it. Files not mentioned upstream are appended.
# ---------------------------------------------------------------------------
rc_emit_filelist() {
    local ordered=() seen f base line
    FILELIST="${PREFIX}${BLOCK}.f"

    if [ -n "${VF_FILELIST:-}" ] && [ -f "$UPSTREAM/$VF_FILELIST" ]; then
        while IFS= read -r line; do
            base="$(basename "${line%%[[:space:]]*}")"
            f="${PREFIX}${base}"
            [ -f "$STAGE/$f" ] || continue
            case " ${ordered[*]:-} " in *" $f "*) continue ;; esac
            ordered+=("$f")
        done < <(grep -E "${VF_FILTER:-.}" "$UPSTREAM/$VF_FILELIST" | grep -vE '^\s*(\+|//|$)')
        rc_log "compile order derived from $VF_FILELIST"
    fi

    # The generated config header must be visible before anything uses it.
    if [ -n "${ENV_HEADER:-}" ]; then
        ordered=("$ENV_HEADER" "${ordered[@]}")
    fi

    for f in "${STAGED_FILES[@]}"; do
        case " ${ordered[*]:-} " in *" $f "*) continue ;; esac
        ordered+=("$f")
    done

    {
        printf '// GENERATED by tools/scripts/rename/rename_%s.sh -- do not edit by hand.\n' "$BLOCK"
        printf '// Compile-ordered filelist for the imported %s block.\n' "$BLOCK"
        printf '+incdir+${ARCA_ROOT}/rtl/%s\n' "$BLOCK"
        for f in "${ordered[@]}"; do
            [ -n "$f" ] || continue
            printf '${ARCA_ROOT}/rtl/%s/%s\n' "$BLOCK" "$f"
        done
    } > "$STAGE/$FILELIST"
    rc_log "wrote $FILELIST"
}

# ---------------------------------------------------------------------------
# rc_install -- publish the staged block and its map into the ARCA repo
# ---------------------------------------------------------------------------
rc_install() {
    rm -rf "$OUT_RTL"
    mkdir -p "$OUT_RTL"
    cp -a "$STAGE"/. "$OUT_RTL"/
    grep -vE '^\s*#' "$MAP" > "$OUT_REVINFO/$BLOCK.map" || true
    sed -i "1i # ARCA identifier rename map for block '$BLOCK' (prefix: $PREFIX)" "$OUT_REVINFO/$BLOCK.map"
    rc_log "installed -> rtl/$BLOCK/ and revinfo/$BLOCK.map"
}

# ---------------------------------------------------------------------------
# rc_emit_revinfo -- provenance record.
#
# Purpose (per the engineering lead): make it possible to review the upstream
# changelog when pulling updates, and to reproduce the import exactly.
# ---------------------------------------------------------------------------
rc_emit_revinfo() {
    local out="$OUT_REVINFO/$BLOCK.revinfo.yml"
    local f tok script_sha
    script_sha="$(sha256sum "$0" "$RC_LIB_DIR/rename_common.sh" "$RC_LIB_DIR/lib/apply_map.pl" \
                  | sha256sum | cut -d' ' -f1)"

    {
        printf '# ARCA vendored-block provenance record -- GENERATED, do not edit by hand.\n'
        printf '#\n'
        printf '# To review what changed upstream since this import:\n'
        printf '#   git -C <caliptra-rtl> log --oneline %s..origin/main -- %s\n' \
               "$UPSTREAM_SHA" "$(printf '%s ' "${UPSTREAM_SUBTREES[@]}")"
        printf '#\n'
        printf 'block: %s\n' "$BLOCK"
        printf 'prefix: "%s"\n' "$PREFIX"
        printf 'macro_prefix: "%s"\n' "$MACRO_PREFIX"
        printf 'imported_at: "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '\n'
        printf 'upstream:\n'
        printf '  repo: "%s"\n' "$UPSTREAM_URL"
        printf '  branch: "%s"\n' "$UPSTREAM_BRANCH"
        printf '  commit: "%s"\n' "$UPSTREAM_SHA"
        printf '  commit_date: "%s"\n' "$UPSTREAM_DATE"
        printf '  commit_subject: "%s"\n' "$(printf '%s' "$UPSTREAM_DESC" | sed 's/"/\\"/g')"
        printf '  working_tree_dirty: %s\n' "$UPSTREAM_DIRTY"
        printf '  subtrees:\n'
        for tok in "${UPSTREAM_SUBTREES[@]}"; do printf '    - %s\n' "$tok"; done
        if [ -n "${VF_FILELIST:-}" ]; then
            printf '  compile_order_from: %s\n' "$VF_FILELIST"
        fi
        printf '\n'
        printf 'importer:\n'
        printf '  script: tools/scripts/rename/%s\n' "$(basename "$0")"
        printf '  library_version: "%s"\n' "$RC_SCRIPT_VERSION"
        printf '  toolchain_fingerprint: "%s"\n' "$script_sha"
        printf '  bash: "%s"\n' "${BASH_VERSION}"
        printf '  perl: "%s"\n' "$(perl -e 'print $^V')"
        printf '\n'
        printf 'policy:\n'
        printf '  excluded_globs:\n'
        for tok in "${EXCLUDE_GLOBS[@]}"; do [ -n "$tok" ] && printf '    - "%s"\n' "$tok"; done
        printf '  cross_block_identifiers:\n'
        if [ "${#EXTRA_RENAME_IDENTS[@]}" -gt 0 ]; then
            for tok in "${EXTRA_RENAME_IDENTS[@]}"; do [ -n "$tok" ] && printf '    - "%s"\n' "$tok"; done
        else
            printf '    []\n'
        fi
        printf '  environment_config_macros:\n'
        if [ "${#ENV_MACRO_SPECS[@]}" -gt 0 ]; then
            for tok in "${ENV_MACRO_SPECS[@]}"; do [ -n "$tok" ] && printf '    - "%s"\n' "$tok"; done
        else
            printf '    []\n'
        fi
        printf '  keep_list:  # shared ARCA platform identifiers, deliberately NOT prefixed\n'
        if [ "${#KEEP_IDENTS[@]}" -gt 0 ]; then
            for tok in "${KEEP_IDENTS[@]}"; do [ -n "$tok" ] && printf '    - "%s"\n' "$tok"; done
        else
            printf '    []\n'
        fi
        printf '\n'
        printf 'artifacts:\n'
        printf '  rtl_dir: rtl/%s\n' "$BLOCK"
        printf '  filelist: rtl/%s/%s\n' "$BLOCK" "$FILELIST"
        printf '  rename_map: revinfo/%s.map\n' "$BLOCK"
        printf '\n'
        printf 'source_manifest:  # sha256 of the upstream files as imported\n'
        while IFS= read -r tok; do
            printf '  - { sha256: "%s", path: "%s" }\n' "${tok%% *}" "${tok##* }"
        done < "$SRC_MANIFEST"
        printf '\n'
        printf 'renamed_manifest:  # sha256 of the committed, renamed files\n'
        for f in $(cd "$OUT_RTL" && ls | sort); do
            printf '  - { sha256: "%s", path: "rtl/%s/%s" }\n' \
                   "$(sha256sum "$OUT_RTL/$f" | cut -d' ' -f1)" "$BLOCK" "$f"
        done
    } > "$out"
    rc_log "wrote revinfo/$BLOCK.revinfo.yml"
}

# ---------------------------------------------------------------------------
# rc_run -- orchestration
# ---------------------------------------------------------------------------
rc_run() {
    rc_stage
    if declare -F block_pre_rename >/dev/null; then block_pre_rename; fi
    rc_build_map
    rc_apply
    rc_env_macros
    if declare -F block_post_rename >/dev/null; then block_post_rename; fi
    rc_rename_files
    rc_emit_filelist
    rc_install
    rc_emit_revinfo
    "$RC_LIB_DIR/verify_import.sh" --dest "$DEST" --block "$BLOCK" --prefix "$PREFIX"
    rc_log "import complete"
}
