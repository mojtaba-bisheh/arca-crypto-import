# ARCA — vendored Caliptra crypto blocks (worked example)

Reference implementation of how **ARCA** imports crypto engines from
[`chipsalliance/caliptra-rtl`](https://github.com/chipsalliance/caliptra-rtl),
following the same idea as VeeR-EL2's
[`tools/prefix_macros.sh`](https://github.com/chipsalliance/Cores-VeeR-EL2/blob/main/tools/prefix_macros.sh):

> copy the block locally → prefix every name the block owns → record where it
> came from → commit the result.

Two engines are imported end to end as worked examples: **ECC** (secp384r1) and
**HMAC** (HMAC-SHA512, including the HMAC_DRBG it owns).

Everything under `rtl/` and `revinfo/` in this repo is **generated** by the
scripts in `tools/scripts/rename/` and committed as-is.

---

## Why prefix at all

An SoC may contain more than one Caliptra-derived instance, or more than one
*version* of the same engine. SystemVerilog has a flat global namespace for
modules, packages, interfaces and compiler macros, so two copies collide at
elaboration. Prefixing everything the block owns (`ecc_top` → `arca_ecc_top`,
`` `HMAC_PARAM_PKG `` → `` `ARCA_HMAC_PARAM_PKG ``) makes the imported block
relocatable and lets ARCA carry its own release cadence.

---

## Repository layout

```
rtl/
  ecc/                      generated, prefixed ECC fileset + arca_ecc.f
  hmac/                     generated, prefixed HMAC + HMAC_DRBG + arca_hmac.f
revinfo/
  ecc.revinfo.yml           provenance: upstream repo/commit/date, policy, sha256 manifests
  ecc.map                   full original -> renamed identifier table
  hmac.revinfo.yml
  hmac.map
tools/scripts/rename/
  rename_common.sh          shared machinery (sourced library, not executable on its own)
  rename_ecc.sh             per-block driver: ECC quirks
  rename_hmac.sh            per-block driver: HMAC quirks
  lib/apply_map.pl          the actual token-substitution engine
  import_block.sh           one-shot driver: fetch upstream, rename, verify, commit
  verify_import.sh          structural checks on a committed fileset
  roundtrip_check.sh        proves the rename changed names and nothing else
  upstream_diff.sh          "what changed upstream since we imported this?"
docs/METHODOLOGY.md         design rationale, policies, how to add a new block
```

One script per block, all under `tools/scripts/rename/`. The blocks are
*similar but not identical* — different directory hierarchies, different
include-guard macro names, different environment-supplied configuration
macros, different cross-block dependencies — so each block gets a short driver
that declares its quirks and delegates the mechanics to `rename_common.sh`.

---

## Quick start

```bash
# Import every block from upstream default branch (clones into .upstream-cache/)
make import

# ...or a specific block from a specific upstream ref, using a local checkout
make import-ecc UPSTREAM=~/src/caliptra-rtl REF=v2.1.0

# Re-run the checks on what is already committed
make verify
make roundtrip UPSTREAM=~/src/caliptra-rtl

# Before pulling updates: review the upstream changelog for exactly the
# subtrees we vendored, starting at the commit recorded in revinfo/
make updates UPSTREAM=~/src/caliptra-rtl
```

To import and commit in one shot:

```bash
./tools/scripts/rename/import_block.sh all --ref main --commit
```

---

## What the import actually does

| Step | What happens |
|------|--------------|
| 1. stage | Upstream subtrees are copied into a temp dir. `*_reg_uvm.sv` and `*.rdl` are excluded (see [METHODOLOGY](docs/METHODOLOGY.md)). sha256 of every source file is recorded. |
| 2. map | Every `module` / `package` / `interface` / `` `define `` declared *inside* the block is collected, plus driver-declared cross-block identifiers and environment config macros. The keep-list (shared platform identifiers) is subtracted. Result: `revinfo/<block>.map`. |
| 3. apply | One Perl pass per file over the whole map, alternation sorted longest-first, with SystemVerilog identifier boundaries. |
| 4. env macros | Macros the caliptra-rtl *environment* supplied are captured into a generated block-private header (`arca_hmac_config.svh`) and the `` `include `` is redirected there. |
| 5. file rename | Every file gets the prefix; `` `include `` references were already rewritten in step 3. |
| 6. filelist | A compile-ordered `arca_<block>.f` is generated, ordering derived from the upstream `.vf` filelist. |
| 7. revinfo | `revinfo/<block>.revinfo.yml` records upstream repo/branch/commit/date/subject, dirty flag, subtrees, prefix, script fingerprint, policy (exclusions, keep-list, cross-block deps, env macros) and sha256 manifests before *and* after renaming. |
| 8. verify | 9 structural checks, then the round-trip proof. |

### The rename engine, concretely

`\b` is **not** a correct SystemVerilog identifier boundary — SV identifiers
may contain `_` and `$`, and escaped identifiers start with `\`. The engine
uses explicit look-around instead:

```perl
(?<![A-Za-z0-9_$\\]) (ident1|ident2|...) (?![A-Za-z0-9_$])
```

Consequences that matter:

* `` `HMAC_PARAM_PKG `` **is** matched — the backtick is outside the class, so
  macro usages are renamed without a separate pass.
* `arca_hmac` is **not** re-matched — the character before `hmac` is `_`, which
  makes the whole transform idempotent by construction.
* Renaming module `hmac` never touches `hmac_reg_pkg`, `hmac_core`,
  `ecc_hmac_drbg_interface` or local signals like `hmac_drbg_init`.
* Everything is applied in **one pass per file** with the alternation sorted by
  descending length, so no token can be partially rewritten by an earlier pass
  and then rewritten again by a later one.

### The strongest check: round-trip

`roundtrip_check.sh` strips the prefix back off every committed file and diffs
it against the exact upstream blob at the commit recorded in `revinfo/`:

```
== ecc (upstream 9d6585080a35, prefix arca_) ==
  ok    ecc_adder.sv
  ...
  -- 23 file(s) round-tripped

== hmac (upstream 9d6585080a35, prefix arca_) ==
  ok    hmac_core.sv
  ok    hmac_ctrl.sv (include redirected on purpose)
  ...
  -- 7 file(s) round-tripped

roundtrip_check: imported RTL differs from upstream by naming only
```

That is the property that matters for a security IP import: the vendored RTL
differs from upstream by **names only** — no stray logic edits, no dropped
lines, no mangled string literals.

---

## Interesting cases these two blocks already exercise

* **Cross-block ownership.** ECC instantiates `hmac_drbg`, which lives in a
  different upstream directory. Policy: HMAC owns it and imports it once; ECC
  only rewrites the *reference*. Both land on `arca_hmac_drbg`, so the netlist
  has exactly one copy. Declared in `rename_ecc.sh:EXTRA_RENAME_IDENTS`.
* **Multiple upstream directories per block.** HMAC spans `src/hmac/rtl` and
  `src/hmac_drbg/rtl`.
* **Environment configuration macros.** HMAC consumes
  `` `CLP_CSR_HMAC_KEY_DWORDS ``, defined in caliptra-rtl's global
  `src/libs/rtl/caliptra_macros.svh`. The import captures it as
  `` `ARCA_CLP_CSR_HMAC_KEY_DWORDS `` in a generated block-private header and
  redirects the `` `include ``, so the vendored block stops reaching into
  caliptra-rtl globals.
* **Irregular include guards.** ECC's guards do not follow one pattern
  (`CALIPTRA_ECC_DEFINES`, `CALIPTRA_ECC_PARAMS_PKG`, `CALIPTRA_ECC_PM_UOP_PKG`,
  `ECC_DSA_UOP_PKG`), so they are discovered from the sources, never hard-coded.
* **Short, collision-prone names.** Module `hmac` — handled by the boundary
  regex above.
* **Keep-list.** `kv_defines_pkg`, `kv_read_t`, `kv_write_t`,
  `` `CALIPTRA_ASSERT_* ``, `caliptra_prim_assert.sv` are *shared platform*
  identifiers, deliberately **not** prefixed. See the caveat in
  [METHODOLOGY](docs/METHODOLOGY.md#shared-platform-library).

---

## Adding a new block

1. `cp tools/scripts/rename/rename_ecc.sh tools/scripts/rename/rename_<block>.sh`
2. Edit `BLOCK`, `UPSTREAM_SUBTREES`, `VF_FILELIST` / `VF_FILTER`,
   `EXCLUDE_GLOBS`, `EXTRA_RENAME_IDENTS`, `ENV_MACRO_SPECS`, `KEEP_IDENTS`.
   Document the block's quirks in the header comment.
3. `./tools/scripts/rename/import_block.sh <block> --commit`
4. Add the block to `BLOCKS` in the `Makefile`.

No changes to `rename_common.sh` should be needed for a well-behaved block; if
they are, add a `block_pre_rename` / `block_post_rename` hook in the driver
rather than special-casing the shared library.

---

## Status

This is an example repository used to agree on the methodology before applying
it to the real ARCA tree. It is not a product deliverable.
