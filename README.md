# arca-crypto-import

Worked example of vendoring Caliptra crypto engines from
[`chipsalliance/caliptra-rtl`](https://github.com/chipsalliance/caliptra-rtl)
into ARCA under an `arca_` namespace, modelled on VeeR-EL2's
`tools/prefix_macros.sh`.

Two blocks are imported for real — **ECC** and **HMAC** (which carries
`hmac_drbg` with it) — so the flow is exercised against actual edge cases
rather than described in the abstract.

This repo exists to agree on the methodology. It is not a product deliverable.

## What it does

1. Copy the block's folder out of a caliptra-rtl checkout, mirroring the
   upstream hierarchy (`src/ecc/rtl` → `src/ecc/rtl`).
2. Apply `arca_` / `ARCA_` prefixes to **synthesized design material**.
3. Record the originating upstream commit, so you can read the changelog
   before pulling updates.
4. Commit the renamed fileset plus that record.

```bash
git clone https://github.com/chipsalliance/caliptra-rtl.git ../caliptra-rtl

./tools/scripts/rename/import_block.sh all --upstream ../caliptra-rtl
./tools/scripts/rename/import_block.sh ecc --upstream ../caliptra-rtl --commit

./tools/scripts/rename/verify_import.sh                        # structural checks
./tools/scripts/rename/roundtrip_check.sh --upstream ../caliptra-rtl
./tools/scripts/rename/upstream_diff.sh  --upstream ../caliptra-rtl   # what changed upstream
```

## Layout

```
src/ecc/              mirrors caliptra-rtl's src/ecc/
  rtl/                synthesizable -- renamed (arca_*)
  coverage/ tb/ formal/ stimulus/ uvmf_ecc/
                      verification collateral -- upstream names kept
  config/arca_ecc_top.vf     generated, compile-ordered filelist
  revinfo.yml         provenance: upstream commit, subtrees, policy, sha256 manifest
  revinfo.map         identifier rename map

src/hmac/  src/hmac_drbg/    same shape; one import owns both

tools/scripts/rename/
  rename_common.sh    shared engine
  rename_ecc.sh       per-block driver: subtrees, filelist, quirks
  rename_hmac.sh
  import_block.sh     runs a driver, then verifies
  verify_import.sh    13 structural checks
  roundtrip_check.sh  strips the prefix, diffs against the upstream blobs
  check_filelists.sh  resolves every path in every .f/.F
  upstream_diff.sh    changelog since the recorded commit
```

`revinfo` lives **inside** the block it describes, so copying `src/ecc/`
anywhere carries the record of where it came from.

## Rename scope: synthesized design material only

The prefix exists to keep ARCA's design namespace from colliding with an SoC
that also integrates upstream Caliptra. Collisions happen in the **netlist**.
Verification collateral is never synthesized, so renaming it buys no safety and
diverges the vendored copy from upstream on every file.

> Rename what is **declared** in synthesizable RTL.
> Rewrite **references** to it everywhere. Rename nothing else.

The two halves are easy to conflate, and the second is why the rename map is
still applied to every vendored file:

| | Declares design names? | Names renamed? | References rewritten? |
|---|---|---|---|
| `rtl/` | yes — the synth tier | **yes** | yes |
| `coverage/` | no — bind code | no | yes (`bind arca_ecc_top`) |
| `tb/` `formal/` | no | no | yes |
| `uvmf_*/uvmf_template_output/` | no | no | yes (`arca_ecc_top` in `hdl_top.sv`) |
| `uvmf_*/<BLOCK>_*.yaml` | no — names UVM *classes* | no | nothing to rewrite |

`hdl_top.sv` keeps its upstream name and instantiates `arca_ecc_top`;
`ecc_top_cov_bind` keeps its name and binds into `arca_ecc_top`. The benches
still drive the vendored RTL without being renamed themselves.

`SYNTH_SUBTREES` defaults to every delivery subtree whose basename is `rtl`,
matching the `VF_FILTER` each driver already declares.

**Payoff: 324 of 427 imported files are byte-identical to upstream**, so the
next merge from caliptra-rtl is a small review rather than a whole-tree one.

### Why the UVMF tree is vendored at all

It looks like a derived artifact you could regenerate. It is not: `hdl_top.sv`
instantiates the DUT inside a `// pragma uvmf custom dut_instantiation`
region, which UVMF *preserves* across regeneration. 152 files across the import
carry such regions. It is generated-then-hand-edited source, so it is vendored,
and its references are rewritten.

The generator inputs (`uvmf_*/<BLOCK>_*.yaml`) need **no exclusion rule**: all
5 per block were scanned against the full rename map (231 ECC / 177 HMAC
identifiers) with the engine's own identifier-boundary regex — zero matches.
They name only UVM classes, which are package-scoped and never enter the map.
`GENERATOR_INPUTS` asserts they stay byte-identical, because the round-trip
strips the prefix before diffing and so cannot see a wrongly-prefixed one.

## The rename engine

`\b` is **not** a correct SystemVerilog identifier boundary — identifiers may
contain `_` and `$`, and escaped identifiers start with `\`. The engine uses
explicit look-around:

```perl
(?<![A-Za-z0-9_$\\]) (ident1|ident2|...) (?![A-Za-z0-9_$])
```

* `` `HMAC_PARAM_PKG `` **is** matched — the backtick is outside the class, so
  macro usages need no separate pass.
* `arca_hmac` is **not** re-matched — the preceding `_` blocks the look-behind,
  making the transform idempotent by construction.
* Renaming module `hmac` never touches `hmac_reg_pkg`, `hmac_core` or
  `hmac_drbg_init`.
* One pass per file, alternation sorted by descending length, so no token is
  rewritten twice.

Two narrower passes follow, because an identifier pass cannot express either:

* `rc_fix_file_references` rewrites references to renamed **file** names
  (`arca_ecc_top.sv` in `.f` lists, `compile.do`, Makefiles). A file stem is not
  an identifier and is not in the map.
* `rc_fix_path_components` reverts the opposite error — a prefixed **directory**
  component in a path string. Several blocks name their top module after their
  folder, so a text pass cannot tell the module `hmac_drbg` from the directory
  `src/hmac_drbg/`, and emits dangling paths:

  ```
  ${CALIPTRA_ROOT}/src/arca_hmac_drbg/rtl/arca_hmac_drbg.sv
                       ^^^^ no such directory   ^^^^ correct
  ```

  It reverts only when the unprefixed directory exists and the prefixed one does
  not, driven by the directory tree rather than the rename map, so a directory
  that genuinely was renamed is left alone. This repaired 48 references.

## Deliberately not prefixed

`kv_defines_pkg`, `kv_read_t`, `kv_write_t`, `kv_error_code_e`,
`` `CALIPTRA_ASSERT_* ``, `caliptra_prim_assert.sv` are **shared platform**
identifiers: ARCA must supply one compatible copy, and prefixing them per-block
would fork the platform. Listed explicitly in each driver's `KEEP_IDENTS` so
the decision is visible rather than implicit.

Build and simulation outputs (`*.ucdb *.vcd *.fsdb *.o *.so *.pyc` …) are
skipped, as are `*_reg_uvm.sv` and `*.rdl` (regenerated from the register spec).

## Verification

`verify_import.sh` — 13 structural checks, no SV parser needed:

1. every synthesizable file name carries the prefix
1b. the ARCA layout mirrors the caliptra-rtl hierarchy
2. every `module`/`package`/`interface`/`program` declared under
   `synth_subtrees` carries the prefix
2b. no declaration **outside** those subtrees carries it — the converse, so the
   scope cannot silently re-widen
3. every `` `define `` in the synth tier carries the macro prefix
4. no double prefixing (`arca_arca_`) — idempotency
5. no original, unprefixed block identifier survives anywhere — the
   load-bearing proof that *references* followed the rename
6. the rename map is injective
7. every `` `include `` resolves, locally or from the platform header list
8. the generated filelist sits in the block's `config/`, covers every source
9. every file still matches the sha256 in revinfo (detects hand-edits)
10. no collateral file name carries the prefix
11. every prefixed path component names a directory that exists
12. collateral-tier summary; checks 2b/4/5 applied there too

`roundtrip_check.sh` is the strongest check: strip the prefix back off and diff
against the upstream git blobs. Anything beyond naming — a dropped line, a
corrupted file, an over-eager substitution — shows up as a diff. Binary files
are compared byte-for-byte; generator inputs are compared **without** stripping.

`check_filelists.sh` resolves every path in every `.f`/`.F`, expanding
`$UVMF_VIP_LIBRARY_HOME` and `$UVMF_PROJECT_DIR` the way the UVMF run scripts
do. The round-trip cannot subsume this: a filelist whose paths all moved can
still round-trip cleanly while pointing at nothing.

CI (`.github/workflows/checks.yml`) runs all of the above, re-runs the import at
the recorded commit and requires a bit-identical tree, and elaborates the
delivery tier with `slang`.

The re-import runs on a different machine than the one that produced the commit,
which makes it a real reproducibility test rather than a self-consistency one.
Two things had to be fixed to pass it: the sorts that order the rename map and
the sha256 manifest are run under `LC_ALL=C`, because glibc's default collation
ignores punctuation and orders `hmac.sv` after `hmac_param_pkg.sv`; and the
upstream branch is declared (`--branch`, default `main`) rather than read from
the clone, which CI has in detached HEAD. `imported_at`, `bash` and `perl`
describe the importing machine and are allowed to differ; nothing else is.

| | ECC | HMAC (+ HMAC_DRBG) |
|---|---|---|
| delivery tier | 25 files | 12 files |
| collateral tier | 191 files, 5 dirs | 193 files, 9 dirs |
| byte-identical to upstream | 158 of 219 | 166 of 208 |
| structural / round-trip / re-import | pass | pass |
| `slang` elaboration | 0 errors, 0 warnings | 0 errors, 0 warnings |

## Updating a block

```bash
./tools/scripts/rename/upstream_diff.sh --upstream ../caliptra-rtl   # review the changelog
git -C ../caliptra-rtl checkout <new-sha>
./tools/scripts/rename/import_block.sh ecc --upstream ../caliptra-rtl --commit
```

The import is idempotent and reproducible, so the diff of that commit is exactly
the upstream delta expressed in ARCA names. Local edits to vendored files are
caught by check 9 — carry them as patches in the driver instead.

## Adding a block

1. `cp tools/scripts/rename/rename_ecc.sh tools/scripts/rename/rename_<block>.sh`
2. Edit `BLOCK`, `UPSTREAM_SUBTREES`, `COLLATERAL_SUBTREES` (plus `DEST_SUBTREES`
   / `BLOCK_DIR` only if ARCA must deviate from the upstream path),
   `VF_FILELIST` / `VF_FILTER`, `EXCLUDE_GLOBS`, `EXTRA_RENAME_IDENTS`,
   `GENERATOR_INPUTS`, `ENV_MACRO_SPECS`, `KEEP_IDENTS`. Document the block's
   quirks in the header comment.
3. `./tools/scripts/rename/import_block.sh <block> --upstream ../caliptra-rtl --commit`

`rename_common.sh` should not need changes for a well-behaved block; if it does,
add a `block_pre_rename` / `block_post_rename` hook in the driver rather than
special-casing the shared engine.

## Known gaps

* No SV parser locally — semantic checking is `slang` in CI only.
* The shared platform library (`kv_*`, `caliptra_prim_*`) is assumed to exist
  once in ARCA at a compatible version. Two blocks needing different versions
  of it is not solved here.
* `src/ecc/coverage/config/*.cfg` name RTL hierarchy paths; they are renamed by
  the identifier pass but not semantically validated.
