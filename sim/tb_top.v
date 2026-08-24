`timescale 1ns/1ps

module tb_top;
    reg         clk;
    reg         rst_n;
    wire [31:0] imem_data;
    wire [31:0] dmem_rdata;
    wire [31:0] imem_addr;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire        dmem_we;
    wire [3:0]  dmem_be;
    wire [31:0] dbg_pc;
    wire [31:0] dbg_instr_if;
    wire [31:0] dbg_instr_id;
    wire [4:0]  dbg_rd_ex;
    wire [4:0]  dbg_rd_mem;
    wire [4:0]  dbg_rd_wb;
    wire        dbg_stall;
    wire        dbg_flush;
    reg [31:0] imem [0:255];
    reg [31:0] dmem [0:255];

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    assign imem_data = imem[imem_addr[9:2]];
    assign dmem_rdata = dmem[dmem_addr[9:2]];
    always @(posedge clk) begin
        if (dmem_we) begin
            if (dmem_be[0]) dmem[dmem_addr[9:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_be[1]) dmem[dmem_addr[9:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_be[2]) dmem[dmem_addr[9:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_be[3]) dmem[dmem_addr[9:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    top dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .imem_addr   (imem_addr),
        .imem_data   (imem_data),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_we     (dmem_we),
        .dmem_be     (dmem_be),
        .dmem_rdata  (dmem_rdata),
        .dbg_pc      (dbg_pc),
        .dbg_instr_if(dbg_instr_if),
        .dbg_instr_id(dbg_instr_id),
        .dbg_rd_ex   (dbg_rd_ex),
        .dbg_rd_mem  (dbg_rd_mem),
        .dbg_rd_wb   (dbg_rd_wb),
        .dbg_stall   (dbg_stall),
        .dbg_flush   (dbg_flush)
    );

    integer i;
    integer cycle_count;
    integer stall_count;
    integer flush_count;

    task load_fibonacci;
        begin
            imem[0]  = 32'h00000093; // addi x1, x0, 0   ; F(0) = 0
            imem[1]  = 32'h00100113; // addi x2, x0, 1   ; F(1) = 1
            imem[2]  = 32'h00900213; // addi x4, x0, 9   ; counter = 9
            // loop:
            imem[3]  = 32'h002081b3; // add  x3, x1, x2  ; x3 = x1 + x2
            imem[4]  = 32'h00010093; // addi x1, x2, 0   ; mv x1, x2
            imem[5]  = 32'h00018113; // addi x2, x3, 0   ; mv x2, x3
            imem[6]  = 32'hfff20213; // addi x4, x4, -1  ; counter--
            imem[7]  = 32'hfe0218e3;; // bne  x4, x0, loop (-8*4 -> loop at imem[3])
            
            imem[8]  = 32'h00212023; // sw   x2, 0(x2)   ; store result 
            imem[9]  = 32'h00200023; // sw   x2, 0(x0)   ; store F(10) to addr 0
            imem[10] = 32'h0000006f; // jal  x0, 0       ; loop forever (halt)
            
            // Fill rest with NOPs
            for (i = 11; i < 256; i = i + 1) begin
                imem[i] = 32'h00000013;
            end
    end
    endtask

    task load_memory_hazards;
        begin
            imem[0]  = 32'h02a00093; // addi x1, x0, 42
            imem[1]  = 32'h00102023; // sw   x1, 0(x0)
            imem[2]  = 32'h00002103; // lw   x2, 0(x0)
            imem[3]  = 32'h00110193; // addi x3, x2, 1 (load-use)
            imem[4]  = 32'h00302423; // sw   x3, 8(x0)
            imem[5]  = 32'hf8000213; // addi x4, x0, -128
            imem[6]  = 32'h004002a3; // sb   x4, 5(x0)
            imem[7]  = 32'h00500283; // lb   x5, 5(x0)
            imem[8]  = 32'h00502623; // sw   x5, 12(x0)
            imem[9]  = 32'h00504303; // lbu  x6, 5(x0)
            imem[10] = 32'h00602823; // sw   x6, 16(x0)
            imem[11] = 32'h000083b7; // lui  x7, 8
            imem[12] = 32'h00138393; // addi x7, x7, 1
            imem[13] = 32'h00701323; // sh   x7, 6(x0)
            imem[14] = 32'h00601403; // lh   x8, 6(x0)
            imem[15] = 32'h00802a23; // sw   x8, 20(x0)
            imem[16] = 32'h00605483; // lhu  x9, 6(x0)
            imem[17] = 32'h00902c23; // sw   x9, 24(x0)
            imem[18] = 32'h0000006f; // jal  x0, 0
        end
    endtask

    // Pipeline state tracking
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            if (dbg_stall) stall_count = stall_count + 1;
            if (dbg_flush) flush_count = flush_count + 1;
        end
    end

    initial begin
        $dumpfile("sim/top_wave.vcd");
        $dumpvars(0, tb_top);
        cycle_count = 0;
        stall_count = 0;
        flush_count = 0;

        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h0;
        end

        load_fibonacci();
        $display("=======================================================");
        $display(" 5-Stage Pipelined Processor Simulation");
        $display("=======================================================");
        $display(" Program: Fibonacci F(10) = 55");
        $display("=======================================================");
        $display("%6s | %8s | %10s | %5s | %5s | %5s",
                 "Cycle", "PC", "Instr(Hex)", "Stall", "Flush", "DMEM[0]");
        $display("-------+----------+------------+-------+-------+--------");

        rst_n = 0;
        #15;
        rst_n = 1;

        repeat(100) begin
            @(posedge clk);
            #1;
            $display("%6d | %08h | 0x%08h | %5s | %5s | 0x%08h",
                cycle_count,
                dbg_pc,
                dbg_instr_if,
                dbg_stall ? "STALL" : "     ",
                dbg_flush ? "FLUSH" : "     ",
                dmem[0]);
        end

        $display("=======================================================");
        $display(" Simulation Complete");
        $display(" Total Cycles : %0d", cycle_count);
        $display(" Stall Cycles : %0d", stall_count);
        $display(" Flush Cycles : %0d", flush_count);
        $display(" dmem[0x0]    : 0x%08h (%0d) -- expected 55", dmem[0], dmem[0]);
        $display("=======================================================");
        
        if (dmem[0] != 32'd55)
            $fatal(1, "Fibonacci: got %0d, expected 55", dmem[0]);

        rst_n = 0;
        for (i = 0; i < 256; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h0;
        end
        load_memory_hazards();
        repeat (2) @(posedge clk);
        rst_n = 1;
        repeat (60) @(posedge clk);

        if (dmem[2] != 32'd43 || dmem[3] != 32'hffff_ff80 ||
            dmem[4] != 32'h0000_0080 || dmem[5] != 32'hffff_8001 ||
            dmem[6] != 32'h0000_8001)
            $fatal(1, "Memory/hazard failure: %h %h %h %h %h",
                   dmem[2], dmem[3], dmem[4], dmem[5], dmem[6]);

        $display(" PASS: CPU regression complete");
        $finish;
    end

endmodule
