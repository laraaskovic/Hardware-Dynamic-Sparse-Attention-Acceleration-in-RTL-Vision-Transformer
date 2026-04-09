// pe_array.sv
// DIM x DIM systolic array with data shift and global valid gating.

module pe_array #(
    parameter int DATA_W = 16,
    parameter int ACC_W  = 52,
    parameter int DIM    = 4
) (
    input  logic clk,
    input  logic rst_n,
    input  logic valid_mask, // when 0, all PEs hold accumulators
    input  logic load_acc,   // when 1, load acc_init into accumulators
    input  logic signed [DIM*DATA_W-1:0] a_in_vec, // left edge inputs per row
    input  logic signed [DIM*DATA_W-1:0] b_in_vec, // top edge inputs per col
    input  logic signed [DIM*DIM*ACC_W-1:0] acc_init,
    output logic signed [DIM*DIM*ACC_W-1:0] acc_out
);

    // Edge inputs unpack
    logic signed [DATA_W-1:0] a_in [DIM];
    logic signed [DATA_W-1:0] b_in [DIM];
    genvar i, j;
    generate
        for (i = 0; i < DIM; i++) begin : UNPACK
            assign a_in[i] = a_in_vec[i*DATA_W +: DATA_W];
            assign b_in[i] = b_in_vec[i*DATA_W +: DATA_W];
        end
    endgenerate

    // Pipes for a (move right) and b (move down)
    logic signed [DATA_W-1:0] a_pipe[DIM][DIM+1];
    logic signed [DATA_W-1:0] b_pipe[DIM+1][DIM];

    // Initialize left/top edges each cycle
    generate
        for (i = 0; i < DIM; i++) begin : EDGE_IN
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_pipe[i][0] <= '0;
                    b_pipe[0][i] <= '0;
                end else begin
                    a_pipe[i][0] <= a_in[i];
                    b_pipe[0][i] <= b_in[i];
                end
            end
        end
    endgenerate

    // Accumulator init unpack
    logic signed [ACC_W-1:0] acc_init_mat[DIM][DIM];
    generate
        for (i = 0; i < DIM; i++) begin : ACC_UNPACK
            for (j = 0; j < DIM; j++) begin
                assign acc_init_mat[i][j] = acc_init[(i*DIM + j)*ACC_W +: ACC_W];
            end
        end
    endgenerate

    // PE grid
    logic signed [ACC_W-1:0] acc_mat[DIM][DIM];
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
                    .load_acc(load_acc),
                    .a_in(a_pipe[i][j]),
                    .b_in(b_pipe[i][j]),
                    .acc_in(acc_init_mat[i][j]),
                    .a_out(a_pipe[i][j+1]),
                    .b_out(b_pipe[i+1][j]),
                    .acc_out(acc_mat[i][j])
                );
            end
        end
    endgenerate

    // Pack acc outputs
    generate
        for (i = 0; i < DIM; i++) begin : PACK
            for (j = 0; j < DIM; j++) begin
                assign acc_out[(i*DIM + j)*ACC_W +: ACC_W] = acc_mat[i][j];
            end
        end
    endgenerate

endmodule
