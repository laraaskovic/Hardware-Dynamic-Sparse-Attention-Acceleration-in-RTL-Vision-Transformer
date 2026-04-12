// tile_align_assert.sv
// Checks that data valid alignment matches prescreener valid_out.
module tile_align_assert (
    input logic clk,
    input logic rst_n,
    input logic valid_out,
    input logic data_valid_aligned
);
    property valid_alignment;
        @(posedge clk) disable iff (!rst_n)
            valid_out == data_valid_aligned;
    endproperty

    assert property(valid_alignment)
        else $error("tile_align_assert: valid_out not aligned with data_valid_aligned");
endmodule
