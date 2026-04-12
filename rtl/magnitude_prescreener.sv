// magnitude_prescreener.sv
// Pipelined L1 upper-bound estimator for Q·K attention scores.
// Produces a 1-bit valid_mask indicating whether the block should be computed.

module magnitude_prescreener #(
    parameter int WIDTH    = 16,  // bits per element (signed fixed-point)
    parameter int VEC_LEN  = 64,  // elements per vector
    // Sum of VEC_LEN magnitudes: needs WIDTH + log2(VEC_LEN) bits (plus margin)
    parameter int SUM_W    = WIDTH + $clog2(VEC_LEN) + 1,
    parameter int PROD_W   = 2 * SUM_W
) (
    input  logic                       clk,
    input  logic                       rst_n,
    input  logic                       valid_in,
    input  logic [VEC_LEN*WIDTH-1:0]   q_vec_flat,
    input  logic [VEC_LEN*WIDTH-1:0]   k_vec_flat,
    input  logic [PROD_W-1:0]          threshold,   // fixed-point scaled
    output logic                       valid_out,   // aligned with mask
    output logic                       valid_mask,  // 1 => compute block
    output logic [PROD_W-1:0]          product_mon, // exposed for assertions/coverage
    output logic [PROD_W-1:0]          threshold_mon
);

    // Unpack flattened buses into arrays
    logic signed [WIDTH-1:0] q_vec   [VEC_LEN];
    logic signed [WIDTH-1:0] k_vec   [VEC_LEN];
    genvar i;
    generate
        for (i = 0; i < VEC_LEN; i++) begin : UNPACK
            assign q_vec[i] = q_vec_flat[i*WIDTH +: WIDTH];
            assign k_vec[i] = k_vec_flat[i*WIDTH +: WIDTH];
        end
    endgenerate

    // Magnitude helper
    function automatic logic [WIDTH-1:0] abs_val (input logic signed [WIDTH-1:0] din);
        abs_val = din[WIDTH-1] ? (~din + 1'b1) : din;
    endfunction

    // Stage 1: compute L1 sums
    logic [SUM_W-1:0] sum_q_s1, sum_k_s1;
    integer j;
    // Note: iverilog limitation on constant selects in always_comb; using always @* equivalent
    always @* begin
        sum_q_s1 = '0;
        sum_k_s1 = '0;
        for (j = 0; j < VEC_LEN; j++) begin
            sum_q_s1 = sum_q_s1 + abs_val(q_vec[j]);
            sum_k_s1 = sum_k_s1 + abs_val(k_vec[j]);
        end
    end

    // Pipeline registers
    logic                  v_s1, v_s2;
    logic [SUM_W-1:0]      sum_q_r1, sum_k_r1;
    logic [PROD_W-1:0]     threshold_r1, threshold_r2;
    logic [PROD_W-1:0]     product_r2;

    // Stage 1 registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_q_r1    <= '0;
            sum_k_r1    <= '0;
            threshold_r1<= '0;
            v_s1        <= 1'b0;
        end else begin
            sum_q_r1    <= sum_q_s1;
            sum_k_r1    <= sum_k_s1;
            threshold_r1<= threshold;
            v_s1        <= valid_in;
        end
    end

    // Stage 2: multiply and compare
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_r2   <= '0;
            threshold_r2 <= '0;
            v_s2         <= 1'b0;
        end else begin
            product_r2   <= sum_q_r1 * sum_k_r1;
            threshold_r2 <= threshold_r1;
            v_s2         <= v_s1;
        end
    end

    assign valid_mask    = (product_r2 >= threshold_r2);
    assign valid_out     = v_s2;
    assign product_mon   = product_r2;
    assign threshold_mon = threshold_r2;

endmodule
