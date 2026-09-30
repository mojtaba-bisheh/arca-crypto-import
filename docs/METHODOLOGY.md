# Methodology

Design notes for the ARCA crypto-block import flow. The `README.md` covers how
to *run* it; this file covers *why* it is shaped the way it is, and what the
open risks are.

---

## 1. Requirements this flow implements

From the engineering lead, modelled on VeeR-EL2's `tools/prefix_macros.sh`:

1. Copy the entire block locally into ARCA.
2. A renaming script that applies new prefixes to modules, packages, and any
   macros the environment applies to configure the block.
3. Save a file recording which caliptra-rtl git commit the block came from, so
   the upstream changelog can be reviewed when pulling updates.
4. Commit the renamed fileset + revinfo file.
5. One renaming script per crypto block, under `tools/scripts/` (in a
   subdirectory), because the blocks differ in edge cases, macro names and
   directory hierarchies.

Mapping to this repo:

| Requirement | Where |
|---|---|
| 1 | `rename_common.sh:rc_stage`, output under `rtl/<block>/` |
| 2 | `rename_common.sh:rc_build_map` + `lib/apply_map.pl` + `rc_env_macros` |
| 3 | `rename_common.sh:rc_emit_revinfo` → `revinfo/<block>.revinfo.yml`; consumed by `upstream_diff.sh` |
| 4 | `import_block.sh --commit` |
| 5 | `tools/scripts/rename/rename_<block>.sh`, one per block |

---

## 2. What differs from VeeR's `prefix_macros.sh`

VeeR's script is a sequence of ~25 in-place `sed`/`perl` passes over the design
directory. It works for VeeR, but it has properties that are uncomfortable for
a security IP import:

| VeeR approach | Here | Why |
|---|---|---|
| Many sequential in-place passes | One pass per file over a complete map | Sequential passes can re-rename an already-renamed token, and the outcome depends on pass order. |
| Renames in place, in the source tree | Renames in a temp staging dir, then installs | The upstream checkout is never mutated, so the import is repeatable and `git status` upstream stays clean. |
| `\b` / ad-hoc `[^A-Za-z0-9_]` boundaries | `(?<![A-Za-z0-9_$\\]) … (?![A-Za-z0-9_$])` | `$` is a legal SV identifier character and escaped identifiers start with `\`. |
| Hard-codes macro names (`EL2_IC_TAG_SRAM`, …) | Discovers declarations from the staged sources; drivers only declare what *cannot* be discovered | Upstream adding a new package or guard macro does not silently escape the rename. |
| No provenance record | `revinfo/<block>.revinfo.yml` | Requirement 3. |
| No verification | 9 structural checks + a round-trip proof + CI re-import | See §5. |

---

## 3. Ownership model

Three classes of identifier:

### Block-owned — always prefixed
Anything declared inside the imported subtrees: `module`, `package`,
`interface`, `` `define ``. Discovered automatically, never hard-coded.

### Cross-block — prefixed, owned by exactly one import
`hmac_drbg` is declared in `src/hmac_drbg/rtl` and instantiated by **both**
HMAC and ECC.

Policy: **HMAC owns it.** `rename_hmac.sh` imports the file; `rename_ecc.sh`
only lists `module:hmac_drbg` in `EXTRA_RENAME_IDENTS` so the *reference* is
rewritten to the same `arca_hmac_drbg`. The alternative — a private copy per
block (`arca_ecc_hmac_drbg`, `arca_hmac_hmac_drbg`) — was rejected: two copies
of a DRBG in one RoT netlist is a security review liability, not a convenience.

If ARCA ever wants private copies, change the policy by adding
`src/hmac_drbg/rtl` to `rename_ecc.sh:UPSTREAM_SUBTREES` and removing the
`EXTRA_RENAME_IDENTS` entry — but then also give the two blocks different
prefixes.

### Shared platform library — deliberately NOT prefixed
`kv_defines_pkg`, `kv_read_t`, `kv_write_t`, `` `CALIPTRA_KV_*_REG2STRUCT ``,
`` `CALIPTRA_ASSERT_* ``, `caliptra_prim_assert.sv`, `uvm_pkg`.

<a name="shared-platform-library"></a>
**This is a real assumption, and it must be stated explicitly:** the keep-list
is only correct if ARCA provides exactly **one** canonical, compatible copy of
the shared Caliptra libraries for all vendored blocks. If two imported blocks
ever need *different* versions of `kv_defines_pkg` (e.g. a changed `kv_read_t`
layout), the keep-list stops protecting you and those libraries must be
vendored and prefixed per block too.

Recommended follow-up for the real ARCA tree: import the shared library as its
own "block" with its own revinfo and version pin, even if it is not prefixed.
`verify_import.sh` already lists the platform headers it is willing to resolve
externally (`PLATFORM_HEADERS`), so the assumption is at least machine-checked.

---

## 4. Exclusions, and why

| Pattern | Reason |
|---|---|
| `*_reg_uvm.sv` | UVM RAL model. `` `include``s generated covergroup/sample headers that are not part of the RTL delivery, and pulls in `uvm_pkg`. Not needed for synthesis or for a netlist-level import. Re-enable by dropping it from `EXCLUDE_GLOBS` **and** importing the generated `.svh` files. |
| `*.rdl` | SystemRDL source for the register block. Deliberately **not** committed next to the renamed RTL: regenerating from it with PeakRDL would emit *unprefixed* `<block>_reg.sv` and silently diverge from the committed fileset. The generated `<block>_reg.sv` / `<block>_reg_pkg.sv` are imported instead. If ARCA needs to regenerate, regenerate upstream first, then re-run the import. |

Both exclusions are recorded in `revinfo/<block>.revinfo.yml` under
`policy.excluded_globs`, so the decision is visible in the artifact and not
just in this document.

---

## 5. Verification strategy

No SystemVerilog parser is assumed on a developer machine, so the local checks
are structural. They are still fairly strong:

`verify_import.sh` (runs automatically at the end of every import, and in CI):

1. every file name carries the prefix
2. every `module` / `package` / `interface` declaration carries the prefix
3. every `` `define `` carries the macro prefix
4. no double prefixing (`arca_arca_`) — idempotency
5. no original, unprefixed block identifier survives anywhere
6. the rename map is injective (no two originals collapse onto one name)
7. every `` `include `` target resolves, either locally or from the declared
   shared platform header list
8. the generated filelist covers every source and every entry exists
9. every committed file still matches the sha256 recorded in revinfo
   (detects hand-edits after import)

`roundtrip_check.sh` — the strongest one. Strips the prefix back off and diffs
against the exact upstream blob at the recorded commit. Only `` `include ``
redirections (the deliberate env-macro capture) are tolerated. This proves the
import is a **pure token substitution**: no logic edits, no dropped lines, no
mangled string literals.

CI (`.github/workflows/checks.yml`) adds:

* **reimport** — re-runs the import at the recorded commit and fails if the
  result differs from what is committed. Reproducibility.
* **lint** — builds `slang` and parses each generated filelist, pulling the
  shared platform library from upstream. Marked `continue-on-error` in this
  example repo because the shared library is not vendored here; in the real
  ARCA tree it should be a hard gate.

---

## 6. Provenance record

`revinfo/<block>.revinfo.yml` is generated, never hand-edited. It carries:

* upstream repo URL, branch, commit SHA, commit date, commit subject
* whether the upstream working tree was dirty at import time
* the subtrees imported and the upstream `.vf` used for compile order
* prefix and macro prefix
* importer script name, library version, a fingerprint over
  (driver + `rename_common.sh` + `apply_map.pl`), bash and perl versions
* policy: excluded globs, cross-block identifiers, environment config macros,
  keep-list
* sha256 manifest of the **upstream** files as imported
* sha256 manifest of the **committed, renamed** files

The header of the file contains the exact command to review upstream changes:

```
git -C <caliptra-rtl> log --oneline <sha>..origin/main -- src/ecc/rtl
```

which is what `upstream_diff.sh` automates.

The full identifier table lives next to it in `revinfo/<block>.map`
(`kind <TAB> original <TAB> renamed`) so a reviewer never has to reverse
engineer the script to know what a name used to be.

---

## 7. Update workflow

```bash
make updates UPSTREAM=~/src/caliptra-rtl        # review the changelog
make import-ecc UPSTREAM=~/src/caliptra-rtl     # re-import
make roundtrip UPSTREAM=~/src/caliptra-rtl      # re-prove naming-only
git diff -- rtl/ecc                             # review as a normal RTL diff
./tools/scripts/rename/import_block.sh ecc --commit
```

Because the rename is deterministic and idempotent, `git diff -- rtl/ecc` after
a re-import shows exactly the upstream change, expressed in ARCA names. That is
the property that makes this maintainable over multiple upstream releases.

---

## 8. Known gaps

* **No semantic verification locally.** Structural checks plus the round-trip
  proof catch substitution errors, but only a real front end catches, say, a
  package compile-order problem in the generated filelist. The `slang` CI job
  should become a hard gate once the shared platform library is vendored.
* **Comments and string literals are rewritten** along with code. This is
  intentional (a comment referring to `hmac_drbg` should refer to
  `arca_hmac_drbg`), but it means `$display` output text changes too. No
  `$readmemh`/`$fopen` file-path literals exist in ECC/HMAC, so nothing breaks
  today — a future block with data-file loads needs a check for that.
* **The shared platform library is not vendored here.** See §3.
* **`.rdl` regeneration is out of band.** See §4.
