# ARCA — vendored Caliptra crypto blocks (worked example)

Reference implementation of how **ARCA** imports crypto engines from
[`chipsalliance/caliptra-rtl`](https://github.com/chipsalliance/caliptra-rtl),
following the same idea as VeeR-EL2's
[`tools/prefix_macros.sh`](https://github.com/chipsalliance/Cores-VeeR-EL2/blob/main/tools/prefix_macros.sh):

> copy the block locally → prefix every name the block owns → record where it
> came from → commit the result.

Two engines are imported end to end as worked examples: **ECC** (secp384r1) and
**HMAC** (HMAC-SHA512, including the HMAC_DRBG it owns).

Everything under `src/` and `revinfo/` in this repo is **generated** by the
scripts in `tools/scripts/rename/` and committed as-is.

**The ARCA tree mirrors the caliptra-rtl hierarchy.** A block is imported as a
whole directory — `src/ecc/{rtl,coverage,config}` upstream becomes
`src/ecc/{rtl,coverage,config}` in ARCA, with every file inside renamed. That
keeps upstream paths, ARCA paths and `git log` paths 1:1, which is what makes
the "review the changelog, then re-import" loop cheap.

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

The imported blocks keep their upstream paths, so `src/<block>/<subdir>/` in
caliptra-rtl lands at `src/<block>/<subdir>/` in ARCA:

| caliptra-rtl | ARCA | contents |
|---|---|---|
| `src/ecc/rtl/` | `src/ecc/rtl/` | 23 renamed `.sv` |
| `src/ecc/coverage/` | `src/ecc/coverage/` | `arca_ecc_top_cov_{bind,if}.sv` |
| `src/ecc/config/ecc_top.vf` | `src/ecc/config/arca_ecc_top.vf` | generated compile order |
| `src/hmac/rtl/` | `src/hmac/rtl/` | 7 renamed `.sv` + generated `arca_hmac_config.svh` |
| `src/hmac/coverage/` | `src/hmac/coverage/` | `arca_hmac_ctrl_cov_{bind,if}.sv` |
| `src/hmac/config/hmac_ctrl.vf` | `src/hmac/config/arca_hmac_ctrl.vf` | generated compile order |
| `src/hmac_drbg/rtl/` | `src/hmac_drbg/rtl/` | owned by the HMAC import |
| `src/hmac_drbg/coverage/` | `src/hmac_drbg/coverage/` | |
| `src/<block>/tb/` | `src/<block>/tb/` | block testbenches + vectors |
| `src/<block>/formal/` | `src/<block>/formal/` | formal properties, `.pdf` overview |
| `src/<block>/stimulus/` | `src/<block>/stimulus/` | test vectors |
| `src/ecc/uvmf_ecc/`, `src/hmac/uvmf_2022/` | same | generated UVMF environment |

```
src/
  ecc/       rtl/ coverage/ config/    delivery tier: generated, prefixed ECC fileset
             tb/ formal/ stimulus/ uvmf_ecc/     collateral tier
  hmac/      rtl/ coverage/ config/    delivery tier: generated, prefixed HMAC fileset
             tb/ formal/ stimulus/ uvmf_2022/    collateral tier
  hmac_drbg/ rtl/ coverage/            imported by HMAC, referenced by ECC
             tb/ formal/ stimulus/
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

`revinfo/` stays at the repo root on purpose: it is ARCA import *metadata*, not
upstream content, so it must not shadow a real caliptra-rtl path.

The destination path is a **separate knob** from the identifier prefix. A
driver sets `UPSTREAM_SUBTREES` and, if ARCA must land the block somewhere
else, `DEST_SUBTREES` + `BLOCK_DIR`. Renaming the HMAC directory to
`src/hmac512/` while keeping `arca_hmac*` module names is a two-line change in
`rename_hmac.sh` — documented in that script's header.

---

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

## The whole block folder is imported — in two tiers

The requirement was "copy the entire block", not "copy the RTL", so the import
takes **everything under `src/<block>/`**: `rtl/`, `coverage/`, `tb/`,
`formal/`, `stimulus/` and the generated UVMF environment. Over 400 files per
import, not 36.

The two tiers differ in how strict the rename contract is, not in whether the
files are carried:

| | **delivery tier** | **collateral tier** |
|---|---|---|
| driver knob | `UPSTREAM_SUBTREES` | `COLLATERAL_SUBTREES` |
| what | `rtl/`, `coverage/` | `tb/`, `formal/`, `stimulus/`, `uvmf_*/`, `coverage/config/` |
| identifier rename | yes, same map | yes, **same map** — so the testbench still binds to the renamed RTL |
| file names | *every* file is prefixed | every **HDL source** (`*.sv *.svh *.v *.vh`) is prefixed; other files only when the stem is a renamed identifier, so `Makefile`, `compile.do` and the UVMF `.yaml` keep their names |
| directory names | unchanged (block dirs mirror upstream) | prefixed when the directory is *named after* a renamed package — UVMF's `interface_packages/ECC_out_pkg/` becomes `arca_ECC_out_pkg/` so the generated `.f` lists still resolve |
| flat-namespace guarantee | asserted (unique basenames, every `` `include `` resolves, covered by the generated `.vf`) | not asserted — upstream deliberately reuses `Makefile`, `compile.do`, `.project` across directories |
| CI | elaborated by `slang` | carried and round-tripped, not elaborated (needs UVM + a simulator licence) |
| round-trip proof | yes | yes |

Two things are still *not* vendored, on purpose:

* **Build and simulation outputs** — `ARTIFACT_GLOBS` skips `*.ucdb`, `*.exe`,
  `*.o`, `*.wlf`, `*.vcd`, `*.fsdb`, … Upstream checks a few of these in
  (`src/ecc/tb/ecc_secp384r1.exe`, three `.ucdb` under `uvmf_ecc/.../sim/`);
  vendoring them would commit stale results and bloat the history. Everything
  needed to *regenerate* them is imported.
* **Upstream `config/`** — the `.vf` / `compile.yml` there resolve
  `$COMPILE_ROOT` and `$MSFT_REPO_ROOT` against the caliptra-rtl build
  environment, and ARCA generates its own `arca_*.vf` into that directory.

Binary files that are *documentation* rather than output — e.g.
`src/ecc/formal/fv_ecc_block_overview.pdf` — are carried through byte-for-byte
and `cmp`-checked by the round-trip.

After the renames, a final pass rewrites every *reference to a file by name* —
`` `include `` directives, UVMF `.f` filelists, `compile.do` scripts — so the
collateral still points at the files that now exist. `verify_import.sh` asserts
that **no HDL source anywhere in the import is left without the prefix**.

`--no-collateral` imports the delivery tier only, if a consumer wants just the
synthesisable fileset.

---

## What gets renamed: only synthesized design material

A fair question when you first see the import touch `tb/`, `formal/` and the
UVMF tree: *shouldn't the rename stop at `rtl/`?*

Yes — for *declarations*. The prefix exists to keep ARCA's design namespace from
colliding with an SoC that also integrates upstream Caliptra. Collisions happen
in the **netlist**. Verification collateral is never synthesized, so it cannot
collide there, and renaming it buys nothing while gratuitously diverging the
vendored copy from upstream.

So the scope is one rule:

> **Rename what is *declared* in synthesizable RTL.
> Rewrite *references* to it everywhere. Rename nothing else.**

The two halves are easy to conflate, and the second is why the rename map is
still applied to every vendored file:

| Directory | Declares design names? | Names renamed? | References rewritten? |
|---|---|---|---|
| `rtl/` | yes — this is the synth tier | **yes** | yes |
| `coverage/` | no — bind code, never synthesized | no | yes (`bind arca_ecc_top`) |
| `tb/` | no | no | yes |
| `formal/` | no | no | yes |
| `uvmf_*/uvmf_template_output/` | no | no | yes (`arca_ecc_top` in `hdl_top.sv`) |
| `uvmf_*/<BLOCK>_*.yaml` | no — names UVM *classes* | no | nothing to rewrite |

`hdl_top.sv` keeps its upstream file and module name and instantiates
`arca_ecc_top`. `ecc_top_cov_bind` keeps its name and binds into
`arca_ecc_top`. That is the policy in two lines of evidence.

The payoff is measurable: **324 of 423 imported files are now byte-identical to
upstream.** Only files that genuinely name RTL differ, which makes the next
upstream merge a much smaller review.

### The YAML needs no exclusion rule

It is tempting to special-case `uvmf_*/<BLOCK>_*.yaml` in the script. We checked
instead: the 5 generator YAMLs per block were scanned against the full rename
map (231 ECC / 177 HMAC identifiers) with the engine's own identifier-boundary
regex — **zero matches**. The YAML names only UVM classes, which are scoped by
their package and never enter the map. It survives byte-identical because the
rule already excludes it, not because of an exception.

What *is* needed is an assertion that it stays that way, since the round-trip
strips the prefix before diffing and therefore cannot see a wrongly-prefixed
generator input. `GENERATOR_INPUTS` + a no-stripping `cmp` closes that gap.

### Path components are not identifiers

Several blocks name their top module after their folder, so a text pass cannot
tell the module `hmac_drbg` from the directory `src/hmac_drbg/`. Left alone the
engine emits dangling paths:

```
${CALIPTRA_ROOT}/src/arca_hmac_drbg/rtl/arca_hmac_drbg.sv
                     ^^^^ no such directory   ^^^^ correct
```

`rc_fix_path_components` reverts a prefixed path component when the unprefixed
directory exists and the prefixed one does not — driven by the tree produced,
not by the rename map, so a directory that really was renamed is left alone.
This repaired **48 references** across the two blocks. Nothing else caught them:
`check_filelists.sh` skips `${CALIPTRA_ROOT}`-rooted entries as external, and
the round-trip strips the prefix before diffing, so the dangling form compared
*equal* to upstream. Check 11 in `verify_import.sh` now pins it.

## Generated verification IP (UVMF) — does renaming break it?

Short answer: no, and the generator still works — but the generated tree is
*not* a throwaway derived artifact, which is the part that is easy to get
wrong.

The UVMF benches under `src/ecc/uvmf_ecc/` and `src/hmac/uvmf_2022/` are machine
generated. Two things live side by side there:

| | what it is | what the import does to it |
|---|---|---|
| `<BLOCK>_bench.yaml`, `<BLOCK>_environment.yaml`, `<BLOCK>_*_interface.yaml` | the generator **inputs** | nothing — all 10 are **byte-identical** to upstream |
| `uvmf_template_output/` | generated **and then hand-edited** (see below) | fully renamed: packages, interfaces, modules, file names, package directories, and every `.f` / `.vinfo` / `Makefile` / `compile.do` reference to them |

**Why the inputs are untouched.** They describe UVM *components* — `top_env: ECC`,
`bfm_name: ECC_in_agent`. Those become SystemVerilog **class** names, and classes
are not in SystemVerilog's global namespace; they are scoped by the package that
holds them. The rename map only carries `module`, `package`, `interface` and
`` `define ``, so the YAML has nothing in it to rewrite. That is deliberate, and
it has a useful side effect: `+UVM_TESTNAME=test_top` and the `testlist` entries
keep working, because the class is still `test_top` — it just lives in
`arca_ECC_tests_pkg` now.

The result, measured on the current import:

```
$ grep -rhoP '^\s*(module|package|interface|program)\s+\K\w+' src --include=*.sv --include=*.svh \
    | sort -u | grep -cv '^arca_'
0          # zero unprefixed global-namespace declarations, anywhere
$ grep -rhoP '^\s*(virtual\s+)?class\s+\K\w+' src --include=*.sv --include=*.svh | sort -u | grep -cv '^arca_'
71         # UVM classes keep upstream names — scoped by prefixed packages
```

**The generated tree is also hand-edited, so it is source.** UVMF emits
`// pragma uvmf custom <name> begin` / `end` regions and *preserves their
contents* across regeneration. They are where a human fills in what the YAML
cannot describe — above all the DUT itself:

```systemverilog
// src/ecc/uvmf_ecc/uvmf_template_output/project_benches/ECC/tb/testbench/arca_hdl_top.sv
  // pragma uvmf custom dut_instantiation begin
  arca_ecc_top #( .AHB_DATA_WIDTH(64), .AHB_ADDR_WIDTH(15) ) dut ( ... );
  arca_ecc_top_cov_bind i_ecc_top_cov_bind();
  // pragma uvmf custom dut_instantiation end
```

76 files under `src/ecc/uvmf_ecc/` carry such regions (152 across the whole
import). Three consequences, and they are the reason the scope is what it is:

1. **It must be vendored.** Regenerating from the YAML alone does not produce a
   working bench — it produces a bench with an empty `dut_instantiation`.
2. **It must be renamed.** Those custom regions name `ecc_top`,
   `ecc_top_cov_bind`, `ecc_defines_pkg` — all renamed. Carry them verbatim and
   the bench does not bind to the RTL we actually vendored.
3. **Renaming the YAML roots would not help.** The tempting alternative is to
   rename `"ECC_in"` → `"arca_ECC_in"` in the inputs so the generator emits
   prefixed names natively and the post-hoc pass disappears. It doesn't
   disappear: the hand-written custom regions still contain unprefixed RTL
   identifiers, which no generator will fix. That option adds a second naming
   scheme and removes nothing.

**Byte-identity of the inputs is checked, not assumed.** The round-trip check
structurally *cannot* police this: it strips the prefix before comparing, so a
`.yaml` wrongly renamed to `arca_ECC_in` strips straight back to `ECC_in` and
passes — while the next regeneration would silently emit names disagreeing with
what is committed. Each block driver therefore declares its generator inputs:

```bash
# tools/scripts/rename/rename_ecc.sh
GENERATOR_INPUTS=(
    "src/ecc/uvmf_ecc/ECC_bench.yaml"
    ...
)
```

and they are compared to upstream with `cmp` — no prefix stripping — at import
time and again in `roundtrip_check.sh`:

```
  ok    5 generator input(s) byte-identical to upstream
```

**Package directories follow their package.** UVMF names a VIP directory after
the package it holds and then refers to it by that literal path:

```
$UVMF_VIP_LIBRARY_HOME/interface_packages/ECC_in_pkg/ECC_in_pkg.sv
```

The identifier pass rewrites `ECC_in_pkg` in that string whether we like it or
not, so the directory has to move to `arca_ECC_in_pkg/` or every filelist
dangles. It does, and the `Makefile`, `compile.do`, `.f`, `.F` and `.vinfo`
references all follow.

**Regeneration workflow.** Do *not* re-run `uvmf_gen` inside ARCA — the inputs
are upstream-named, so it would emit `interface_packages/ECC_in_pkg/` next to
the renamed tree. Instead:

1. regenerate upstream (or in a scratch clone of caliptra-rtl),
2. re-run `import_block.sh <block> --upstream <that tree>`.

Hand edits to the custom regions belong upstream too, for the same reason.
Nothing under `src/` is ever hand-edited *in ARCA*; the `import is reproducible` CI job
re-runs the whole import from upstream and asserts a zero diff, which is what
makes that rule enforceable rather than aspirational.

**What is and isn't proven.** The delivery tier (`rtl/`, `coverage/`) is
elaborated by slang in CI, so for that tier "it compiles" is a fact. The UVMF
collateral is *structurally* verified but not simulated — that needs UVM and a
licensed simulator. Call it reference-consistent, not sim-proven.

"Reference-consistent" is enforced rather than asserted. `check_filelists.sh`
resolves every path named by every `.f` / `.F` in the import — expanding
`$UVMF_VIP_LIBRARY_HOME` and `$UVMF_PROJECT_DIR` the way the UVMF run scripts
do, skipping `${UVM_HOME}` and `uvmf_base_pkg` as external — and fails if any
of them names a file that is not there:

```
$ make verify
  ok    36 vendored path(s) in 24 UVMF filelist(s) all resolve (8 external ref(s) skipped)
```

This is the check that would have caught the dangling `interface_packages/`
path described above, and it is the one check the round-trip *cannot* catch: a
consistently-wrong path still strips back to the correct upstream one.

## What the import actually does

| Step | What happens |
|------|--------------|
| 1. stage | Upstream subtrees are copied into a temp dir — delivery tier flattened per subtree, collateral tier recursively, preserving paths. `*_reg_uvm.sv` and `*.rdl` are excluded (see [METHODOLOGY](docs/METHODOLOGY.md)). sha256 of every source file is recorded. |
| 2. map | Every `module` / `package` / `interface` / `` `define `` declared *inside* the block is collected, plus driver-declared cross-block identifiers and environment config macros. The keep-list (shared platform identifiers) is subtracted. Result: `revinfo/<block>.map`. |
| 3. apply | One Perl pass per file over the whole map, alternation sorted longest-first, with SystemVerilog identifier boundaries. |
| 4. env macros | Macros the caliptra-rtl *environment* supplied are captured into a generated block-private header (`arca_hmac_config.svh`) and the `` `include `` is redirected there. |
| 5. file rename | Every file gets the prefix; `` `include `` references were already rewritten in step 3. |
| 6. filelist | A compile-ordered `.vf` is generated *where upstream keeps it* — `src/<block>/config/arca_<name>.vf` — ordering derived from the upstream `.vf`, with `+incdir+` lines for every imported directory. |
| 7. revinfo | `revinfo/<block>.revinfo.yml` records upstream repo/branch/commit/date/subject, dirty flag, subtrees, prefix, script fingerprint, policy (exclusions, keep-list, cross-block deps, env macros) and sha256 manifests before *and* after renaming. |
| 8. verify | 11 structural checks (including "the ARCA layout mirrors the caliptra-rtl hierarchy" and a collateral-tier consistency summary), then the round-trip proof over **both** tiers. |

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

Two narrower passes run afterwards, because a single identifier pass cannot
express either of them:

* `rc_fix_file_references` rewrites references to *file* names
  (`fv_add_sub_alter_coverpoints.sv`). A file stem is not an identifier and is
  not in the map; the name is matched together with its extension, under a
  deliberately looser look-behind so a `/` may precede it.
* `rc_fix_path_components` reverts the opposite error — a prefixed *directory*
  component in a path string, where the identifier pass could not tell the
  module `hmac_drbg` from the folder `src/hmac_drbg/`. It reverts only when the
  unprefixed directory exists and the prefixed one does not.

### The strongest check: round-trip

`roundtrip_check.sh` strips the prefix back off every committed file and diffs
it against the exact upstream blob at the commit recorded in `revinfo/`:

```
== ecc (upstream 9d6585080a35, prefix arca_) ==
  ok    1 binary file(s) carried byte-for-byte
  -- 215 file(s) round-tripped

== hmac (upstream 9d6585080a35, prefix arca_) ==
  ok    src/hmac/rtl/hmac_ctrl.sv (include redirected on purpose)
  ok    src/hmac/rtl/hmac.sv (include redirected on purpose)
  -- 204 file(s) round-tripped

roundtrip_check: imported RTL differs from upstream by naming only
```

Only the interesting lines are printed: a clean file is silent, the two HMAC
`` `include `` redirections are the deliberate env-macro capture, and the one
binary is `fv_ecc_block_overview.pdf`.

That is the property that matters for a security IP import: the vendored RTL
differs from upstream by **names only** — no stray logic edits, no dropped
lines, no mangled string literals.

---

## Interesting cases these two blocks already exercise

* **Cross-block ownership.** ECC instantiates `hmac_drbg`, which lives in a
  different upstream directory. Policy: HMAC owns it and imports it once; ECC
  only rewrites the *reference*. Both land on `arca_hmac_drbg`, so the netlist
  has exactly one copy. Declared in `rename_ecc.sh:EXTRA_RENAME_IDENTS`.
* **Multiple upstream directories per block.** HMAC spans four upstream
  directories — `src/hmac/{rtl,coverage}` and `src/hmac_drbg/{rtl,coverage}` —
  and all four are mirrored into ARCA at the same paths.
* **`bind` targets.** The coverage files carry
  `bind ecc_top ecc_top_cov_if i_ecc_top_cov_if (.*);`. Both the bound-to
  module and the interface are block-owned, so both get prefixed
  (`bind arca_ecc_top arca_ecc_top_cov_if ...`) while the *instance* name is
  left alone — it is local to the bind, not part of the global namespace.
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
2. Edit `BLOCK`, `UPSTREAM_SUBTREES`, `COLLATERAL_SUBTREES` (plus `DEST_SUBTREES` / `BLOCK_DIR` only if
   ARCA must deviate from the upstream path), `VF_FILELIST` / `VF_FILTER`,
   `EXCLUDE_GLOBS`, `EXTRA_RENAME_IDENTS`, `ENV_MACRO_SPECS`, `KEEP_IDENTS`.
   Document the block's quirks and its path mapping in the header comment.
3. `./tools/scripts/rename/import_block.sh <block> --commit`
4. Add the block to `BLOCKS` in the `Makefile`.

No changes to `rename_common.sh` should be needed for a well-behaved block; if
they are, add a `block_pre_rename` / `block_post_rename` hook in the driver
rather than special-casing the shared library.

---

## Status

This is an example repository used to agree on the methodology before applying
it to the real ARCA tree. It is not a product deliverable.

Current state of the two imported blocks, all enforced in CI
(`.github/workflows/checks.yml`):

| Check | ECC | HMAC (+ HMAC_DRBG) |
|---|---|---|
| delivery tier | 25 files | 12 files |
| collateral tier | 191 files in 5 dirs (4 build artifacts skipped) | 193 files in 9 dirs |
| structural verification (13 checks) | pass | pass |
| files byte-identical to upstream | 158 of 217 | 166 of 206 |
| round-trip vs upstream blobs | pass, 215 files | pass, 204 files |
| generator inputs byte-identical | pass, 5 files | pass, 5 files |
| re-import reproducibility | pass | pass |
| `slang` elaboration (delivery tier) | 0 errors, 0 warnings | 0 errors, 0 warnings |

See [`docs/METHODOLOGY.md`](docs/METHODOLOGY.md) for the design rationale,
the ownership policy, and the known gaps.
