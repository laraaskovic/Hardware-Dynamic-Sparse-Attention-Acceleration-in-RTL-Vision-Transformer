`timescale 1ns/1ps

// Simple BFM TB to tickle top_dynasparse registers and run one block.
module top_dynasparse_tb;
    localparam int WIDTH   = 16;
    localparam int VEC_LEN = 8;
    localparam int SUM_W   = WIDTH + $clog2(VEC_LEN) + 4;
    localparam int PROD_W  = 2*SUM_W;
    localparam int DATA_W  = 16;
    localparam int ACC_W   = 52;
    localparam int DIM     = 2;

    logic clk, rst_n;
    logic s_aclk, s_aresetn;
    // AXI-lite wires
    logic [3:0] awaddr;
    logic awvalid;
    logic awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic wvalid;
    logic wready;
    logic [1:0]  bresp;
    logic bvalid;
    logic bready;
    logic [3:0] araddr;
    logic arvalid;
    logic arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic rvalid;
    logic rready;
    logic done;

    top_dynasparse #(
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
        .s_axi_aclk(s_aclk),
        .s_axi_aresetn(s_aresetn),
        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .done(done)
    );

    // share clocks
    initial begin clk = 0; s_aclk = 0; end
    always #5 clk = ~clk;
    always #5 s_aclk = ~s_aclk;

    initial begin
        rst_n = 0; s_aresetn = 0;
        awaddr=0; awvalid=0; wdata=0; wstrb=4'hF; wvalid=0; bready=1;
        araddr=0; arvalid=0; rready=1;
        repeat(4) @(posedge clk);
        rst_n = 1; s_aresetn = 1;

        // Write threshold low word (alpha 0.1 scaled)
        axi_write(4'h8, 32'd5000);
        // Start pulse
        axi_write(4'h0, 32'h1);

        repeat(20) @(posedge clk);
        $display("top_dynasparse_tb completed (no functional check)");
        $finish;
    end

    task axi_write(input [3:0] addr, input [31:0] data);
        begin
            awaddr  <= addr;
            awvalid <= 1;
            wdata   <= data;
            wvalid  <= 1;
            @(posedge s_aclk);
            awvalid <= 0;
            wvalid  <= 0;
            // wait for bvalid
            wait (bvalid);
            @(posedge s_aclk);
        end
    endtask

endmodule
