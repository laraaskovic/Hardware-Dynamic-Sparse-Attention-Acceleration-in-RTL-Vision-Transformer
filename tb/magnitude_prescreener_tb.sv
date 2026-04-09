`timescale 1ns/1ps

module magnitude_prescreener_tb;

    // Parameters
    localparam int WIDTH   = 16;
    localparam int VEC_LEN = 16;  // keep small for sim speed
    localparam int SUM_W   = WIDTH + $clog2(VEC_LEN) + 1;
    localparam int PROD_W  = 2 * SUM_W;
    localparam int LATENCY = 2;   // pipeline depth in DUT

    // DUT I/O
    logic clk, rst_n;
    logic valid_in;
    logic [VEC_LEN*WIDTH-1:0] q_flat, k_flat;
    logic [PROD_W-1:0] threshold;
    logic valid_out, valid_mask;
    logic [PROD_W-1:0] product_mon, threshold_mon;

    magnitude_prescreener #(
        .WIDTH(WIDTH),
        .VEC_LEN(VEC_LEN),
        .SUM_W(SUM_W),
        .PROD_W(PROD_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .q_vec_flat(q_flat),
        .k_vec_flat(k_flat),
        .threshold(threshold),
        .valid_out(valid_out),
        .valid_mask(valid_mask),
        .product_mon(product_mon),
        .threshold_mon(threshold_mon)
    );

    // Bind assertion module
    magnitude_prescreener_assert #(
        .PROD_W(PROD_W),
        .LATENCY(LATENCY)
    ) dut_assert (
        .clk(clk),
        .rst_n(rst_n),
        .valid_out(valid_out),
        .valid_mask(valid_mask),
        .product_mon(product_mon),
        .threshold_mon(threshold_mon)
    );

    // Clock
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // Stimulus helpers
    function automatic logic signed [WIDTH-1:0] rand_fixed();
        // Uniform over small range to avoid overflow in test
        rand_fixed = $urandom_range(-(1 << (WIDTH-2)), (1 << (WIDTH-2)) - 1);
    endfunction

    function automatic void pack_vec(ref logic [VEC_LEN*WIDTH-1:0] flat,
                                     logic signed [WIDTH-1:0] vec[VEC_LEN]);
        for (int i = 0; i < VEC_LEN; i++) begin
            flat[i*WIDTH +: WIDTH] = vec[i];
        end
    endfunction

    function automatic longint unsigned golden_mask(
        logic signed [WIDTH-1:0] qv[VEC_LEN],
        logic signed [WIDTH-1:0] kv[VEC_LEN],
        longint unsigned th
    );
        longint unsigned sum_q = 0;
        longint unsigned sum_k = 0;
        for (int i = 0; i < VEC_LEN; i++) begin
            sum_q += (qv[i][WIDTH-1]) ? (~qv[i] + 1) : qv[i];
            sum_k += (kv[i][WIDTH-1]) ? (~kv[i] + 1) : kv[i];
        end
        golden_mask = (sum_q * sum_k >= th);
    endfunction

    // Expected pipeline tracking
    typedef struct packed {
        bit valid;
        bit mask;
    } exp_t;
    exp_t exp_queue [0:LATENCY]; // simple shift register

    task automatic push_expect(bit v, bit m);
        for (int i = LATENCY; i > 0; i--) begin
            exp_queue[i] = exp_queue[i-1];
        end
        exp_queue[0].valid = v;
        exp_queue[0].mask  = m;
    endtask

    task automatic pop_and_check();
        if (exp_queue[LATENCY].valid) begin
            if (valid_out !== exp_queue[LATENCY].valid) begin
                $fatal(1, "valid_out mismatch at time %0t", $time);
            end
            if (valid_mask !== exp_queue[LATENCY].mask) begin
                $fatal(1, "mask mismatch at time %0t: got %0b exp %0b",
                       $time, valid_mask, exp_queue[LATENCY].mask);
            end
        end
    endtask

    // Main test sequence
    initial begin
        rst_n = 0; valid_in = 0; q_flat = '0; k_flat = '0; threshold = '0;
        for (int i = 0; i <= LATENCY; i++) exp_queue[i] = '{valid:0, mask:0};
        repeat (4) @(posedge clk);
        rst_n = 1;

        int unsigned NUM_TESTS = 200;
        for (int t = 0; t < NUM_TESTS; t++) begin
            logic signed [WIDTH-1:0] qv[VEC_LEN];
            logic signed [WIDTH-1:0] kv[VEC_LEN];
            for (int i = 0; i < VEC_LEN; i++) begin
                qv[i] = rand_fixed();
                kv[i] = rand_fixed();
            end

            // Choose threshold relative to sums to exercise both branches
            longint unsigned sum_q = 0, sum_k = 0;
            for (int i = 0; i < VEC_LEN; i++) begin
                sum_q += (qv[i][WIDTH-1]) ? (~qv[i] + 1) : qv[i];
                sum_k += (kv[i][WIDTH-1]) ? (~kv[i] + 1) : kv[i];
            end
            longint unsigned prod = sum_q * sum_k;
            longint unsigned th = (t % 2 == 0) ? prod >> 1 : prod + (1 << (SUM_W-2));

            pack_vec(q_flat, qv);
            pack_vec(k_flat, kv);
            threshold = th[PROD_W-1:0];
            valid_in  = 1'b1;

            bit exp_mask = golden_mask(qv, kv, th);
            push_expect(1'b1, exp_mask);

            @(posedge clk);
            pop_and_check();
        end

        // Flush pipeline
        valid_in = 0;
        repeat (LATENCY+2) begin
            @(posedge clk);
            pop_and_check();
        end

        $display("magnitude_prescreener_tb: PASS");
        $finish;
    end

endmodule
