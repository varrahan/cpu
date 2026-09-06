`timescale 1ns/1ps
module tb_debug;
    logic clk = 0, rst_n = 0, debug_req = 0, resume_req = 0;
    logic step = 0, dpc_write = 0;
    logic [31:0] dpc_wdata = 0;
    logic retire_boundary = 0;
    logic [31:0] next_pc = 0;
    wire enter_fire, resume_fire, halted;
    wire [31:0] dpc;
    always #5 clk = ~clk;
    debug_control dut (.*);
    initial begin
        repeat (2) @(posedge clk); rst_n = 1;
        debug_req = 1; next_pc = 32'h123; retire_boundary = 1;
        @(posedge clk); #1; retire_boundary = 0; debug_req = 0;
        if (!halted || dpc != 32'h122) $fatal(1, "debug halt mismatch");
        dpc_wdata = 32'h456; dpc_write = 1;
        @(posedge clk); #1; dpc_write = 0;
        if (dpc != 32'h456) $fatal(1, "debug dpc write mismatch");
        step = 1; resume_req = 1; #1;
        if (!resume_fire) $fatal(1, "debug resume handshake mismatch");
        @(posedge clk); #1;
        resume_req = 0;
        if (halted) $fatal(1, "debug resume mismatch");
        retire_boundary = 1;
        @(posedge clk); #1; retire_boundary = 0;
        if (!halted) $fatal(1, "debug single-step mismatch");
        $display("PASS: debug retirement-boundary regression complete");
        $finish;
    end
endmodule
