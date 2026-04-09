`timescale 1ns/1ps

module softmax_masked_tb;
    localparam int DATA_W  = 16;
    localparam int LUT_W   = 16;
    localparam int LUT_ADDR= 12;
    localparam int VEC_LEN = 4;

    logic clk, rst_n, valid_in, valid_out;
    logic [VEC_LEN*DATA_W-1:0] in_vec;
    logic [VEC_LEN-1:0] mask;
    logic [VEC_LEN*LUT_W-1:0] out_vec;

    softmax_masked #(
        .DATA_W(DATA_W),
        .LUT_ADDR(LUT_ADDR),
        .LUT_W(LUT_W),
        .VEC_LEN(VEC_LEN)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .in_vec(in_vec),
        .mask(mask),
        .valid_out(valid_out),
        .out_vec(out_vec)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Simple behavioral softmax for reference (real math)
    function automatic real softmax_ref(input real vals[VEC_LEN], input bit m[VEC_LEN], input int idx);
        real maxv; real sum;
        maxv = -1e9;
        for (int i=0;i<VEC_LEN;i++) if (m[i]) if (vals[i] > maxv) maxv = vals[i];
        sum = 0.0;
        for (int i=0;i<VEC_LEN;i++) if (m[i]) sum += $exp(vals[i]-maxv);
        if (!m[idx]) return 0.0;
        return $exp(vals[idx]-maxv)/sum;
    endfunction

    initial begin
        rst_n = 0; valid_in = 0; in_vec = '0; mask = '0;
        repeat (3) @(posedge clk);
        rst_n = 1;

        real vals[VEC_LEN];
        bit  msk[VEC_LEN];
        // Test vector
        vals[0]=0.2; vals[1]=0.4; vals[2]=-0.1; vals[3]=0.0;
        msk[0]=1; msk[1]=1; msk[2]=1; msk[3]=0; // mask last entry
        for (int i=0;i<VEC_LEN;i++) begin
            int fixed = $rtoi(vals[i]*(1<<13));
            in_vec[i*DATA_W +: DATA_W] = fixed[DATA_W-1:0];
            mask[i] = msk[i];
        end
        valid_in = 1;
        @(posedge clk);
        valid_in = 0;
        repeat (4) @(posedge clk); // allow pipeline

        // Check outputs roughly (tolerance)
        for (int i=0;i<VEC_LEN;i++) begin
            real expect = softmax_ref(vals, msk, i);
            real got = $itor($signed(out_vec[i*LUT_W +: LUT_W]))/(1<<LUT_W);
            if (msk[i]==0 && got > 1e-3) $fatal("Masked entry not zero");
            if (msk[i]==1 && ($abs(got-expect) > 0.05))
                $fatal("Softmax mismatch idx %0d: got %f exp %f", i, got, expect);
        end

        $display("softmax_masked_tb: PASS (coarse check)");
        $finish;
    end
endmodule
