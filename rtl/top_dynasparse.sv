// top_dynasparse.sv
// Skeleton of top-level FSM + AXI-lite placeholder.

module top_dynasparse #(
    parameter int WIDTH   = 16,
    parameter int VEC_LEN = 64,
    parameter int SUM_W   = 26,
    parameter int PROD_W  = 52,
    parameter int DATA_W  = 16,
    parameter int ACC_W   = 52,
    parameter int DIM     = 4
) (
    input  logic clk,
    input  logic rst_n,
    // AXI-lite signals would go here (placeholder)
    input  logic start,
    output logic done
);

    typedef enum logic [2:0] {IDLE, LOAD_Q, LOAD_K, PRESCREEN, COMPUTE, WRITEBACK} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE:       if (start) next_state = LOAD_Q;
            LOAD_Q:     next_state = LOAD_K;
            LOAD_K:     next_state = PRESCREEN;
            PRESCREEN:  next_state = COMPUTE;
            COMPUTE:    next_state = WRITEBACK;
            WRITEBACK:  next_state = IDLE;
        endcase
    end

    assign done = (state == WRITEBACK);

    // TODO: instantiate buffers, tile_prescreen_array, softmax_masked, AXI-lite bridge.

endmodule
