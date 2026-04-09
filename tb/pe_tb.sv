`timescale 1ns/1ps

module pe_tb;
    localparam int DATA_W = 16;
    localparam int ACC_W  = 40;

    logic clk, rst_n, valid_in;
    logic load_acc;
    logic signed [DATA_W-1:0] a_in, b_in;
    logic signed [ACC_W-1:0]  acc_in, acc_out;

    pe #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .load_acc(load_acc),
        .a_in(a_in),
        .b_in(b_in),
        .acc_in(acc_in),
        .a_out(), .b_out(),
        .acc_out(acc_out)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    initial begin
        rst_n = 0; valid_in = 0; load_acc = 0; a_in = 0; b_in = 0; acc_in = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Case 1: valid=1, perform MAC
        acc_in = 10;
        load_acc = 1;
        @(posedge clk);
        load_acc = 0;
        a_in = 3;
        b_in = -4;
        valid_in = 1;
        @(posedge clk);
        if (acc_out !== (10 + (3 * -4))) $fatal("MAC wrong when valid=1");

        // Case 2: valid=0, hold acc
        acc_in = acc_out;
        a_in = 7;
        b_in = 9;
        valid_in = 0;
        @(posedge clk);
        if (acc_out !== acc_in) $fatal("Accumulator changed when valid=0");

        $display("pe_tb: PASS");
        $finish;
    end
endmodule
