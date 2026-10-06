// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// // Macros and helper code for security countermeasures.

`ifndef ARCA_ABR_PRIM_ASSERT_SEC_CM_SVH
`define ARCA_ABR_PRIM_ASSERT_SEC_CM_SVH

// Explicitly include the file defining the macros referenced below
// (ARCA_ABR_ASSERT, ARCA_ABR_ASSUME_FPV, etc.). Guarded, so it is a no-op when this
// fragment is pulled in via arca_abr_prim_assert.sv.
`include "arca_abr_prim_assert.sv"

`define ARCA__ABR_SEC_CM_ALERT_MAX_CYC 30

// Helper macros
`define ARCA_ABR_ASSERT_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_, MAX_CYCLES_, ERR_NAME_) \
  `ARCA_ABR_ASSERT(FpvSecCm``NAME_``, \
          $rose(PRIM_HIER_.ERR_NAME_) && !(GATE_) \
          |-> ##[0:MAX_CYCLES_] (ALERT_.alert_p)) \
  `ifdef ARCA_ABR_INC_ASSERT \
  assign PRIM_HIER_.unused_assert_connected = 1'b1; \
  `endif \
  `ARCA_ABR_ASSUME_FPV(``NAME_``TriggerAfterAlertInit_S, $stable(rst_b) == 0 |-> \
                       PRIM_HIER_.ERR_NAME_ == 0 [*10])

`define ARCA_ABR_ASSERT_ERROR_TRIGGER_ERR(NAME_, PRIM_HIER_, ERR_, GATE_, MAX_CYCLES_, ERR_NAME_, CLK_, RST_) \
  `ARCA_ABR_ASSERT(FpvSecCm``NAME_``, \
          $rose(PRIM_HIER_.ERR_NAME_) && !(GATE_) \
          |-> ##[0:MAX_CYCLES_] (ERR_), CLK_, RST_) \
  `ifdef ARCA_ABR_INC_ASSERT \
  assign PRIM_HIER_.unused_assert_connected = 1'b1; \
  `endif

// macros for security countermeasures that will trigger alert
`define ARCA_ABR_ASSERT_PRIM_COUNT_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_ = 0, MAX_CYCLES_ = `ARCA__ABR_SEC_CM_ALERT_MAX_CYC) \
  `ARCA_ABR_ASSERT_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_, MAX_CYCLES_, err_o)

`define ARCA_ABR_ASSERT_PRIM_DOUBLE_LFSR_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_ = 0, MAX_CYCLES_ = `ARCA__ABR_SEC_CM_ALERT_MAX_CYC) \
  `ARCA_ABR_ASSERT_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_, MAX_CYCLES_, err_o)

`define ARCA_ABR_ASSERT_PRIM_FSM_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_ = 0, MAX_CYCLES_ = `ARCA__ABR_SEC_CM_ALERT_MAX_CYC) \
  `ARCA_ABR_ASSERT_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_, MAX_CYCLES_, unused_err_o)

`define ARCA_ABR_ASSERT_PRIM_ONEHOT_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_ = 0, MAX_CYCLES_ = `ARCA__ABR_SEC_CM_ALERT_MAX_CYC) \
  `ARCA_ABR_ASSERT_ERROR_TRIGGER_ALERT(NAME_, PRIM_HIER_, ALERT_, GATE_, MAX_CYCLES_, err_o)

`define ARCA_ABR_ASSERT_PRIM_REG_WE_ONEHOT_ERROR_TRIGGER_ALERT(NAME_, REG_TOP_HIER_, ALERT_, GATE_ = 0, MAX_CYCLES_ = `ARCA__ABR_SEC_CM_ALERT_MAX_CYC) \
  `ARCA_ABR_ASSERT_PRIM_ONEHOT_ERROR_TRIGGER_ALERT(NAME_, \
    REG_TOP_HIER_.u_abr_prim_reg_we_check.u_abr_prim_onehot_check, ALERT_, GATE_, MAX_CYCLES_)

`endif // PRIM_ASSERT_SEC_CM_SVH
