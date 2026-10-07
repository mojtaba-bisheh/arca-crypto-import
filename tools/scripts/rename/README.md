# Tessera crypto import

Caliptra crypto engines vendored into Tessera, with a rename script per block.
Run every command below from the repository root.

## Pulling the latest update from caliptra-rtl / adams-bridge

Everything is done by `tools/scripts/rename/import_block.sh`. It clones (or
reuses) the upstream repo, checks out the branch recorded in the block's
`revinfo.yml`, re-copies the block, re-applies the `tessera_` prefix and rewrites
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

Blocks: `aes` `ecc` `hmac512` `hmac256` `mldsa_mlkem_all_levels` `sha256`
`sha256_masked` `sha3` `sha512` `sha512_masked`. `mldsa_mlkem_all_levels`
comes from the `adams-bridge` submodule, and `hmac256` and `sha256_masked`
from caliptra-rtl's `future` branch — both are handled automatically.

Two blocks carry an Tessera name that differs from the upstream one.

`hmac512`: caliptra-rtl calls the SHA-512 HMAC engine simply `hmac`, which
reads as a generic name next to `hmac256`. The repo-wide *stem policy* in
`rename_common.sh` (`RC_DEFAULT_STEM_RENAMES`) renames `hmac*` to `hmac512*`
on top of the `tessera_` prefix, so upstream `src/hmac/rtl/hmac_core.sv` lands as
`src/hmac512/rtl/tessera_hmac512_core.sv`. `hmac_drbg` is exempt
(`RC_DEFAULT_STEM_KEEP`) — it is a shared DRBG, not a SHA-512 HMAC, and ECC
imports it too. The policy lives in the shared engine rather than in
`rename_hmac512.sh` because identifiers cross block boundaries: ECC also
references `hmac_param_pkg`, and both imports have to spell the renamed
package the same way. Each `revinfo.yml` records the policy that was in force
under `policy.stem_renames` / `policy.stem_keep`.

`revinfo.yml` is deliberately engine-level: it answers "where did this block
come from", which is one upstream commit. The per-file list lives beside it in
`revinfo.manifest`, because it is machine input rather than something you read
-- `roundtrip_check.sh` enumerates it to know what to prove, and it is what
records the effect of `excluded_globs` / `artifact_globs`. `revinfo.yml` pins it
under `content.manifest_sha256`, and `verify_import.sh` rejects the pair if they
disagree, so moving the detail out does not make it easier to tamper with.

`mldsa_mlkem_all_levels` is renamed the other way round: its *directory* is
renamed but its *identifiers* are not. Upstream calls the engine `abr`
("Adams Bridge"), a codename that says nothing about ML-DSA, ML-KEM, or the
security levels covered, so the Tessera directory is named for what the block
implements. The identifiers keep the short upstream `abr_` stem — a
22-character stem on all 222 identifiers in the block would cost far more
readability than it buys. Directory and stem are independent knobs:
`BLOCK_DIR`/`DEST_SUBTREES` set the first, `RC_DEFAULT_STEM_RENAMES` the
second. Tying them together, as `hmac512` does, is a per-block choice.

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
