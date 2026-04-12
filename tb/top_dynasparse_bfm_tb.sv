`timescale 1ns/1ps

// Bus Functional Model TB:
// - writes threshold and start via AXI-lite
// - writes one Q/K block into SRAM via direct WE (shortcut, not AXI-lite)
// - waits for done
// - reports counters (blocks, MACs, runtime)

module top_dynasparse_bfm_tb;
    localparam int WIDTH   = 16;
    localparam int VEC_LEN = 8;
    localparam int SUM_W   = WIDTH + $clog2(VEC_LEN) + 4;
    localparam int PROD_W  = 2*SUM_W;
    localparam int DATA_W  = 16;
    localparam int ACC_W   = 52;
    localparam int DIM     = 2;
    localparam int ADDR_W  = 4;

    logic clk, rst_n;
    logic s_aclk, s_aresetn;
    logic [3:0] awaddr; logic awvalid; logic awready;
    logic [31:0] wdata; logic [3:0] wstrb; logic wvalid; logic wready;
    logic [1:0] bresp; logic bvalid; logic bready;
    logic [3:0] araddr; logic arvalid; logic arready;
    logic [31:0] rdata; logic [1:0] rresp; logic rvalid; logic rready;
    logic done;

    top_dynasparse #(
        .WIDTH(WIDTH),
        .VEC_LEN(VEC_LEN),
        .SUM_W(SUM_W),
        .PROD_W(PROD_W),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .DIM(DIM),
        .ADDR_W(ADDR_W)
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

    logic [31:0] blocks_compute, blocks_skip, macs_compute, macs_skip;

    initial begin
        // VCD dump for visualization (compatible with Icarus/GTKWave)
        $dumpfile("top_dynasparse_bfm.vcd");
        $dumpvars(0, top_dynasparse_bfm_tb);

        rst_n = 0; s_aresetn = 0;
        awaddr=0; awvalid=0; wdata=0; wstrb=4'hF; wvalid=0; bready=1;
        araddr=0; arvalid=0; rready=1;
        repeat(5) @(posedge clk);
        rst_n = 1; s_aresetn = 1;

        // write threshold low
        axi_write(8'h08, 32'd10000);
        // write one Q/K block directly into SRAM port 0 (address 0)
        force dut.q_we = 1'b1;
        force dut.k_we = 1'b1;
        force dut.q_waddr = '0;
        force dut.k_waddr = '0;
        // simple pattern
        force dut.q_wdata = {VEC_LEN{16'sd2}};
        force dut.k_wdata = {VEC_LEN{16'sd3}};
        @(posedge clk);
        release dut.q_we;
        release dut.k_we;

        // start
        axi_write(8'h00, 32'h1);

        // wait for done
        wait(done);
        $display("Done asserted");

        // read counters
        blocks_compute = axi_read(8'h10);
        blocks_skip    = axi_read(8'h14);
        macs_compute   = axi_read(8'h18);
        macs_skip      = axi_read(8'h1C);
        $display("blocks_compute=%0d blocks_skip=%0d macs_compute=%0d macs_skip=%0d",
                 blocks_compute, blocks_skip, macs_compute, macs_skip);
        $finish;
    end

    task axi_write(input [7:0] addr, input [31:0] data);
        begin
            awaddr  <= addr[3:0];
            awvalid <= 1;
            wdata   <= data;
            wvalid  <= 1;
            @(posedge s_aclk);
            awvalid <= 0;
            wvalid  <= 0;
            wait(bvalid);
            @(posedge s_aclk);
        end
    endtask

    function automatic [31:0] axi_read(input [7:0] addr);
        begin
            araddr  <= addr[3:0];
            arvalid <= 1;
            @(posedge s_aclk);
            arvalid <= 0;
            wait(rvalid);
            axi_read = rdata;
            @(posedge s_aclk);
        end
    endfunction

endmodule
