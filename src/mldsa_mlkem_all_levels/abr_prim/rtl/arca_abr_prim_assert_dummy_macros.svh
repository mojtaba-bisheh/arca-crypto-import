// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Macro bodies included by arca_abr_prim_assert.sv for tools that don't support assertions. See
// arca_abr_prim_assert.sv for documentation for each of the macros.

// Explicitly include the file defining the macros referenced below
// (ARCA_ABR_ASSERT_DEFAULT_CLK/RST, etc.). Guarded, so it is a no-op when this
// fragment is pulled in via arca_abr_prim_assert.sv.
`include "arca_abr_prim_assert.sv"

`define ARCA_ABR_ASSERT_I(__name, __prop)
`define ARCA_ABR_ASSERT_INIT(__name, __prop)
`define ARCA_ABR_ASSERT_INIT_NET(__name, __prop)
`define ARCA_ABR_ASSERT_FINAL(__name, __prop)
`ifndef ARCA_ABR_SVA
`define ARCA_ABR_ASSERT(__name, __prop, __clk = `ARCA_ABR_ASSERT_DEFAULT_CLK, __rst = `ARCA_ABR_ASSERT_DEFAULT_RST)
`define ARCA_ABR_ASSERT_NEVER(__name, __prop, __clk = `ARCA_ABR_ASSERT_DEFAULT_CLK, __rst = `ARCA_ABR_ASSERT_DEFAULT_RST)
`define ARCA_ABR_ASSERT_KNOWN(__name, __sig, __clk = `ARCA_ABR_ASSERT_DEFAULT_CLK, __rst = `ARCA_ABR_ASSERT_DEFAULT_RST)
`endif
`define ARCA_ABR_COVER(__name, __prop, __clk = `ARCA_ABR_ASSERT_DEFAULT_CLK, __rst = `ARCA_ABR_ASSERT_DEFAULT_RST)
`define ARCA_ABR_ASSUME(__name, __prop, __clk = `ARCA_ABR_ASSERT_DEFAULT_CLK, __rst = `ARCA_ABR_ASSERT_DEFAULT_RST)
`define ARCA_ABR_ASSUME_I(__name, __prop)
