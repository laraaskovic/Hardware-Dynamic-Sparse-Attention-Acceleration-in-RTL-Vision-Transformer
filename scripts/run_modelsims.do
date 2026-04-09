vlib work
vlog rtl/magnitude_prescreener.sv rtl/pe.sv rtl/pe_array.sv rtl/tile_prescreen_array.sv rtl/softmax_masked.sv rtl/top_dynasparse.sv rtl/axi_lite_slave.sv
vlog tb/magnitude_prescreener_tb.sv tb/pe_tb.sv tb/pe_array_tb.sv tb/tile_prescreen_array_tb.sv tb/softmax_masked_tb.sv tb/top_dynasparse_tb.sv
vsim -c magnitude_prescreener_tb -do "run -all; quit"
vsim -c pe_tb -do "run -all; quit"
vsim -c pe_array_tb -do "run -all; quit"
vsim -c tile_prescreen_array_tb -do "run -all; quit"
vsim -c softmax_masked_tb -do "run -all; quit"
vsim -c top_dynasparse_tb -do "run -all; quit"
