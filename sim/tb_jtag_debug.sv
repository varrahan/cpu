`timescale 1ns/1ps
module tb_jtag_debug;
    logic core_clk = 0, core_rst_n = 0;
    logic tck = 0, trst_n = 1, tms = 1, tdi = 0;
    wire tdo, debug_req, debug_resume, debug_reg_valid, debug_reg_write;
    wire [5:0] debug_reg_addr; wire [63:0] debug_reg_wdata;
    logic debug_halted = 0; logic [31:0] debug_dpc = 32'h100;
    logic [1:0] debug_privilege = 2'b11;
    wire debug_dpc_write, debug_step; wire [31:0] debug_dpc_wdata;
    logic [63:0] registers [0:63]; integer i;
    always #2 core_clk = ~core_clk;
    wire debug_reg_ready = debug_reg_valid && debug_halted;
    wire [63:0] debug_reg_rdata = registers[debug_reg_addr];
    always @(posedge core_clk) begin
        if (!core_rst_n) debug_halted <= 0;
        else begin
            if (debug_req) debug_halted <= 1;
            if (debug_resume) debug_halted <= 0;
            if (debug_reg_ready && debug_reg_write)
                registers[debug_reg_addr] <= debug_reg_wdata;
            if (debug_dpc_write) debug_dpc <= debug_dpc_wdata;
        end
    end
    riscv_debug_transport dut (
        .core_clk(core_clk), .core_rst_n(core_rst_n), .tck(tck),
        .trst_n(trst_n), .tms(tms), .tdi(tdi), .tdo(tdo),
        .debug_req(debug_req), .debug_resume(debug_resume),
        .debug_reg_valid(debug_reg_valid), .debug_reg_write(debug_reg_write),
        .debug_reg_addr(debug_reg_addr), .debug_reg_wdata(debug_reg_wdata),
        .debug_reg_ready(debug_reg_ready), .debug_reg_rdata(debug_reg_rdata),
        .debug_halted(debug_halted), .debug_dpc(debug_dpc),
        .debug_privilege(debug_privilege), .debug_dpc_write(debug_dpc_write),
        .debug_dpc_wdata(debug_dpc_wdata), .debug_step(debug_step)
    );
    task automatic tick(input logic next_tms, input logic next_tdi,
                        output logic sampled_tdo);
        begin
            tms = next_tms; tdi = next_tdi; #1; sampled_tdo = tdo;
            #4; tck = 1; #5; tck = 0;
        end
    endtask
    task automatic set_ir(input logic [4:0] value);
        logic ignored; integer bitno;
        begin
            tick(1, 0, ignored); tick(1, 0, ignored);
            tick(0, 0, ignored); tick(0, 0, ignored);
            for (bitno = 0; bitno < 5; bitno++)
                tick(bitno == 4, value[bitno], ignored);
            tick(1, 0, ignored); tick(0, 0, ignored);
        end
    endtask
    task automatic scan_dmi(input logic [40:0] request,
                            output logic [40:0] response);
        logic sampled; integer bitno;
        begin
            tick(1, 0, sampled); tick(0, 0, sampled); tick(0, 0, sampled);
            for (bitno = 0; bitno < 41; bitno++) begin
                tick(bitno == 40, request[bitno], sampled);
                response[bitno] = sampled;
            end
            tick(1, 0, sampled); tick(0, 0, sampled);
        end
    endtask
    task automatic scan_dr32(output logic [31:0] response);
        logic sampled; integer bitno;
        begin
            tick(1, 0, sampled); tick(0, 0, sampled); tick(0, 0, sampled);
            for (bitno = 0; bitno < 32; bitno++) begin
                tick(bitno == 31, 0, sampled);
                response[bitno] = sampled;
            end
            tick(1, 0, sampled); tick(0, 0, sampled);
        end
    endtask
    task automatic dmi_write(input logic [6:0] address,
                             input logic [31:0] value);
        logic [40:0] response;
        begin
            scan_dmi({address, value, 2'b10}, response);
            repeat (12) @(posedge core_clk);
            repeat (4) tick(0, 0, response[0]);
            scan_dmi(41'b0, response);
            if (response[1:0] != 0)
                $fatal(1, "DMI write failed addr=%h op=%b pending=%b req=%b/%b rsp=%b/%b",
                       address, response[1:0], dut.request_pending_tck,
                       dut.req_toggle_sync_core, dut.req_seen_core,
                       dut.rsp_toggle_core, dut.rsp_toggle_sync_tck);
        end
    endtask
    task automatic dmi_read(input logic [6:0] address,
                            output logic [31:0] value);
        logic [40:0] response;
        begin
            scan_dmi({address, 32'b0, 2'b01}, response);
            repeat (12) @(posedge core_clk);
            repeat (4) tick(0, 0, response[0]);
            scan_dmi(41'b0, response);
            if (response[1:0] != 0)
                $fatal(1, "DMI read failed addr=%h op=%b", address, response[1:0]);
            value = response[33:2];
        end
    endtask
    initial begin : test
        logic ignored; logic [31:0] value;
        for (i = 0; i < 64; i++) registers[i] = 0;
        repeat (4) @(posedge core_clk);
        trst_n = 0; #1; trst_n = 1; core_rst_n = 1;
        repeat (6) tick(1, 0, ignored); tick(0, 0, ignored);
        scan_dr32(value);
        if (value != 32'h0000_0001) $fatal(1, "JTAG IDCODE mismatch: %h", value);
        set_ir(5'h10); scan_dr32(value);
        if (value[3:0] != 4'd1 || value[9:4] != 6'd7)
            $fatal(1, "JTAG DTMCS mismatch: %h", value);
        set_ir(5'h11);
        dmi_write(7'h10, 32'h8000_0001);
        if (!debug_halted) $fatal(1, "JTAG halt request failed");
        dmi_read(7'h11, value);
        if (value[9:8] != 2'b11 || value[3:0] != 4'd3)
            $fatal(1, "Debug 1.0 dmstatus mismatch: %h", value);
        dmi_write(7'h17, 32'h0022_0301); repeat (8) @(posedge core_clk);
        dmi_read(7'h04, value);
        if (value != 32'h4014_112d) $fatal(1, "abstract misa read failed");
        dmi_write(7'h04, 32'h55aa_1234);
        dmi_write(7'h17, 32'h0023_100a); repeat (8) @(posedge core_clk);
        if (registers[10][31:0] != 32'h55aa_1234)
            $fatal(1, "abstract GPR write failed");
        registers[10] = 64'hdead_beef;
        dmi_write(7'h17, 32'h0022_100a); repeat (8) @(posedge core_clk);
        dmi_read(7'h04, value);
        if (value != 32'hdead_beef) $fatal(1, "abstract GPR read failed");
        dmi_write(7'h04, 32'h246); dmi_write(7'h17, 32'h0023_07b1);
        if (debug_dpc != 32'h246) $fatal(1, "abstract dpc write failed");
        dmi_write(7'h10, 32'h4000_0001); repeat (8) @(posedge core_clk);
        if (debug_halted) $fatal(1, "JTAG resume request failed");
        $display("PASS: RISC-V Debug 1.0 JTAG DTM/minimal DM regression");
        $finish;
    end
endmodule
