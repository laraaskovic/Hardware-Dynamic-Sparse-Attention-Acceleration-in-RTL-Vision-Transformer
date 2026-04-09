// Assertion module for magnitude_prescreener
// Checks: whenever the internal product exceeds threshold at output time, valid_mask must be 1.

module magnitude_prescreener_assert #(
    parameter int PROD_W  = 40,
    parameter int LATENCY = 2
) (
    input logic                 clk,
    input logic                 rst_n,
    input logic                 valid_out,
    input logic                 valid_mask,
    input logic [PROD_W-1:0]    product_mon,
    input logic [PROD_W-1:0]    threshold_mon
);
    property no_false_negative;
        @(posedge clk) disable iff (!rst_n)
            valid_out && (product_mon >= threshold_mon) |-> valid_mask;
    endproperty

    assert property(no_false_negative)
        else $error("False negative: product >= threshold but valid_mask deasserted.");

endmodule
