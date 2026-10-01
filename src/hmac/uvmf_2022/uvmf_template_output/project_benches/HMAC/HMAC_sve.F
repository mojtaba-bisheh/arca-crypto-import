
// UVM
+incdir+${UVM_HOME}/src
${UVM_HOME}/src/uvm_pkg.sv

// Common UVMF files
-f ${UVMF_HOME}/common/common_sve.f

// BFM Files
-F ${UVMF_VIP_LIBRARY_HOME}/interface_packages/arca_HMAC_in_pkg/HMAC_in_pkg_sve.F
-F ${UVMF_VIP_LIBRARY_HOME}/interface_packages/arca_HMAC_out_pkg/HMAC_out_pkg_sve.F

// Environment Files
-F ${UVMF_VIP_LIBRARY_HOME}/environment_packages/arca_HMAC_env_pkg/HMAC_env_pkg_sve.F

// Bench Files
+incdir+./tb/tests
./tb/tests/arca_HMAC_tests_pkg.sv

+incdir+./tb/sequences
./tb/sequences/arca_HMAC_sequences_pkg.sv

+incdir+./tb/parameters
./tb/parameters/arca_HMAC_parameters_pkg.sv

./tb/testbench/arca_hdl_top.sv
./tb/testbench/arca_hvl_top.sv

