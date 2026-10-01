//----------------------------------------------------------------------
// Created with uvmf_gen version 2022.3
//----------------------------------------------------------------------
// pragma uvmf custom header begin
// pragma uvmf custom header end
//----------------------------------------------------------------------
//----------------------------------------------------------------------
//     
// PACKAGE: This file defines all of the files contained in the
//    interface package that will run on the host simulator.
//
// CONTAINS:
//    - <HMAC_in_typedefs_hdl>
//    - <arca_HMAC_in_typedefs.svh>
//    - <arca_HMAC_in_transaction.svh>

//    - <arca_HMAC_in_configuration.svh>
//    - <arca_HMAC_in_driver.svh>
//    - <arca_HMAC_in_monitor.svh>

//    - <arca_HMAC_in_transaction_coverage.svh>
//    - <arca_HMAC_in_sequence_base.svh>
//    - <arca_HMAC_in_random_sequence.svh>

//    - <arca_HMAC_in_responder_sequence.svh>
//    - <arca_HMAC_in2reg_adapter.svh>
//
//----------------------------------------------------------------------
//----------------------------------------------------------------------
//
package arca_HMAC_in_pkg;
  
   import uvm_pkg::*;
   import uvmf_base_pkg_hdl::*;
   import uvmf_base_pkg::*;
   import arca_HMAC_in_pkg_hdl::*;

   `include "uvm_macros.svh"

   // pragma uvmf custom package_imports_additional begin 
   // pragma uvmf custom package_imports_additional end
   `include "src/arca_HMAC_in_macros.svh"

   export arca_HMAC_in_pkg_hdl::*;
   
 

   // Parameters defined as HVL parameters

   `include "src/arca_HMAC_in_typedefs.svh"
   `include "src/arca_HMAC_in_transaction.svh"

   `include "src/arca_HMAC_in_configuration.svh"
   `include "src/arca_HMAC_in_driver.svh"
   `include "src/arca_HMAC_in_monitor.svh"

   `include "src/arca_HMAC_in_transaction_coverage.svh"
   `include "src/arca_HMAC_in_sequence_base.svh"
   `include "src/arca_HMAC_in_random_sequence.svh"
   `include "src/arca_HMAC_in_reset_sequence.svh"
   `include "src/arca_HMAC_in_otf_reset_sequence.svh"
   `include "src/arca_HMAC_in_last_alone_error_sequence.svh"

   `include "src/arca_HMAC_in_responder_sequence.svh"
   `include "src/arca_HMAC_in2reg_adapter.svh"

   `include "src/arca_HMAC_in_agent.svh"

   // pragma uvmf custom package_item_additional begin
   // UVMF_CHANGE_ME : When adding new interface sequences to the src directory
   //    be sure to add the sequence file here so that it will be
   //    compiled as part of the interface package.  Be sure to place
   //    the new sequence after any base sequences of the new sequence.
   // pragma uvmf custom package_item_additional end

endpackage

// pragma uvmf custom external begin
// pragma uvmf custom external end

