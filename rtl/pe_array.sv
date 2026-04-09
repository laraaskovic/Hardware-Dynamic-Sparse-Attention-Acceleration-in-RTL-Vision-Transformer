// pe_array.sv
// Simple square systolic array with broadcast valid mask.

module pe_array #(
    parameter int DATA_W = 16,
    parameter int ACC_W  = 40,
    parameter int DIM    = 4
) (
    input  logic clk,
    input  logic rst_n,
    input  logic valid_mask, // when 0, whole block is skipped
    input  logic signed [DIM*DATA_W-1:0] a_vec, // rows (Q)
    input  logic signed [DIM*DATA_W-1:0] b_vec, // cols (K)
    input  logic signed [DIM*DIM*ACC_W-1:0] acc_init,
    output logic signed [DIM*DIM*ACC_W-1:0] acc_out
);

    // Unpack inputs
    logic signed [DATA_W-1:0] a[DIM];
    logic signed [DATA_W-1:0] b[DIM];
    logic signed [ACC_W-1:0] acc[DIM][DIM];

    genvar i, j;
    generate
        for (i = 0; i < DIM; i++) begin : UNPACK_A
            assign a[i] = a_vec[i*DATA_W +: DATA_W];
            assign b[i] = b_vec[i*DATA_W +: DATA_W];
        end
        for (i = 0; i < DIM; i++) begin : UNPACK_ACC_ROW
            for (j = 0; j < DIM; j++) begin : UNPACK_ACC_COL
                assign acc[i][j] = acc_init[(i*DIM + j)*ACC_W +: ACC_W];
            end
        end
    endgenerate

    // Wires for outputs
    logic signed [ACC_W-1:0] acc_next[DIM][DIM];

    generate
        for (i = 0; i < DIM; i++) begin : ROW
            for (j = 0; j < DIM; j++) begin : COL
                pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) u_pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .valid_in(valid_mask),
                    .a_in(a[i]),
                    .b_in(b[j]),
                    .acc_in(acc[i][j]),
                    .a_out(), // not used in this simple broadcast version
                    .b_out(),
                    .acc_out(acc_next[i][j])
                );
            end
        end
    endgenerate

    // Pack outputs
    generate
        for (i = 0; i < DIM; i++) begin : PACK_ACC_ROW
            for (j = 0; j < DIM; j++) begin : PACK_ACC_COL
                assign acc_out[(i*DIM + j)*ACC_W +: ACC_W] = acc_next[i][j];
            end
        end
    endgenerate

endmodule
