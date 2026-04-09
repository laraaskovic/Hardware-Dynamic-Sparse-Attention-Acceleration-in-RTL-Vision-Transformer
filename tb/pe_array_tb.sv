`timescale 1ns/1ps

module pe_array_tb;
    localparam int DATA_W = 16;
    localparam int ACC_W  = 52;
    localparam int DIM    = 2;

    logic clk, rst_n;
    logic valid_mask, load_acc;
    logic signed [DIM*DATA_W-1:0] a_in_vec, b_in_vec;
    logic signed [DIM*DIM*ACC_W-1:0] acc_init, acc_out;

    pe_array #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .DIM(DIM)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_mask(valid_mask),
        .load_acc(load_acc),
        .a_in_vec(a_in_vec),
        .b_in_vec(b_in_vec),
        .acc_init(acc_init),
        .acc_out(acc_out)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // Simple helper to randomize inputs
    function automatic void rand_inputs();
        for (int i = 0; i < DIM; i++) begin
            a_in_vec[i*DATA_W +: DATA_W] = $urandom_range(-4, 4);
            b_in_vec[i*DATA_W +: DATA_W] = $urandom_range(-4, 4);
        end
    endfunction

    // Property: when valid_mask=0, acc_out holds
    logic signed [DIM*DIM*ACC_W-1:0] acc_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) acc_prev <= '0;
        else acc_prev <= acc_out;
    end
    property hold_when_invalid;
        @(posedge clk) disable iff (!rst_n)
            (valid_mask == 0) |-> (acc_out == acc_prev);
    endproperty
    assert property(hold_when_invalid)
        else $fatal("acc_out changed while valid_mask=0");

    initial begin
        rst_n = 0; valid_mask = 0; load_acc = 0; a_in_vec = '0; b_in_vec = '0; acc_init = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;

        // Load accumulators to zero
        load_acc = 1;
        rand_inputs();
        @(posedge clk);
        load_acc = 0;

        // Phase 1: valid=1 expect change
        valid_mask = 1;
        rand_inputs();
        @(posedge clk);
        logic signed [DIM*DIM*ACC_W-1:0] acc_after_valid = acc_out;

        // Phase 2: hold with valid=0 for a few cycles
        valid_mask = 0;
        repeat (3) begin
            rand_inputs();
            @(posedge clk);
            if (acc_out !== acc_after_valid)
                $fatal("Accumulator changed during valid_mask=0 hold");
        end

        // Phase 3: re-enable and expect change
        valid_mask = 1;
        rand_inputs();
        @(posedge clk);
        if (acc_out == acc_after_valid)
            $fatal("Accumulator did not update when valid=1");

        $display("pe_array_tb: PASS");
        $finish;
    end

endmodule
