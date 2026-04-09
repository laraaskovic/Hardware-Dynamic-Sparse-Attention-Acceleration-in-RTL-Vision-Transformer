`timescale 1ns/1ps

module reciprocal_unit_tb;
    localparam int DEN_W = 24;
    localparam int OUT_W = 16;
    localparam int SCALE = 16;

    logic [DEN_W-1:0] denom;
    logic [OUT_W-1:0] recip;

    reciprocal_unit #(
        .DEN_W(DEN_W),
        .OUT_W(OUT_W),
        .SCALE(SCALE)
    ) dut (
        .denom(denom),
        .recip(recip)
    );

    initial begin
        // simple directed tests
        denom = 24'd1; #1;
        if (recip != (1<<SCALE)) $fatal("recip 1 failed");
        denom = 24'd2; #1;
        if (recip != ((1<<SCALE)/2)) $fatal("recip 2 failed");
        denom = 24'd100; #1;
        if (recip == 0) $fatal("recip 100 zero");
        // random sweep
        for (int i=0;i<100;i++) begin
            denom = $urandom_range(1, 1000000);
            #1;
        end
        $display("reciprocal_unit_tb: PASS");
        $finish;
    end
endmodule
