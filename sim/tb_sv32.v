`timescale 1ns/1ps
module tb_sv32;
    reg clk = 0, rst_n = 0, flush = 0, req_valid = 0;
    always #5 clk = ~clk;
    reg [31:0] vaddr, satp;
    reg [1:0] privilege;
    reg access_read, access_write, access_execute;
    reg mstatus_sum, mstatus_mxr;
    wire resp_ready, page_fault, access_fault;
    wire [31:0] paddr;
    wire mem_req_valid, mem_req_write, mem_req_amo, mem_rsp_ready;
    wire [31:0] mem_req_addr, mem_req_wdata;
    wire [3:0] mem_req_be;
    wire [4:0] mem_req_amo_op;
    reg mem_rsp_valid = 0, mem_rsp_error = 0;
    reg [31:0] mem_rsp_rdata = 0;
    reg [31:0] mem [0:4095];
    integer i, timeout;

    sv32_mmu dut (.*,
        .mem_req_ready(1'b1), .mem_req_allow(1'b1));

    always @(posedge clk) begin
        mem_rsp_valid <= 0;
        if (mem_req_valid) begin
            mem_rsp_valid <= 1;
            mem_rsp_rdata <= mem[mem_req_addr[13:2]];
            if (mem_req_amo)
                mem[mem_req_addr[13:2]] <=
                    mem[mem_req_addr[13:2]] | mem_req_wdata;
        end
    end

    task translate;
        input expected_fault;
        begin
            req_valid = 1;
            timeout = 0;
            while (!resp_ready && timeout < 40) begin
                @(posedge clk); #1; timeout = timeout + 1;
            end
            if (!resp_ready) $fatal(1, "Sv32 timeout");
            if (page_fault !== expected_fault || access_fault)
                $fatal(1, "Sv32 fault mismatch");
            req_valid = 0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        for (i = 0; i < 4096; i = i + 1) mem[i] = 0;
        vaddr = 32'h0040_3004;
        satp = 32'h8000_0001; // root page at 0x1000
        privilege = 0;
        access_read = 0; access_write = 1; access_execute = 0;
        mstatus_sum = 0; mstatus_mxr = 0;
        mem[12'h401] = 32'h0000_0801; // root[1] -> PPN 2
        mem[12'h803] = 32'h0000_0c57; // leaf -> PPN 3, D initially clear
        repeat (3) @(posedge clk);
        rst_n = 1;
        translate(0);
        if (paddr != 32'h0000_3004 || !mem[12'h803][7])
            $fatal(1, "Sv32 translation/A-D update mismatch");
        access_write = 0; access_execute = 1;
        translate(1);
        satp = 0; privilege = 3;
        translate(0);
        if (paddr != vaddr) $fatal(1, "bare translation mismatch");
        $display("PASS: Sv32 TLB/page-walker regression complete");
        $finish;
    end
endmodule
