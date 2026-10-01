
// UVM
+incdir+${UVM_HOME}/src
${UVM_HOME}/src/uvm_pkg.sv

// Common UVMF files
-f ${UVMF_HOME}/common/common_sve.f

// BFM Files
-F ${UVMF_VIP_LIBRARY_HOME}/interface_packages/arca_ECC_in_pkg/ECC_in_pkg_sve.F
-F ${UVMF_VIP_LIBRARY_HOME}/interface_packages/arca_ECC_out_pkg/ECC_out_pkg_sve.F

// Environment Files
-F ${UVMF_VIP_LIBRARY_HOME}/environment_packages/arca_ECC_env_pkg/ECC_env_pkg_sve.F

// Bench Files
+incdir+./tb/tests
./tb/tests/arca_ECC_tests_pkg.sv

+incdir+./tb/sequences
./tb/sequences/arca_ECC_sequences_pkg.sv

+incdir+./tb/parameters
./tb/parameters/arca_ECC_parameters_pkg.sv

./tb/testbench/arca_hdl_top.sv
./tb/testbench/arca_hvl_top.sv

