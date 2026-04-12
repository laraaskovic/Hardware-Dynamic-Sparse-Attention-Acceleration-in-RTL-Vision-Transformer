// Minimal AXI4-Lite slave exposing control/status, threshold, and counters.
// Address map (word offsets):
// 0x00: control (bit0 start, bit1 soft_reset)
// 0x04: status  (bit0 done, bit1 busy)
// 0x08: threshold low [31:0]
// 0x0C: threshold high [PROD_W-1:32] (when PROD_W>32)
// 0x10: blocks_compute (RO)
// 0x14: blocks_skip    (RO)
// 0x18: macs_compute   (RO)
// 0x1C: macs_skip      (RO)
// 0x20: macs_runtime   (RO)
// 0x24: cycles_active  (RO)

module axi_lite_slave #(
    parameter int PROD_W = 52
) (
    input  logic         ACLK,
    input  logic         ARESETn,
    // Write address channel
    input  logic [3:0]   AWADDR,
    input  logic         AWVALID,
    output logic         AWREADY,
    // Write data channel
    input  logic [31:0]  WDATA,
    input  logic [3:0]   WSTRB,
    input  logic         WVALID,
    output logic         WREADY,
    // Write response channel
    output logic [1:0]   BRESP,
    output logic         BVALID,
    input  logic         BREADY,
    // Read address channel
    input  logic [3:0]   ARADDR,
    input  logic         ARVALID,
    output logic         ARREADY,
    // Read data channel
    output logic [31:0]  RDATA,
    output logic [1:0]   RRESP,
    output logic         RVALID,
    input  logic         RREADY,
    // Exposed registers
    output logic         start_pulse,
    output logic [PROD_W-1:0] threshold,
    input  logic         done,
    input  logic         busy,
    input  logic [31:0]  blocks_compute,
    input  logic [31:0]  blocks_skip,
    input  logic [31:0]  macs_compute,
    input  logic [31:0]  macs_skip,
    input  logic [31:0]  macs_runtime,
    input  logic [31:0]  cycles_active
);

    // Internal regs
    logic start_reg;
    logic [PROD_W-1:0] threshold_reg;

    // Simple ready/valid handshakes (one-beat)
    assign AWREADY = 1'b1;
    assign WREADY  = 1'b1;
    assign BRESP   = 2'b00;
    assign ARREADY = 1'b1;
    assign RRESP   = 2'b00;

    // Write logic
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            start_reg     <= 1'b0;
            threshold_reg <= '0;
            BVALID        <= 1'b0;
        end else begin
            BVALID <= 1'b0;
            if (AWVALID && WVALID) begin
                case (AWADDR[5:2])
                    4'h0: start_reg <= WDATA[0];
                    4'h2: threshold_reg[31:0] <= WDATA; // low 32 bits
                    4'h3: if (PROD_W > 32) threshold_reg[PROD_W-1:32] <= WDATA[PROD_W-1:32];
                    default: ;
                endcase
                BVALID <= 1'b1;
            end
        end
    end

    // If PROD_W > 32, keep upper bits separately
    // Self-clear start_reg to form a pulse
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) start_reg <= 1'b0;
        else if (start_reg) start_reg <= 1'b0;
    end

    assign threshold = threshold_reg;
    assign start_pulse = start_reg; // one-cycle pulse

    // Read logic
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            RVALID <= 1'b0;
            RDATA  <= '0;
        end else begin
            RVALID <= 1'b0;
            if (ARVALID) begin
                case (ARADDR[5:2])
                    4'h0: RDATA <= {30'b0, busy, done};
                    4'h2: RDATA <= threshold_reg[31:0];
                    4'h3: RDATA <= (PROD_W > 32) ? threshold_reg[63:32] : 32'b0;
                    4'h4: RDATA <= blocks_compute;
                    4'h5: RDATA <= blocks_skip;
                    4'h6: RDATA <= macs_compute;
                    4'h7: RDATA <= macs_skip;
                    4'h8: RDATA <= macs_runtime;
                    4'h9: RDATA <= cycles_active;
                    default: RDATA <= 32'b0;
                endcase
                RVALID <= 1'b1;
            end
        end
    end

endmodule
