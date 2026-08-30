`timescale 1ps/1ps

module tb_photonic_macros;
    reg clk = 0, rst_n = 0, stall = 1, flush = 0;
    reg [31:0] redirect_pc = 0;
    reg [2:0] instr_length = 4;
    wire [31:0] pc;
    wire issue_window;
    reg [31:0] pmpcfg0 = 0, pmpaddr0 = 0;
    reg [31:0] pmp_addr = 0;
    wire pmp_allow;
    reg md_start = 0;
    wire md_ready, md_busy, md_done;
    wire [31:0] md_result;
    reg mem_we = 0;
    reg [1:0] mem_waddr = 0;
    reg [31:0] mem_wdata = 0;
    reg [3:0] mem_wbe = 0;
    reg [3:0] mem_raddr = 0;
    wire [63:0] mem_rdata;

    always #5 clk = ~clk;

    P_PC32 pc_macro (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .redirect_pc(redirect_pc), .instr_length(instr_length),
        .pc(pc), .issue_window(issue_window)
    );
    P_PMP32 pmp_macro (
        .addr(pmp_addr), .size(4'd4), .privilege(2'd0),
        .access_read(1'b1), .access_write(1'b0), .access_execute(1'b0),
        .pmpcfg0(pmpcfg0), .pmpaddr0(pmpaddr0),
        .pmpaddr1(0), .pmpaddr2(0), .pmpaddr3(0), .allow(pmp_allow)
    );
    P_MULDIV32 md_macro (
        .clk(clk), .rst_n(rst_n), .start(md_start), .flush(flush),
        .op(3'b000), .a(6), .b(7), .ready(md_ready), .busy(md_busy),
        .done(md_done), .result(md_result)
    );
    P_MEM_ASYNC #(
        .DATA_WIDTH(32), .ADDR_WIDTH(2), .READ_PORTS(2), .BYTE_LANES(4)
    ) memory_macro (
        .clk(clk), .rst_n(rst_n), .we(mem_we),
        .waddr(mem_waddr), .wdata(mem_wdata),
        .wbe(mem_wbe), .raddr(mem_raddr), .rdata(mem_rdata)
    );

    initial begin
        repeat (2) @(posedge clk);
        #1;
        if ($isunknown(mem_rdata) || mem_rdata != 0)
            $fatal(1, "memory macro reset initialization failure");
        rst_n = 1;
        stall = 0;
        @(posedge clk); #1;
        if (issue_window || pc != 0) $fatal(1, "PC accept phase failed");
        @(posedge clk); #1;
        if (!issue_window || pc != 4) $fatal(1, "PC advance phase failed");
        redirect_pc = 32'h100;
        flush = 1;
        @(posedge clk); #1;
        flush = 0;
        if (pc != 32'h100) $fatal(1, "PC predicate redirect failed");

        pmpcfg0 = 32'h0000_000f;
        pmpaddr0 = 32'h0000_0400;
        pmp_addr = 32'h0000_0100; #1;
        if (!pmp_allow) $fatal(1, "PMP macro allowed-range failure");
        pmp_addr = 32'h0000_1000; #1;
        if (pmp_allow) $fatal(1, "PMP macro denied-range failure");

        md_start = 1;
        @(posedge clk); #1; md_start = 0;
        wait (md_done); #1;
        if (md_result != 42) $fatal(1, "M macro result failure");

        mem_we = 1; mem_waddr = 1; mem_wdata = 32'hdead_beef;
        mem_wbe = 4'b1111;
        @(posedge clk); #1; mem_we = 0; mem_raddr[1:0] = 1; #1;
        if (mem_rdata[31:0] != 32'hdead_beef)
            $fatal(1, "memory macro full-word write failure");
        mem_we = 1; mem_wdata = 32'h00aa_0000; mem_wbe = 4'b0100;
        @(posedge clk); #1; mem_we = 0; #1;
        if (mem_rdata[31:0] != 32'hdeaa_beef)
            $fatal(1, "memory macro byte-write failure");
        $display("PASS: photonic macro binding regression complete");
        $finish;
    end
endmodule
