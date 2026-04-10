// pe_array gating assertion: when valid_mask=0, accumulators hold across cycles.
module pe_array_assert #(
    parameter int ACC_W = 52,
    parameter int DIM   = 4
) (
    input logic clk,
    input logic rst_n,
    input logic valid_mask,
    input logic [DIM*DIM*ACC_W-1:0] acc_flat
);
    logic [DIM*DIM*ACC_W-1:0] acc_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) acc_prev <= '0;
        else acc_prev <= acc_flat;
    end
    property hold_when_mask0;
        @(posedge clk) disable iff (!rst_n)
            (valid_mask==0) |-> (acc_flat == acc_prev);
    endproperty
    assert property(hold_when_mask0)
        else $error("pe_array_assert: accumulator changed while valid_mask=0");
endmodule
