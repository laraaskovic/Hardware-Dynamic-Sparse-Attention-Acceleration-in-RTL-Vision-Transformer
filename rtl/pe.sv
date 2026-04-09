// pe.sv
// Single systolic processing element with valid gating.
// When valid_in=0, the accumulator holds its value and no MAC occurs.

module pe #(
    parameter int DATA_W = 16,
    parameter int ACC_W  = 40
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  valid_in,
    input  logic                  load_acc,   // when 1, load acc_in directly
    input  logic signed [DATA_W-1:0] a_in,
    input  logic signed [DATA_W-1:0] b_in,
    input  logic signed [ACC_W-1:0]  acc_in,
    output logic signed [DATA_W-1:0] a_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic signed [ACC_W-1:0]  acc_out
);

    logic signed [ACC_W-1:0] mac;
    assign mac = acc_in + (a_in * b_in);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_out <= '0;
            a_out   <= '0;
            b_out   <= '0;
        end else begin
            a_out <= a_in;
            b_out <= b_in;
            if (load_acc) begin
                acc_out <= acc_in;
            end else if (valid_in) begin
                acc_out <= mac;
            end else begin
                acc_out <= acc_out; // hold
            end
        end
    end

endmodule
