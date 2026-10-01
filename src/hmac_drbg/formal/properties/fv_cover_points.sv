// -------------------------------------------------
// Contact: contact@lubis-eda.com
// Author: Tobias Ludwig, Michael Schwarz
// -------------------------------------------------
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
//
module arca_fv_coverpoints_m(
    input logic clk,
    input logic reset_n,
    input logic zeroize
);
    
    default clocking default_clk @(posedge clk); endclocking

     //Cover zeroize
     cover_zeroize: cover property(disable iff(!reset_n) arca_hmac_drbg.zeroize );
     //Assert zeroize input and check the status of all registers. All registers/internal memories should be cleared.
     cover_zeroize_after_next: cover property(disable iff(!reset_n  ) arca_hmac_drbg.zeroize && arca_hmac_drbg.ready && arca_hmac_drbg.next_cmd );
    
     cover_multiple_next: cover property(disable iff(!reset_n || zeroize) 
        arca_hmac_drbg.next_cmd && arca_hmac_drbg.ready ##1 arca_hmac_drbg.next_cmd && arca_hmac_drbg.ready[->1] 
    );
     
    // Assert init_cmd or next_cmd when HMAC_ready is still low. The engine ignores the new command and continues 
    // to complete the previous command.
     cover_init_and_next_ready_low: cover property(disable iff(!reset_n || zeroize) 
        (arca_hmac_drbg.init_cmd || 
        arca_hmac_drbg.next_cmd) &&
        !arca_hmac_drbg.ready
    );

    //Cover transition from T to "done" and "k3" state
    cover_transition_T_to_DONE: cover property (disable iff(!reset_n || zeroize)
        arca_hmac_drbg.T_ST 
        ##1
        !((arca_hmac_drbg.HMAC_tag == 384'd0) || (arca_hmac_drbg.HMAC_DRBG_PRIME <= arca_hmac_drbg.HMAC_tag))
        ##1    
        arca_hmac_drbg.DONE_ST
    );

    cover_transition_T_to_K3: cover property (disable iff(!reset_n || zeroize)
        arca_hmac_drbg.T_ST 
        ##1
        ((arca_hmac_drbg.HMAC_tag == 384'd0) || (arca_hmac_drbg.HMAC_DRBG_PRIME <= arca_hmac_drbg.HMAC_tag))
        ##1
        arca_hmac_drbg.K3_ST
    );
    
endmodule 
bind arca_hmac_drbg arca_fv_coverpoints_m fv_coverpoints(
  .clk(clk),
  .reset_n(reset_n),
  .zeroize(zeroize)
);