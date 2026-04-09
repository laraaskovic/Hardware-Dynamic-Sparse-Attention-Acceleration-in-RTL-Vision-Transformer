// Minimal AXI4-Lite slave exposing control/status and threshold registers.
// Address map (word offsets):
// 0x00: control (bit0 start, bit1 soft_reset)
// 0x04: status  (bit0 done, bit1 busy)
// 0x08: threshold [PROD_W-1:0] (write)

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
    input  logic         busy
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
                case (AWADDR[3:2])
                    2'b00: start_reg <= WDATA[0];
                    2'b10: threshold_reg <= WDATA; // low 32 bits; extend if needed below
                    default: ;
                endcase
                BVALID <= 1'b1;
            end
        end
    end

    // If PROD_W > 32, keep upper bits separately
    generate
        if (PROD_W > 32) begin : UP32
            always_ff @(posedge ACLK or negedge ARESETn) begin
                if (!ARESETn) threshold_reg[PROD_W-1:32] <= '0;
                else if (AWVALID && WVALID && AWADDR[3:2]==2'b11)
                    threshold_reg[PROD_W-1:32] <= WDATA[PROD_W-1:32];
            end
        end
    endgenerate

    assign threshold = threshold_reg;
    assign start_pulse = start_reg; // one-cycle pulse assumed; upstream clears busy/done

    // Read logic
    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            RVALID <= 1'b0;
            RDATA  <= '0;
        end else begin
            RVALID <= 1'b0;
            if (ARVALID) begin
                case (ARADDR[3:2])
                    2'b00: RDATA <= {30'b0, busy, done};
                    2'b10: RDATA <= threshold_reg[31:0];
                    2'b11: RDATA <= (PROD_W > 32) ? threshold_reg[63:32] : 32'b0;
                    default: RDATA <= 32'b0;
                endcase
                RVALID <= 1'b1;
            end
        end
    end

endmodule
