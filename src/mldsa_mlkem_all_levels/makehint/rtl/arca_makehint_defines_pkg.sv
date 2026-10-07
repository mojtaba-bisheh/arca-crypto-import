// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//======================================================================
//
// arca_makehint_defines_pkg.sv
// --------
// Makehint parameters for Mldsa
//======================================================================

`ifndef ARCA_MLDSA_MAKEHINT_DEFINES
`define ARCA_MLDSA_MAKEHINT_DEFINES

package arca_makehint_defines_pkg;

    typedef enum logic [2:0] {MH_IDLE, MH_RD_MEM, MH_WAIT, MH_FLUSH_SBUF, MH_RD_IBUF_LOW, MH_RD_IBUF_HIGH, MH_RD_IBUF_MID} mh_read_state_e;

endpackage

`endif