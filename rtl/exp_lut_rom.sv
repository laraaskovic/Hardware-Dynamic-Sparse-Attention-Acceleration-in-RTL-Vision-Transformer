// exp_lut_rom.sv
// Parameterizable synchronous ROM for softmax exponent lookup.
// Default depth = 4096 (covers [-8, 8] with step ~1/128 when ADDR_W=12).

module exp_lut_rom #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 16,
    parameter string MEMFILE = "rtl/lut/exp_lut.mem"
) (
    input  logic                 clk,
    input  logic [ADDR_W-1:0]    addr,
    output logic [DATA_W-1:0]    dout
);
    localparam int DEPTH = 1 << ADDR_W;
    logic [DATA_W-1:0] rom [0:DEPTH-1];

    initial begin
        $readmemh(MEMFILE, rom);
    end

    always_ff @(posedge clk) begin
        dout <= rom[addr];
    end
endmodule
