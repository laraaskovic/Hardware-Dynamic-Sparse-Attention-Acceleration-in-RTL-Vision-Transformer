# Quick VCD generation using iverilog/vvp (PowerShell). Requires iverilog on PATH.
# Produces top_dynasparse_bfm.vcd for viewing in GTKWave.

$sources = @(
    "rtl/axi_lite_slave.sv",
    "rtl/simple_dualport_sram.sv",
    "rtl/exp_lut_rom.sv",
    "rtl/reciprocal_unit.sv",
    "rtl/magnitude_prescreener.sv",
    "rtl/pe.sv",
    "rtl/pe_array.sv",
    "rtl/tile_prescreen_array.sv",
    "rtl/softmax_masked.sv",
    "rtl/top_dynasparse.sv",
    "tb/top_dynasparse_bfm_tb.sv"
)

$cmd = @("iverilog", "-g2012", "-s", "top_dynasparse_bfm_tb", "-o", "simv") + $sources
& $cmd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& vvp simv
Write-Host "VCD generated: top_dynasparse_bfm.vcd (open with GTKWave)"
