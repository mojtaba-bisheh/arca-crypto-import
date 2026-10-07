#!/usr/bin/env bash
#
# rename_hmac512.sh -- import + prefix the caliptra-rtl HMAC-SHA512 engine
#                      together with the HMAC_DRBG it owns.
#
#   ./tools/scripts/rename/rename_hmac512.sh --upstream /path/to/caliptra-rtl
#
# Layout
# ------
# This is the one block whose Tessera layout deliberately does *not* mirror
# caliptra-rtl. Upstream calls the SHA-512 HMAC engine plain "hmac" and the
# SHA-256 one "hmac256", so a faithful import would put tessera_hmac_core next to
# tessera_hmac256_core and leave the shorter name as the ambiguous one. Tessera
# shelves it as hmac512 -- directory and identifier stem together, because a
# directory named hmac512 full of tessera_hmac_* modules is no clearer than what
# it replaced.
#
#   caliptra-rtl                       Tessera
#   src/hmac/rtl/hmac_ctrl.sv      ->  src/hmac512/rtl/tessera_hmac512_ctrl.sv
#   src/hmac/coverage/...          ->  src/hmac512/coverage/...
#   src/hmac/uvmf_2022/...         ->  src/hmac512/uvmf_2022/...
#   src/hmac_drbg/rtl/hmac_drbg.sv ->  src/hmac_drbg/rtl/tessera_hmac_drbg.sv
#   src/hmac/config/hmac_ctrl.vf   ->  src/hmac512/config/tessera_hmac512_ctrl.vf (generated)
#
# The stem rewrite itself is declared repo-wide in rename_common.sh
# (RC_DEFAULT_STEM_RENAMES), not here, because ECC imports hmac_param_pkg and
# has to spell the renamed package exactly the same way. hmac_drbg is on the
# keep list: it is a DRBG shared with ECC, not a SHA-512 HMAC, so it keeps its
# upstream name and its own src/hmac_drbg/ directory.
#
# Block-specific notes
# --------------------
# * Unlike ECC, HMAC spans TWO upstream directories: src/hmac/rtl and
#   src/hmac_drbg/rtl. hmac_drbg is deliberately owned by this import because
#   both HMAC and ECC instantiate it; importing it once avoids two divergent
#   copies in the Tessera netlist.
# * GENERATOR_INPUTS below are given by their *upstream* path. rename_common.sh
#   translates them through COLLATERAL_DEST_SUBTREES; roundtrip_check.sh does
#   the same through the dirmap it recorded. This is the first block to both
#   relocate its collateral and declare generator inputs, so it is the first
#   one where those two paths differ.
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

BLOCK="hmac512"

UPSTREAM_SUBTREES=(
    "src/hmac/rtl"
    "src/hmac/coverage"
    "src/hmac_drbg/rtl"
    "src/hmac_drbg/coverage"
)

# The rest of both block folders. src/hmac/config and src/hmac_drbg/config stay
# out: Tessera generates its own filelist there and the upstream .vf/compile.yml
# resolve $COMPILE_ROOT against the caliptra-rtl build environment.
COLLATERAL_SUBTREES=(
    "src/hmac/tb"
    "src/hmac/coverage/config"
    "src/hmac/stimulus"
    "src/hmac/uvmf_2022"
    "src/hmac_drbg/tb"
    "src/hmac_drbg/coverage/config"
    "src/hmac_drbg/stimulus"
)

# The SHA-512 engine moves to src/hmac512/; hmac_drbg stays where upstream put
# it, because ECC compiles it from there and it is not part of the rename.
DEST_SUBTREES=(
    "src/hmac512/rtl"
    "src/hmac512/coverage"
    "src/hmac_drbg/rtl"
    "src/hmac_drbg/coverage"
)

COLLATERAL_DEST_SUBTREES=(
    "src/hmac512/tb"
    "src/hmac512/coverage/config"
    "src/hmac512/stimulus"
    "src/hmac512/uvmf_2022"
    "src/hmac_drbg/tb"
    "src/hmac_drbg/coverage/config"
    "src/hmac_drbg/stimulus"
)

# DEST_SUBTREES[0] is src/hmac512/rtl, so BLOCK_DIR would be derived correctly
# anyway; stating it keeps the block folder independent of subtree ordering.
BLOCK_DIR="src/hmac512"

VF_FILELIST="src/hmac/config/hmac_ctrl.vf"
VF_FILTER="/hmac(_drbg)?/rtl/"

EXCLUDE_GLOBS=(
    "*_reg_uvm.sv"
    "*.rdl"
)

# Declared by rename_sha512_masked.sh, instantiated by hmac_core.
EXTRA_RENAME_IDENTS=(
    "module:sha512_masked_core"
)

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
