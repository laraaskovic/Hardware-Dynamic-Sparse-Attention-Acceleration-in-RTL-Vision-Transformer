// softmax_masked.sv
// Fixed-point masked softmax using log-sum-exp and LUT-based exp.
// This is a synthesizable skeleton; expects exp LUT BRAM initialized externally.

module softmax_masked #(
    parameter int DATA_W   = 16, // input width (Q3.13 recommended)
    parameter int LUT_ADDR = 12, // covers signed range [-2048,2047] -> step depends on scaling
    parameter int LUT_W    = 16, // output exp width (Q0.16 recommended)
    parameter int VEC_LEN  = 8,
    parameter int DEN_W    = 24  // denominator accumulator width
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      valid_in,
    input  logic [VEC_LEN*DATA_W-1:0] in_vec,     // concatenated inputs
    input  logic [VEC_LEN-1:0]        mask,       // 1 = keep, 0 = treat as -inf
    output logic                      valid_out,
    output logic [VEC_LEN*LUT_W-1:0]  out_vec     // softmax outputs
);

    // Unpack
    logic signed [DATA_W-1:0] x [VEC_LEN];
    genvar i;
    generate
        for (i = 0; i < VEC_LEN; i++) begin : UNPACK
            assign x[i] = in_vec[i*DATA_W +: DATA_W];
        end
    endgenerate

    // Stage 1: apply mask (-inf => minimum value)
    logic signed [DATA_W-1:0] x_masked [VEC_LEN];
    localparam signed [DATA_W-1:0] NEG_INF = {1'b1, {(DATA_W-1){1'b1}}}; // most negative
    always_comb begin
        for (int k = 0; k < VEC_LEN; k++) begin
            x_masked[k] = mask[k] ? x[k] : NEG_INF;
        end
    end

    // Stage 2: find max
    logic signed [DATA_W-1:0] xmax;
    always_comb begin
        xmax = x_masked[0];
        for (int k = 1; k < VEC_LEN; k++) begin
            if (x_masked[k] > xmax) xmax = x_masked[k];
        end
    end

    // Stage 3: subtract max and index LUT (shift right by FRAC bits to map to LUT step)
    localparam int FRAC = 13;
    logic signed [DATA_W-1:0] x_shifted [VEC_LEN];
    logic [LUT_ADDR-1:0]      lut_addr [VEC_LEN];
    logic [LUT_W-1:0]         exp_val  [VEC_LEN];
    generate
        for (i = 0; i < VEC_LEN; i++) begin : SHIFT
            assign x_shifted[i] = x_masked[i] - xmax;
            // map fixed-point to LUT index: use upper bits after FRAC shift
            wire signed [DATA_W-1:0] xs = x_shifted[i];
            wire signed [DATA_W-1:0] xs_shift = xs >>> FRAC; // approximate step 1
            wire signed [LUT_ADDR:0] clip = (xs_shift >  (1<<(LUT_ADDR-1))-1) ? (1<<(LUT_ADDR-1))-1 :
                                            (xs_shift < -(1<<(LUT_ADDR-1)))   ? -(1<<(LUT_ADDR-1))   : xs_shift[LUT_ADDR-1:0];
            assign lut_addr[i] = clip[LUT_ADDR-1:0];
        end
    endgenerate

    // Exponential LUT (synchronous read)
    generate
        for (i = 0; i < VEC_LEN; i++) begin : EXPROM
            exp_lut_rom #(
                .ADDR_W(LUT_ADDR),
                .DATA_W(LUT_W),
                .MEMFILE("rtl/lut/exp_lut.mem")
            ) exp_lut_i (
                .clk (clk),
                .addr(lut_addr[i]),
                .dout(exp_val[i])
            );
        end
    endgenerate

    // Stage 4: sum exp (note: DEN_W sized to avoid overflow for VEC_LEN terms)
    logic [DEN_W-1:0] exp_sum;
    always_comb begin
        exp_sum = '0;
        for (int k = 0; k < VEC_LEN; k++) exp_sum += exp_val[k];
    end

    // Stage 5: normalize using reciprocal_unit (integer)
    logic [LUT_W-1:0] recip;
    reciprocal_unit #(
        .DEN_W(DEN_W),
        .OUT_W(LUT_W),
        .SCALE(LUT_W)
    ) recip_i (
        .denom(exp_sum),
        .recip(recip)
    );

    generate
        for (i = 0; i < VEC_LEN; i++) begin : NORM
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) out_vec[i*LUT_W +: LUT_W] <= '0;
                else out_vec[i*LUT_W +: LUT_W] <= (exp_sum == 0) ? '0 : ((exp_val[i] * recip) >> LUT_W);
            end
        end
    endgenerate

    // valid pipeline (2 cycles here: LUT + recip/mul)
    logic [1:0] vpipe;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) vpipe <= '0;
        else vpipe <= {vpipe[0], valid_in};
    end
    assign valid_out = vpipe[1];

endmodule
