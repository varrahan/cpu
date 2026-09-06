`timescale 1ns/1ps

module tb_async_memory;
    logic clk = 0, rst_n = 0;
    logic mem_we = 0;
    logic [1:0] mem_waddr = 0;
    logic [31:0] mem_wdata = 0;
    logic [3:0] mem_wbe = 0;
    logic [3:0] mem_raddr = 0;
    wire [63:0] mem_rdata;

    always #5 clk = ~clk;

    async_memory #(
        .DATA_WIDTH(32), .ADDR_WIDTH(2), .READ_PORTS(2), .BYTE_LANES(4)
    ) dut (
        .clk(clk), .rst_n(rst_n), .we(mem_we),
        .waddr(mem_waddr), .wdata(mem_wdata),
        .wbe(mem_wbe), .raddr(mem_raddr), .rdata(mem_rdata)
    );

    initial begin
        repeat (2) @(posedge clk);
        #1;
        if ($isunknown(mem_rdata) || mem_rdata != 0)
            $fatal(1, "memory reset initialization failure");
        rst_n = 1;
        mem_we = 1; mem_waddr = 1; mem_wdata = 32'hdead_beef;
        mem_wbe = 4'b1111;
        @(posedge clk); #1; mem_we = 0; mem_raddr[1:0] = 1; #1;
        if (mem_rdata[31:0] != 32'hdead_beef)
            $fatal(1, "memory full-word write failure");
        mem_we = 1; mem_wdata = 32'h00aa_0000; mem_wbe = 4'b0100;
        @(posedge clk); #1; mem_we = 0; #1;
        if (mem_rdata[31:0] != 32'hdeaa_beef)
            $fatal(1, "memory byte-write failure");
        $display("PASS: asynchronous-read memory reset and byte writes");
        $finish;
    end
endmodule
