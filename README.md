# arca-crypto-import

Caliptra crypto engines vendored into ARCA, with a rename script per block.

## Pulling the latest update from caliptra-rtl / adams-bridge

Everything is done by `tools/scripts/rename/import_block.sh`. It clones (or
reuses) the upstream repo, checks out the branch recorded in the block's
`revinfo.yml`, re-copies the block, re-applies the `arca_` prefix and rewrites
`src/<block>/revinfo.yml` with the new upstream commit.

```sh
# one block
./tools/scripts/rename/import_block.sh ecc

# every block
./tools/scripts/rename/import_block.sh all

# reuse a clone you already have instead of cloning again
./tools/scripts/rename/import_block.sh all --upstream ../caliptra-rtl

# pin a specific upstream commit/tag instead of the branch tip
./tools/scripts/rename/import_block.sh ecc --ref v2.1.0
```

Then review and commit:

```sh
git diff --stat
git add -A && git commit -m "Update ecc from caliptra-rtl"
```

`import_block.sh` runs the checks itself; if it prints `all checks passed`
the import is good.

Blocks: `abr` `aes` `ecc` `hmac` `hmac256` `sha256` `sha3` `sha512`
`sha512_masked`. `abr` comes from the `adams-bridge` submodule and `hmac256`
from caliptra-rtl's `future` branch — both are handled automatically.

## Seeing what changed upstream first

```sh
./tools/scripts/rename/upstream_diff.sh --block ecc --upstream ../caliptra-rtl
./tools/scripts/rename/upstream_diff.sh            # all blocks
```

Lists the upstream commits and files that changed since the commit in
`src/<block>/revinfo.yml`. `--upstream` can be omitted once
`import_block.sh` has populated `.upstream-cache/caliptra-rtl`.

## Other scripts

| Script | Purpose |
| --- | --- |
| `import_block.sh` | the one you run — copy + rename + verify |
| `rename_<block>.sh` | per-block rules; called by `import_block.sh` |
| `rename_common.sh` | shared engine behind the per-block scripts |
| `upstream_diff.sh` | what changed upstream since the last import |
| `verify_import.sh` | structural checks on the imported tree |
| `roundtrip_check.sh` | proves the copy differs from upstream by naming only |
| `check_filelists.sh` | every path in the filelists resolves |

## Rename policy

Rename what is **declared** in synthesizable RTL (modules, packages,
environment config macros). Rewrite **references** to those names everywhere.
Rename nothing else — testbench and UVMF generator inputs keep their upstream
names so they stay comparable with upstream.
