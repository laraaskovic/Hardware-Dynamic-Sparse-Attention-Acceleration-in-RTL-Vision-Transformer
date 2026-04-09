// simple_dualport_sram.sv
// Behavioral dual-port SRAM (1 write, 1 read) for Q/K storage in testbenches.
// Not technology-mapped; replace with vendor RAM in synthesis.

module simple_dualport_sram #(
    parameter int ADDR_W = 8,
    parameter int DATA_W = 128
) (
    input  logic                 clk,
    // write port
    input  logic                 we,
    input  logic [ADDR_W-1:0]    waddr,
    input  logic [DATA_W-1:0]    wdata,
    // read port
    input  logic [ADDR_W-1:0]    raddr,
    output logic [DATA_W-1:0]    rdata
);
    localparam int DEPTH = 1 << ADDR_W;
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        rdata <= mem[raddr];
    end
endmodule
