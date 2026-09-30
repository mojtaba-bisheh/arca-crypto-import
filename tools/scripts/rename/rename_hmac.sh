#!/usr/bin/env bash
#
# rename_hmac.sh -- import + prefix the caliptra-rtl HMAC-SHA512 engine
#                   together with the HMAC_DRBG it owns.
#
#   ./tools/scripts/rename/rename_hmac.sh --upstream /path/to/caliptra-rtl
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

set -euo pipefail

BLOCK="hmac"

UPSTREAM_SUBTREES=(
    "src/hmac/rtl"
    "src/hmac_drbg/rtl"
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
