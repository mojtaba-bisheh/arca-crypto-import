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

import arca_hmac_drbg_pkg::*;


module arca_fv_hmac_drbg_m(
  input bit rst,
  input bit clk,

  // Inputs
  input bit unsigned [383:0] hmac_tag,
  input st_drbg_block input_data,

  // Outputs
  input bit unsigned [383:0] drbg,
  input st_hmac_block hmac_msg,

  // Sync signals
  input bit hmac_tag_valid,
  input bit input_data_valid,

  // Notify signals
  input bit drbg_valid,
  input bit input_data_ready,

  // Registers
  input bit unsigned [7:0] cnt,
  input st_hmac_block arca_hmac,
  input st_drbg_block in_data,
  input bit unsigned [383:0] key_reg,
  input bit unsigned [383:0] tag_temp,
  input bit unsigned [383:0] v_reg,

  // States
  input bit idle,
  input bit K10,
  input bit K11,
  input bit V1,
  input bit K20,
  input bit K21,
  input bit V2,
  input bit T,
  input bit Done,
  input bit K3,
  input bit V3
);


default clocking default_clk @(posedge clk); endclocking


st_hmac_block hmac_0 = '{
  key: 384'd0,
  block_msg: 1024'd0,
  init: 0,
  next: 0
};

st_drbg_block in_data_0 = '{
  entropy: 384'd0,
  nonce: 384'd0,
  init: 0,
  next: 0
};

st_hmac_block hmac_1 = '{
  key: K_INIT,
  block_msg: k10_func(V_INIT, 8'd0, input_data.entropy, input_data.nonce),
  init: 1,
  next: 0
};

st_hmac_block hmac_2 = '{
  key: key_reg,
  block_msg: k10_func(v_reg, 8'((cnt + 8'd1)), input_data.entropy, input_data.nonce),
  init: 1,
  next: 0
};

st_hmac_block hmac_3 = '{
  key: key_reg,
  block_msg: k11_func(in_data.nonce),
  init: 0,
  next: 1
};

st_hmac_block hmac_4 = '{
  key: hmac_tag,
  block_msg: v1_func(v_reg),
  init: 1,
  next: 0
};

st_hmac_block hmac_5 = '{
  key: key_reg,
  block_msg: k10_func(hmac_tag, 8'((cnt + 8'd1)), in_data.entropy, in_data.nonce),
  init: 1,
  next: 0
};

st_hmac_block hmac_6 = '{
  key: key_reg,
  block_msg: v1_func(hmac_tag),
  init: 1,
  next: 0
};

st_hmac_block hmac_7 = '{
  key: key_reg,
  block_msg: 1024'd0,
  init: 0,
  next: 0
};

st_hmac_block hmac_8 = '{
  key: key_reg,
  block_msg: k3_func(v_reg),
  init: 1,
  next: 0
};

st_hmac_block hmac_9 = '{
  key: key_reg,
  block_msg: arca_hmac.block_msg,
  init: arca_hmac.init,
  next: arca_hmac.next
};


sequence reset_sequence;
  rst ##1 !rst;
endsequence


reset_a: assert property (reset_p);
property reset_p;
  reset_sequence |->
  idle &&
  cnt == 8'd0 &&
  hmac_msg == hmac_0 &&
  key_reg == 384'd0 &&
  v_reg == 384'd0 &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


Done_to_idle_a: assert property (disable iff(rst) Done_to_idle_p);
property Done_to_idle_p;
  Done
|->
  ##1
  idle &&
  cnt == $past(cnt, 1) &&
  drbg == $past(tag_temp, 1) &&
  hmac_msg == $past(hmac_msg, 1) &&
  key_reg == $past(key_reg, 1) &&
  v_reg == $past(tag_temp, 1) &&
  drbg_valid == 1 &&
  input_data_ready == 0;
endproperty


K10_to_K11_a: assert property (disable iff(rst) K10_to_K11_p);
property K10_to_K11_p;
  K10 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  K11 &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_3, 2) &&
  key_reg == $past(key_reg, 2) &&
  v_reg == $past(v_reg, 2);
endproperty


K11_to_V1_a: assert property (disable iff(rst) K11_to_V1_p);
property K11_to_V1_p;
  K11 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  V1 &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_4, 2) &&
  key_reg == $past(hmac_tag, 2) &&
  v_reg == $past(v_reg, 2);
endproperty


K20_to_K21_a: assert property (disable iff(rst) K20_to_K21_p);
property K20_to_K21_p;
  K20 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  K21 &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_3, 2) &&
  key_reg == $past(key_reg, 2) &&
  v_reg == $past(v_reg, 2);
endproperty


K21_to_V2_a: assert property (disable iff(rst) K21_to_V2_p);
property K21_to_V2_p;
  K21 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  V2 &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_4, 2) &&
  key_reg == $past(hmac_tag, 2) &&
  v_reg == $past(v_reg, 2);
endproperty


K3_to_V3_a: assert property (disable iff(rst) K3_to_V3_p);
property K3_to_V3_p;
  K3 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  V3 &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_4, 2) &&
  key_reg == $past(hmac_tag, 2) &&
  v_reg == $past(v_reg, 2);
endproperty


T_to_Done_a: assert property (disable iff(rst) T_to_Done_p);
property T_to_Done_p;
  T &&
  hmac_tag_valid &&
  (hmac_tag != 384'd0) &&
  (HMAC_DRBG_PRIME > hmac_tag)
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  Done &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_7, 2) &&
  key_reg == $past(key_reg, 2) &&
  v_reg == $past(v_reg, 2);
endproperty


T_to_K3_a: assert property (disable iff(rst) T_to_K3_p);
property T_to_K3_p;
  T &&
  hmac_tag_valid &&
  ((hmac_tag == 384'd0) || (HMAC_DRBG_PRIME <= hmac_tag))
|->
  ##1 (drbg_valid == 0)[*3] and
  ##1 (input_data_ready == 0)[*3] and
  ##3
  K3 &&
  cnt == $past(cnt, 3) &&
  hmac_msg == $past(hmac_8, 3) &&
  key_reg == $past(key_reg, 3) &&
  v_reg == $past(v_reg, 3);
endproperty


V1_to_K20_a: assert property (disable iff(rst) V1_to_K20_p);
property V1_to_K20_p;
  V1 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*3] and
  ##1 (input_data_ready == 0)[*3] and
  ##3
  K20 &&
  cnt == 8'((9'd1 + $past(cnt, 3))) &&
  hmac_msg == $past(hmac_5, 3) &&
  key_reg == $past(key_reg, 3) &&
  v_reg == $past(hmac_tag, 3);
endproperty


V2_to_T_a: assert property (disable iff(rst) V2_to_T_p);
property V2_to_T_p;
  V2 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  T &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_6, 2) &&
  key_reg == $past(key_reg, 2) &&
  v_reg == $past(hmac_tag, 2);
endproperty


V3_to_T_a: assert property (disable iff(rst) V3_to_T_p);
property V3_to_T_p;
  V3 &&
  hmac_tag_valid
|->
  ##1 (drbg_valid == 0)[*2] and
  ##1 (input_data_ready == 0)[*2] and
  ##2
  T &&
  cnt == $past(cnt, 2) &&
  hmac_msg == $past(hmac_6, 2) &&
  key_reg == $past(key_reg, 2) &&
  v_reg == $past(hmac_tag, 2);
endproperty


idle_to_K10_a: assert property (disable iff(rst) idle_to_K10_p);
property idle_to_K10_p;
  idle &&
  input_data_valid &&
  input_data.init
|->
  ##1 (drbg_valid == 0)[*3] and
  ##1 (input_data_ready == 1) and
  ##2 (input_data_ready == 0) and
  ##3
  K10 &&
  cnt == 8'd0 &&
  hmac_msg == $past(hmac_1, 3) &&
  key_reg == $past(K_INIT, 3) &&
  v_reg == $past(V_INIT, 3) &&
  input_data_ready == 0;
endproperty


idle_to_K10_1_a: assert property (disable iff(rst) idle_to_K10_1_p);
property idle_to_K10_1_p;
  idle &&
  input_data_valid &&
  !input_data.init
|->
  ##1 (drbg_valid == 0)[*3] and
  ##1 (input_data_ready == 1) and
  ##2 (input_data_ready == 0) and
  ##3
  K10 &&
  cnt == 8'((9'd1 + $past(cnt, 3))) &&
  hmac_msg == $past(hmac_2, 3) &&
  key_reg == $past(key_reg, 3) &&
  v_reg == $past(v_reg, 3) &&
  input_data_ready == 0;
endproperty


K10_wait_a: assert property (disable iff(rst) K10_wait_p);
property K10_wait_p;
  K10 &&
  !hmac_tag_valid
|->
  ##1
  K10 &&
  cnt == $past(cnt, 1) &&
  key_reg == $past(key_reg, 1) &&
  v_reg == $past(v_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


K11_wait_a: assert property (disable iff(rst) K11_wait_p);
property K11_wait_p;
  K11 &&
  !hmac_tag_valid
|->
  ##1
  K11 &&
  cnt == $past(cnt, 1) &&
  key_reg == $past(key_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


K20_wait_a: assert property (disable iff(rst) K20_wait_p);
property K20_wait_p;
  K20 &&
  !hmac_tag_valid
|->
  ##1
  K20 &&
  cnt == $past(cnt, 1) &&
  key_reg == $past(key_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


K21_wait_a: assert property (disable iff(rst) K21_wait_p);
property K21_wait_p;
  K21 &&
  !hmac_tag_valid
|->
  ##1
  K21 &&
  cnt == $past(cnt, 1) &&
  key_reg == $past(key_reg, 1) &&
  v_reg == $past(v_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


K3_wait_a: assert property (disable iff(rst) K3_wait_p);
property K3_wait_p;
  K3 &&
  !hmac_tag_valid
|->
  ##1
  K3 &&
  cnt == $past(cnt, 1) &&
  key_reg == $past(key_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


T_wait_a: assert property (disable iff(rst) T_wait_p);
property T_wait_p;
  T &&
  !hmac_tag_valid
|->
  ##1
  T &&
  cnt == $past(cnt, 1) &&
  key_reg == $past(key_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


V1_wait_a: assert property (disable iff(rst) V1_wait_p);
property V1_wait_p;
  V1 &&
  !hmac_tag_valid
|->
  ##1
  V1 &&
  cnt == $past(cnt, 1) &&
  v_reg == $past(v_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


V2_wait_a: assert property (disable iff(rst) V2_wait_p);
property V2_wait_p;
  V2 &&
  !hmac_tag_valid
|->
  ##1
  V2 &&
  cnt == $past(cnt, 1) &&
  v_reg == $past(v_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


V3_wait_a: assert property (disable iff(rst) V3_wait_p);
property V3_wait_p;
  V3 &&
  !hmac_tag_valid
|->
  ##1
  V3 &&
  cnt == $past(cnt, 1) &&
  v_reg == $past(v_reg, 1) &&
  drbg_valid == 0 &&
  input_data_ready == 0;
endproperty


idle_wait_a: assert property (disable iff(rst) idle_wait_p);
property idle_wait_p;
  idle &&
  !input_data_valid
|->
  ##1
  idle &&
  cnt == $past(cnt, 1) &&
  key_reg == $past(key_reg, 1) &&
  v_reg == $past(v_reg, 1) &&
  drbg_valid == $past(drbg_valid) &&
  input_data_ready == 1;
endproperty


endmodule


module arca_fv_hmac_drbg_wrapper_m;


default clocking default_clk @(posedge (arca_hmac_drbg.clk)); endclocking


st_hmac_block hmac_msg = '{ key: (arca_hmac_drbg.HMAC_key), block_msg: (arca_hmac_drbg.HMAC_block), init: (arca_hmac_drbg.HMAC_init), next: (arca_hmac_drbg.HMAC_next) };
st_drbg_block input_data = '{ entropy: (arca_hmac_drbg.entropy), nonce: (arca_hmac_drbg.nonce), init: (arca_hmac_drbg.init_cmd), next: (arca_hmac_drbg.next_cmd) };
st_hmac_block arca_hmac = '{ key: (arca_hmac_drbg.HMAC_key), block_msg: (arca_hmac_drbg.HMAC_block), init: (arca_hmac_drbg.HMAC_init), next: (arca_hmac_drbg.HMAC_next) };
st_drbg_block in_data = '{ entropy: (arca_hmac_drbg.entropy), nonce: (arca_hmac_drbg.nonce), init: (arca_hmac_drbg.init_cmd), next: (arca_hmac_drbg.next_cmd) };


arca_fv_hmac_drbg_m fv_hmac_drbg(
  .rst((!arca_hmac_drbg.reset_n||arca_hmac_drbg.zeroize)),
  .clk(arca_hmac_drbg.clk),

  // Inputs
  .hmac_tag(arca_hmac_drbg.HMAC_tag),
  .input_data(input_data),

  // Outputs
  .drbg(arca_hmac_drbg.drbg),
  .hmac_msg(hmac_msg),

  // Sync signals
  .hmac_tag_valid(arca_hmac_drbg.HMAC_tag_valid  && !$past(arca_hmac_drbg.HMAC_tag_valid)),
  .input_data_valid((arca_hmac_drbg.init_cmd || arca_hmac_drbg.next_cmd) && arca_hmac_drbg.HMAC_ready),

  // Notify signals
  .drbg_valid(arca_hmac_drbg.valid),
  .input_data_ready(arca_hmac_drbg.ready),

  // Registers
  .cnt(arca_hmac_drbg.cnt_reg),
  .arca_hmac(arca_hmac),
  .in_data(in_data),
  .key_reg(arca_hmac_drbg.K_reg),
  .tag_temp(arca_hmac_drbg.HMAC_tag),
  .v_reg(arca_hmac_drbg.V_reg),

  // States
  .idle(arca_hmac_drbg.drbg_st_reg == 5'd00),
  .K10(arca_hmac_drbg.drbg_st_reg == 5'd03),
  .K11(arca_hmac_drbg.drbg_st_reg == 5'd04),
  .V1(arca_hmac_drbg.drbg_st_reg == 5'd05),
  .K20(arca_hmac_drbg.drbg_st_reg == 5'd07),
  .K21(arca_hmac_drbg.drbg_st_reg == 5'd08),
  .V2(arca_hmac_drbg.drbg_st_reg == 5'd09),
  .T(arca_hmac_drbg.drbg_st_reg == 5'd10),
  .Done(arca_hmac_drbg.drbg_st_reg == 5'd14),
  .K3(arca_hmac_drbg.drbg_st_reg == 5'd12),
  .V3(arca_hmac_drbg.drbg_st_reg == 5'd13)
);


endmodule


bind arca_hmac_drbg arca_fv_hmac_drbg_wrapper_m fv_hmac_drbg_wrapper();
