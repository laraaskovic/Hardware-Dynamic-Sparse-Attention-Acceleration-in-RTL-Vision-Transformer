// tile_prescreen_array.sv
// Integrates magnitude_prescreener with pe_array.
// Assumes prescreener latency of 2 cycles; inserts shift registers on data to align with mask.

module tile_prescreen_array #(
    parameter int WIDTH    = 16,
    parameter int VEC_LEN  = 64,
    parameter int SUM_W    = 26,
    parameter int PROD_W   = 52,
    parameter int DATA_W   = 16,
    parameter int ACC_W    = 52,
    parameter int DIM      = 4
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         valid_in,
    input  logic [VEC_LEN*WIDTH-1:0]     q_vec_flat,
    input  logic [VEC_LEN*WIDTH-1:0]     k_vec_flat,
    input  logic [PROD_W-1:0]            threshold,
    input  logic [DIM*DATA_W-1:0]        a_in_vec,
    input  logic [DIM*DATA_W-1:0]        b_in_vec,
    input  logic [DIM*DIM*ACC_W-1:0]     acc_init,
    output logic [DIM*DIM*ACC_W-1:0]     acc_out,
    output logic                         valid_out,
    output logic                         mask_out,
    output logic                         data_valid_aligned,
    // Performance counters (blocks)
    output logic [31:0]                  blocks_compute,
    output logic [31:0]                  blocks_skip,
    output logic [31:0]                  macs_compute,
    output logic [31:0]                  macs_skip,
    // Per-cycle MAC accounting
    output logic [31:0]                  macs_runtime,
    output logic [31:0]                  cycles_active
);

    // Prescreener
    logic ps_valid, ps_mask;
    logic [PROD_W-1:0] product_mon, threshold_mon;
    magnitude_prescreener #(
        .WIDTH(WIDTH),
        .VEC_LEN(VEC_LEN),
        .SUM_W(SUM_W),
        .PROD_W(PROD_W)
    ) u_ps (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .q_vec_flat(q_vec_flat),
        .k_vec_flat(k_vec_flat),
        .threshold(threshold),
        .valid_out(ps_valid),
        .valid_mask(ps_mask),
        .product_mon(product_mon),
        .threshold_mon(threshold_mon)
    );

    // Data delay to match prescreener latency (2 cycles)
    localparam int LAT = 2;
    logic [LAT:0] valid_pipe;
    logic [DIM*DATA_W-1:0] a_pipe[LAT:0];
    logic [DIM*DATA_W-1:0] b_pipe[LAT:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= '0;
            for (int i = 0; i <= LAT; i++) begin
                a_pipe[i] <= '0;
                b_pipe[i] <= '0;
            end
        end else begin
            valid_pipe[0] <= valid_in;
            a_pipe[0] <= a_in_vec;
            b_pipe[0] <= b_in_vec;
            for (int i = 0; i < LAT; i++) begin
                valid_pipe[i+1] <= valid_pipe[i];
                a_pipe[i+1] <= a_pipe[i];
                b_pipe[i+1] <= b_pipe[i];
            end
        end
    end

    // Use prescreener outputs at latency boundary
    assign valid_out = ps_valid;
    assign mask_out  = ps_mask;
    assign data_valid_aligned = valid_pipe[LAT];

    pe_array #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .DIM(DIM)
    ) u_array (
        .clk(clk),
        .rst_n(rst_n),
        .valid_mask(ps_mask),
        .load_acc(valid_pipe[LAT]), // load acc_init when input valid reaches array
        .a_in_vec(a_pipe[LAT]),
        .b_in_vec(b_pipe[LAT]),
        .acc_init(acc_init),
        .acc_out(acc_out)
    );

    // Block-level counters (increment on valid_out)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blocks_compute <= 32'd0;
            blocks_skip    <= 32'd0;
            macs_compute   <= 32'd0;
            macs_skip      <= 32'd0;
            macs_runtime   <= 32'd0;
            cycles_active  <= 32'd0;
        end else if (valid_out) begin
            if (mask_out) blocks_compute <= blocks_compute + 1;
            else          blocks_skip    <= blocks_skip + 1;
            if (mask_out) macs_compute <= macs_compute + DIM*DIM;
            else          macs_skip    <= macs_skip + DIM*DIM;
        end
        // per-cycle MAC runtime accounting
        if (data_valid_aligned) begin
            cycles_active <= cycles_active + 1;
            if (ps_mask) macs_runtime <= macs_runtime + DIM*DIM;
        end
    end

endmodule
