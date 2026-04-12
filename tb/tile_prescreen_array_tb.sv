`timescale 1ns/1ps

module tile_prescreen_array_tb;
    localparam int WIDTH   = 16;
    localparam int VEC_LEN = 8;   // small for test speed
    localparam int SUM_W   = WIDTH + $clog2(VEC_LEN) + 4;
    localparam int PROD_W  = 2*SUM_W;
    localparam int DATA_W  = 16;
    localparam int ACC_W   = 52;
    localparam int DIM     = 2;
    localparam int LAT     = 2;

    logic clk, rst_n;
    logic valid_in;
    logic [VEC_LEN*WIDTH-1:0] q_vec, k_vec;
    logic [PROD_W-1:0] threshold;
    logic [DIM*DATA_W-1:0] a_in_vec, b_in_vec;
    logic [DIM*DIM*ACC_W-1:0] acc_init, acc_out;
    logic valid_out, mask_out;

    tile_prescreen_array #(
        .WIDTH(WIDTH),
        .VEC_LEN(VEC_LEN),
        .SUM_W(SUM_W),
        .PROD_W(PROD_W),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .DIM(DIM)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .q_vec_flat(q_vec),
        .k_vec_flat(k_vec),
        .threshold(threshold),
        .a_in_vec(a_in_vec),
        .b_in_vec(b_in_vec),
        .acc_init(acc_init),
        .acc_out(acc_out),
        .valid_out(valid_out),
        .mask_out(mask_out),
        .data_valid_aligned() // unused in this TB
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // Generate simple data: a_in_vec and b_in_vec hold small values
    task automatic random_vecs();
        for (int i = 0; i < DIM; i++) begin
            a_in_vec[i*DATA_W +: DATA_W] = $urandom_range(-3, 3);
            b_in_vec[i*DATA_W +: DATA_W] = $urandom_range(-3, 3);
        end
    endtask

    function automatic logic [PROD_W-1:0] compute_prod_bound(
        logic signed [WIDTH-1:0] qv[VEC_LEN],
        logic signed [WIDTH-1:0] kv[VEC_LEN]
    );
        longint unsigned sum_q = 0, sum_k = 0;
        for (int i = 0; i < VEC_LEN; i++) begin
            sum_q += qv[i][WIDTH-1] ? (~qv[i] + 1) : qv[i];
            sum_k += kv[i][WIDTH-1] ? (~kv[i] + 1) : kv[i];
        end
        compute_prod_bound = sum_q * sum_k;
    endfunction

    // Pipeline tracker for mask
    logic [LAT:0] mask_pipe;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mask_pipe <= '0;
        else begin
            mask_pipe[0] <= mask_out;
            for (int i = 0; i < LAT; i++) mask_pipe[i+1] <= mask_pipe[i];
        end
    end

    // Assertion: when mask_out=0, acc_out holds
    logic [DIM*DIM*ACC_W-1:0] acc_prev;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) acc_prev <= '0;
        else acc_prev <= acc_out;
    end
    property hold_when_mask0;
        @(posedge clk) disable iff (!rst_n)
            (mask_out==0) |-> (acc_out==acc_prev);
    endproperty
    assert property(hold_when_mask0) else $fatal("acc_out changed while mask_out=0");

    initial begin
        rst_n = 0; valid_in = 0; q_vec = '0; k_vec = '0; threshold = '0; acc_init = '0; a_in_vec = '0; b_in_vec = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;

        // Test 1: mask should be 0 -> no accumulate
        logic signed [WIDTH-1:0] qv[VEC_LEN];
        logic signed [WIDTH-1:0] kv[VEC_LEN];
        for (int i = 0; i < VEC_LEN; i++) begin
            qv[i] = 1; kv[i] = 1;
            q_vec[i*WIDTH +: WIDTH] = qv[i];
            k_vec[i*WIDTH +: WIDTH] = kv[i];
        end
        threshold = compute_prod_bound(qv, kv) + 1; // force mask=0
        random_vecs();
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
        repeat (LAT+2) @(posedge clk); // allow data to flow
        if (acc_out !== acc_prev) $fatal("Expected no change when mask=0");

        // Test 2: mask=1 -> accumulates
        for (int i = 0; i < VEC_LEN; i++) begin
            qv[i] = 2; kv[i] = 2;
            q_vec[i*WIDTH +: WIDTH] = qv[i];
            k_vec[i*WIDTH +: WIDTH] = kv[i];
        end
        threshold = compute_prod_bound(qv, kv) >> 1; // force mask=1
        random_vecs();
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
        repeat (LAT+2) @(posedge clk);
        if (acc_out == acc_prev) $fatal("Expected accumulator change when mask=1");

        $display("tile_prescreen_array_tb: PASS");
        $finish;
    end
endmodule
