TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES += ../../rtl/axi_lite_slave.sv \
                   ../../rtl/simple_dualport_sram.sv \
                   ../../rtl/exp_lut_rom.sv \
                   ../../rtl/reciprocal_unit.sv \
                   ../../rtl/magnitude_prescreener.sv \
                   ../../rtl/pe.sv \
                   ../../rtl/pe_array.sv \
                   ../../rtl/tile_prescreen_array.sv \
                   ../../rtl/softmax_masked.sv \
                   ../../rtl/top_dynasparse.sv

TOPLEVEL := top_dynasparse
MODULE   := test_top_dynasparse

EXTRA_ARGS += -sv

SIM ?= Questa

include $(shell cocotb-config --makefiles)/Makefile.sim
