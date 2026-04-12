// top_dynasparse.sv
// Skeleton of top-level FSM + AXI-lite placeholder.

module top_dynasparse #(
    parameter int WIDTH   = 16,
    parameter int VEC_LEN = 64,
    parameter int SUM_W   = 26,
    parameter int PROD_W  = 52,
    parameter int DATA_W  = 16,
    parameter int ACC_W   = 52,
    parameter int DIM     = 4,
    parameter int ADDR_W  = 8,
    parameter int LUT_W   = 16
) (
    input  logic clk,
    input  logic rst_n,
    // AXI-lite
    input  logic         s_axi_aclk,
    input  logic         s_axi_aresetn,
    input  logic [3:0]   s_axi_awaddr,
    input  logic         s_axi_awvalid,
    output logic         s_axi_awready,
    input  logic [31:0]  s_axi_wdata,
    input  logic [3:0]   s_axi_wstrb,
    input  logic         s_axi_wvalid,
    output logic         s_axi_wready,
    output logic [1:0]   s_axi_bresp,
    output logic         s_axi_bvalid,
    input  logic         s_axi_bready,
    input  logic [3:0]   s_axi_araddr,
    input  logic         s_axi_arvalid,
    output logic         s_axi_arready,
    output logic [31:0]  s_axi_rdata,
    output logic [1:0]   s_axi_rresp,
    output logic         s_axi_rvalid,
    input  logic         s_axi_rready,
    output logic done
);

    typedef enum logic [2:0] {IDLE, LOAD_Q, LOAD_K, PRESCREEN, COMPUTE, SOFTM, WRITEBACK} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:       if (start_pulse) next_state = LOAD_Q;
            LOAD_Q:     next_state = LOAD_K;
            LOAD_K:     next_state = PRESCREEN;
            PRESCREEN:  next_state = COMPUTE;
            COMPUTE:    next_state = SOFTM;
            SOFTM:      next_state = WRITEBACK;
            WRITEBACK:  next_state = IDLE;
        endcase
    end

    assign done = (state == WRITEBACK);

`ifndef IVERILOG
    // synopsys translate_off
    property state_valid;
        @(posedge clk) disable iff (!rst_n)
            state inside {IDLE, LOAD_Q, LOAD_K, PRESCREEN, COMPUTE, SOFTM, WRITEBACK};
    endproperty
    assert property(state_valid) else $error("Illegal FSM state");

    property writeback_after_softm;
        @(posedge clk) disable iff (!rst_n)
            state == WRITEBACK |-> $past(state == SOFTM);
    endproperty
    assert property(writeback_after_softm) else $error("WRITEBACK without SOFTM");

    property soft_valid_before_writeback;
        @(posedge clk) disable iff (!rst_n)
            state == WRITEBACK |-> $past(soft_valid);
    endproperty
    assert property(soft_valid_before_writeback) else $error("WRITEBACK without soft_valid");
    // synopsys translate_on
`endif

    // AXI-lite instance
    logic start_pulse;
    logic [PROD_W-1:0] threshold;
    axi_lite_slave #(.PROD_W(PROD_W)) u_axil (
        .ACLK(s_axi_aclk),
        .ARESETn(s_axi_aresetn),
        .AWADDR(s_axi_awaddr),
        .AWVALID(s_axi_awvalid),
        .AWREADY(s_axi_awready),
        .WDATA(s_axi_wdata),
        .WSTRB(s_axi_wstrb),
        .WVALID(s_axi_wvalid),
        .WREADY(s_axi_wready),
        .BRESP(s_axi_bresp),
        .BVALID(s_axi_bvalid),
        .BREADY(s_axi_bready),
        .ARADDR(s_axi_araddr),
        .ARVALID(s_axi_arvalid),
        .ARREADY(s_axi_arready),
        .RDATA(s_axi_rdata),
        .RRESP(s_axi_rresp),
        .RVALID(s_axi_rvalid),
        .RREADY(s_axi_rready),
        .start_pulse(start_pulse),
        .threshold(threshold),
        .done(done),
        .busy(state != IDLE),
        .blocks_compute(blocks_compute),
        .blocks_skip(blocks_skip),
        .macs_compute(macs_compute),
        .macs_skip(macs_skip),
        .macs_runtime(macs_runtime),
        .cycles_active(cycles_active)
    );

    // Q/K SRAM buffers (dual-port behavioral)
    logic                     q_we, k_we;
    logic [ADDR_W-1:0]        q_waddr, k_waddr;
    logic [VEC_LEN*WIDTH-1:0] q_wdata, k_wdata;
    logic [VEC_LEN*WIDTH-1:0] q_buf, k_buf;

    simple_dualport_sram #(.ADDR_W(ADDR_W), .DATA_W(VEC_LEN*WIDTH)) q_sram (
        .clk(clk),
        .we(q_we),
        .waddr(q_waddr),
        .wdata(q_wdata),
        .raddr({ADDR_W{1'b0}}),
        .rdata(q_buf)
    );
    simple_dualport_sram #(.ADDR_W(ADDR_W), .DATA_W(VEC_LEN*WIDTH)) k_sram (
        .clk(clk),
        .we(k_we),
        .waddr(k_waddr),
        .wdata(k_wdata),
        .raddr({ADDR_W{1'b0}}),
        .rdata(k_buf)
    );

    // Tile and softmax instances
    logic tile_valid_out, tile_mask_out;
    logic [DIM*DIM*ACC_W-1:0] acc_mat;
    logic [DIM*DATA_W-1:0] a_stub, b_stub;
    assign a_stub = '0;
    assign b_stub = '0;
    logic [31:0] blocks_compute, blocks_skip, macs_compute, macs_skip;
    logic [31:0] macs_runtime, cycles_active;
    logic data_valid_aligned;
    tile_prescreen_array #(
        .WIDTH(WIDTH),
        .VEC_LEN(VEC_LEN),
        .SUM_W(SUM_W),
        .PROD_W(PROD_W),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .DIM(DIM)
    ) u_tile (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(start_pulse),
        .q_vec_flat(q_buf),
        .k_vec_flat(k_buf),
        .threshold(threshold),
        .a_in_vec(a_stub),
        .b_in_vec(b_stub),
        .acc_init({DIM*DIM*ACC_W{1'b0}}),
        .acc_out(acc_mat),
        .valid_out(tile_valid_out),
        .mask_out(tile_mask_out),
        .data_valid_aligned(data_valid_aligned),
        .blocks_compute(blocks_compute),
        .blocks_skip(blocks_skip),
        .macs_compute(macs_compute),
        .macs_skip(macs_skip),
        .macs_runtime(macs_runtime),
        .cycles_active(cycles_active)
    );

    // Softmax over first row outputs (extend to full matrix in next rev)
    logic [DIM*LUT_W-1:0] soft_in;
    for (genvar si=0; si<DIM; si++) begin
        assign soft_in[si*LUT_W +: LUT_W] = acc_mat[(si*DIM)*ACC_W +: LUT_W];
    end
    logic [DIM*LUT_W-1:0] soft_out;
    logic soft_valid;

    softmax_masked #(
        .DATA_W(LUT_W),
        .LUT_ADDR(12),
        .LUT_W(LUT_W),
        .VEC_LEN(DIM)
    ) u_soft (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(tile_valid_out),
        .in_vec(soft_in),
        .mask({DIM{tile_mask_out}}),
        .valid_out(soft_valid),
        .out_vec(soft_out)
    );

    // Hook counters into AXI-lite
    // (Reads are handled inside axi_lite_slave)

endmodule
