#!/usr/bin/env bash
#
# rename_ecc.sh -- import + prefix the caliptra-rtl ECC (secp384r1) engine.
#
#   ./tools/scripts/rename/rename_ecc.sh --upstream /path/to/caliptra-rtl
#
# Layout
# ------
# The ARCA tree mirrors the caliptra-rtl hierarchy, so the correspondence
# between the two trees is 1:1:
#
#   caliptra-rtl                          ARCA
#   src/ecc/rtl/ecc_top.sv            ->  src/ecc/rtl/arca_ecc_top.sv
#   src/ecc/coverage/ecc_top_cov_if.sv -> src/ecc/coverage/arca_ecc_top_cov_if.sv
#   src/ecc/config/ecc_top.vf         ->  src/ecc/config/arca_ecc_top.vf (generated)
#   src/ecc/tb/ecc_top_tb.sv          ->  src/ecc/tb/arca_ecc_top_tb.sv
#   src/ecc/formal/...                ->  src/ecc/formal/...
#   src/ecc/stimulus/...              ->  src/ecc/stimulus/...
#   src/ecc/uvmf_ecc/...              ->  src/ecc/uvmf_ecc/...
#
# The whole src/ecc folder is imported. rtl/ + coverage/ are the *delivery*
# (strict contract, elaborated in CI); tb/, formal/, stimulus/ and uvmf_ecc/
# are *collateral* (same identifier map, looser contract) -- see the "Two
# tiers" section in rename_common.sh.
#
# Block-specific notes
# --------------------
# * ECC lives in a single upstream directory (src/ecc/rtl) but instantiates
#   `hmac_drbg`, which lives in src/hmac_drbg/rtl and is owned by the HMAC
#   import. Ownership policy: hmac_drbg is imported exactly once, by
#   rename_hmac.sh. ECC only rewrites the *reference* so both imports link
#   against the same `<prefix>hmac_drbg` module. See EXTRA_RENAME_IDENTS.
# * ECC guards its packages with hand-written include guards whose names do not
#   follow one pattern (CALIPTRA_ECC_DEFINES, CALIPTRA_ECC_PARAMS_PKG,
#   CALIPTRA_ECC_PM_UOP_PKG, ECC_DSA_UOP_PKG). They are discovered from the
#   sources rather than hard-coded.
# * ecc_reg_uvm.sv is a UVM register model that `includes generated covergroup
#   headers which are not part of the RTL delivery; it is excluded.
# * ecc_reg.rdl is the upstream register description. It is excluded from the
#   renamed fileset because regenerating from it would produce unprefixed RTL;
#   if ARCA ever needs to regenerate, re-run this script afterwards.
# * The coverage/ directory is imported too. It exercises a case the rtl/
#   directories do not: `bind ecc_top ecc_top_cov_if ...` -- the rename engine
#   has to rewrite the bind target as well as the interface name.
# * coverage/config/ecc_cm_hier.cfg IS imported now that the testbench comes
#   along; the hierarchy path it names (ecc_top_tb.dut) is renamed with
#   everything else.
# * src/ecc/config/ is deliberately NOT collateral. ARCA generates its own
#   filelist there, and the upstream ecc_top.vf / ecc_top_tb.vf / compile.yml
#   resolve $COMPILE_ROOT against the caliptra-rtl build environment. Copying
#   them would both collide with the generated arca_ecc_top.vf and re-introduce
#   a dependency on an upstream build system.
# * src/ecc/tb/ecc_secp384r1.exe and the three uvmf .ucdb coverage databases are
#   build/simulation *outputs* checked into upstream. They are skipped by
#   ARTIFACT_GLOBS -- vendoring them would commit stale results.
# * src/ecc/formal/fv_ecc_block_overview.pdf is binary but is documentation,
#   not an output, so it is carried through byte-for-byte.
# * ECC needs no environment configuration macros.

set -euo pipefail

BLOCK="ecc"

UPSTREAM_SUBTREES=(
    "src/ecc/rtl"
    "src/ecc/coverage"
)

# The rest of the src/ecc folder: imported whole, same identifier map, looser
# contract. See "Two tiers" in rename_common.sh.
COLLATERAL_SUBTREES=(
    "src/ecc/tb"
    "src/ecc/coverage/config"
    "src/ecc/formal"
    "src/ecc/stimulus"
    "src/ecc/uvmf_ecc"
)

# Where each upstream subtree lands in ARCA. The identity mapping keeps the
# caliptra-rtl hierarchy; set an explicit path only to shelve the block
# elsewhere, e.g. DEST_SUBTREES=("src/ecc384/rtl" "src/ecc384/coverage").

DEST_SUBTREES=(
    "src/ecc/rtl"
    "src/ecc/coverage"
)

VF_FILELIST="src/ecc/config/ecc_top.vf"
VF_FILTER="/ecc/rtl/"

EXCLUDE_GLOBS=(
    "*_reg_uvm.sv"   # UVM RAL model, depends on generated covergroup headers
    "*.rdl"          # SystemRDL source of the register block, see note above
)

# Cross-block dependency: declared elsewhere, renamed here so the reference
# resolves to the module that rename_hmac.sh publishes.
EXTRA_RENAME_IDENTS=(
    "module:hmac_drbg"
)

ENV_MACRO_SPECS=()
ENV_HEADER_REPLACE=()

# Shared ARCA platform identifiers: version-pinned separately, never prefixed.
KEEP_IDENTS=(
    "kv_defines_pkg"
    "kv_read_t"
    "kv_write_t"
    "kv_error_code_e"
    "uvm_pkg"
)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rename_common.sh"

rc_init "$@"
rc_run
