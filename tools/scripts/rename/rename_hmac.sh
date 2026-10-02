#!/usr/bin/env bash
#
# rename_hmac.sh -- import + prefix the caliptra-rtl HMAC-SHA512 engine
#                   together with the HMAC_DRBG it owns.
#
#   ./tools/scripts/rename/rename_hmac.sh --upstream /path/to/caliptra-rtl
#
# Layout
# ------
# The ARCA tree mirrors the caliptra-rtl hierarchy. Because hmac_drbg is its
# own top-level directory upstream, it stays its own top-level directory here:
#
#   caliptra-rtl                       ARCA
#   src/hmac/rtl/hmac_ctrl.sv      ->  src/hmac/rtl/arca_hmac_ctrl.sv
#   src/hmac/coverage/...          ->  src/hmac/coverage/...
#   src/hmac_drbg/rtl/hmac_drbg.sv ->  src/hmac_drbg/rtl/arca_hmac_drbg.sv
#   src/hmac/config/hmac_ctrl.vf   ->  src/hmac/config/arca_hmac_ctrl.vf (generated)
#
# If ARCA prefers to shelve this engine as "hmac512", set DEST_SUBTREES below.
# The directory name and the identifier prefix are independent knobs.
#
# Block-specific notes
# --------------------
# * Unlike ECC, HMAC spans TWO upstream directories: src/hmac/rtl and
#   src/hmac_drbg/rtl. hmac_drbg is deliberately owned by this import because
#   both HMAC and ECC instantiate it; importing it once avoids two divergent
#   copies in the ARCA netlist.
# * `hmac` is an extremely short module name. The rename engine uses explicit
#   SystemVerilog identifier boundaries -- (?<![A-Za-z0-9_$\]) / (?![A-Za-z0-9_$])
#   -- so `hmac_reg_pkg`, `hmac_core` and `ecc_hmac_drbg_interface` are never
#   partially rewritten. A plain `\b` would not be safe enough here.
# * HMAC is the one block that consumes an *environment* configuration macro:
#   `CLP_CSR_HMAC_KEY_DWORDS`, supplied by caliptra-rtl's global
#   src/libs/rtl/caliptra_macros.svh. The import captures that macro into a
#   generated, prefixed, block-private header and redirects the `include, so
#   the vendored block no longer reaches into caliptra-rtl global headers.
# * hmac_reg_uvm.sv and hmac_reg.rdl are excluded for the same reasons as ECC.
# * coverage/ is imported; coverage/config/*.cfg is not (it names a testbench
#   hierarchy that is out of scope for this import).

set -euo pipefail

BLOCK="hmac"

UPSTREAM_SUBTREES=(
    "src/hmac/rtl"
    "src/hmac/coverage"
    "src/hmac_drbg/rtl"
    "src/hmac_drbg/coverage"
)

# Identity mapping: ARCA mirrors caliptra-rtl. To shelve the engine under
# src/hmac512/ instead, change the first two entries to
#   "src/hmac512/rtl" "src/hmac512/coverage"
# and set BLOCK_DIR="src/hmac512". hmac_drbg keeps its own directory either way.
# The rest of both block folders. src/hmac/config and src/hmac_drbg/config stay
# out: ARCA generates its own filelist there and the upstream .vf/compile.yml
# resolve $COMPILE_ROOT against the caliptra-rtl build environment.
COLLATERAL_SUBTREES=(
    "src/hmac/tb"
    "src/hmac/coverage/config"
    "src/hmac/formal"
    "src/hmac/stimulus"
    "src/hmac/uvmf_2022"
    "src/hmac_drbg/tb"
    "src/hmac_drbg/coverage/config"
    "src/hmac_drbg/formal"
    "src/hmac_drbg/stimulus"
)

DEST_SUBTREES=(
    "src/hmac/rtl"
    "src/hmac/coverage"
    "src/hmac_drbg/rtl"
    "src/hmac_drbg/coverage"
)

VF_FILELIST="src/hmac/config/hmac_ctrl.vf"
VF_FILTER="/hmac(_drbg)?/rtl/"

EXCLUDE_GLOBS=(
    "*_reg_uvm.sv"
    "*.rdl"
)

EXTRA_RENAME_IDENTS=()

# Macros the caliptra-rtl environment applies to configure this block.
# Format: MACRO@<upstream path of the header that defines it>
# UVMF generator inputs. These describe the verification environment -- agents,
# environments, interface ports -- and name nothing that the rename map
# touches: UVM agents and environments become SystemVerilog *classes*, which
# are scoped by their package rather than by the compilation unit. So they come
# through byte-identical, and regenerating upstream stays possible.
#
# roundtrip_check.sh asserts byte-identity for these specifically, rather than
# the naming-only equivalence it asserts everywhere else.
GENERATOR_INPUTS=(
    "src/hmac/uvmf_2022/HMAC_bench.yaml"
    "src/hmac/uvmf_2022/HMAC_environment.yaml"
    "src/hmac/uvmf_2022/HMAC_in_interface.yaml"
    "src/hmac/uvmf_2022/HMAC_out_interface.yaml"
    "src/hmac/uvmf_2022/HMAC_util_comp_HMAC_predictor.yaml"
)

ENV_MACRO_SPECS=(
    "CLP_CSR_HMAC_KEY_DWORDS@src/libs/rtl/caliptra_macros.svh"
)

# `include directives redirected to the generated block-private config header.
ENV_HEADER_REPLACE=(
    "caliptra_macros.svh"
)

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
