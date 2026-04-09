// reciprocal_unit.sv
// Single-cycle integer reciprocal for softmax normalization.
// Computes (1<<SCALE) / denom; intended for small widths.

module reciprocal_unit #(
    parameter int DEN_W  = 24,
    parameter int OUT_W  = 16,
    parameter int SCALE  = 16  // numerator = 1<<SCALE
) (
    input  logic [DEN_W-1:0] denom,
    output logic [OUT_W-1:0] recip
);
    // Protect against divide-by-zero
    wire [DEN_W-1:0] denom_safe = (denom == 0) ? {{(DEN_W-1){1'b0}},1'b1} : denom;
    // Combinational integer divide (synthesizable; may infer DSP)
    always_comb begin
        recip = (1'b1 << SCALE) / denom_safe;
    end
endmodule
