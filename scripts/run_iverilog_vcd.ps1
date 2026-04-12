# Quick VCD generation using iverilog/vvp (requires iverilog installed).
# This bypasses ModelSim/Questa and produces top_dynasparse_bfm.vcd for GTKWave.

iverilog -g2012 -o simv ^
  rtl/axi_lite_slave.sv rtl/simple_dualport_sram.sv rtl/exp_lut_rom.sv rtl/reciprocal_unit.sv ^
  rtl/magnitude_prescreener.sv rtl/pe.sv rtl/pe_array.sv rtl/tile_prescreen_array.sv rtl/softmax_masked.sv rtl/top_dynasparse.sv ^
  tb/top_dynasparse_bfm_tb.sv

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

vvp simv

Write-Host "VCD generated: top_dynasparse_bfm.vcd (open with GTKWave)"
