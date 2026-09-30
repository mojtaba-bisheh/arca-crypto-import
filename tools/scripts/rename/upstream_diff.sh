#!/usr/bin/env bash
#
# upstream_diff.sh -- "what changed in caliptra-rtl since we vendored this?"
#
#   ./tools/scripts/rename/upstream_diff.sh            # all blocks, summary
#   ./tools/scripts/rename/upstream_diff.sh --block ecc --patch
#
# This is the whole reason revinfo/<block>.revinfo.yml records a commit SHA:
# it lets you review the upstream changelog for exactly the subtrees you
# imported before deciding to re-run the import.

set -euo pipefail

DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
UPSTREAM=""
BLOCK=""
AGAINST="origin/main"
PATCH=0

while [ $# -gt 0 ]; do
    case "$1" in
        --upstream) UPSTREAM="${2:?}"; shift 2 ;;
        --block)    BLOCK="${2:?}";    shift 2 ;;
        --against)  AGAINST="${2:?}";  shift 2 ;;
        --patch)    PATCH=1;           shift ;;
        --help|-h)  sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -n "$UPSTREAM" ] || UPSTREAM="$DEST/.upstream-cache/caliptra-rtl"
[ -d "$UPSTREAM/.git" ] || { echo "need --upstream <caliptra-rtl checkout>" >&2; exit 2; }

git -C "$UPSTREAM" fetch --quiet --tags --prune origin || true

blocks=()
if [ -n "$BLOCK" ]; then
    blocks=("$BLOCK")
else
    for r in "$DEST"/revinfo/*.revinfo.yml; do
        [ -e "$r" ] || continue
        blocks+=("$(basename "$r" .revinfo.yml)")
    done
fi

for b in "${blocks[@]}"; do
    revinfo="$DEST/revinfo/$b.revinfo.yml"
    sha="$(sed -nE 's/^[[:space:]]*commit:[[:space:]]*"([0-9a-f]+)".*/\1/p' "$revinfo" | head -1)"
    mapfile -t subtrees < <(sed -nE '/^  subtrees:/,/^  [a-z_]+:/ s/^    - (.*)$/\1/p' "$revinfo")

    printf '\n======================================================================\n'
    printf ' %s : imported at %s\n' "$b" "${sha:0:12}"
    printf ' subtrees: %s\n' "${subtrees[*]}"
    printf '======================================================================\n'

    if [ "$(git -C "$UPSTREAM" rev-parse "$AGAINST")" = "$sha" ]; then
        echo "up to date with $AGAINST"
        continue
    fi

    git -C "$UPSTREAM" log --oneline --no-decorate "$sha..$AGAINST" -- "${subtrees[@]}" \
        || echo "(no commits, or $sha is not an ancestor of $AGAINST)"

    if [ "$PATCH" -eq 1 ]; then
        printf '\n---- diff ----\n'
        git -C "$UPSTREAM" diff --stat "$sha..$AGAINST" -- "${subtrees[@]}"
    fi
done
