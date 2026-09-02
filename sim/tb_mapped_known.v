`timescale 1ps/1ps

module tb_mapped_known;
    reg clk = 0;
    reg rst_n = 0;
    reg irq_m_software = 0, irq_m_timer = 0, irq_m_external = 0;
    reg irq_s_software = 0, irq_s_timer = 0, irq_s_external = 0, nmi = 0;
    reg debug_req = 0, debug_resume = 0;
    reg debug_reg_valid = 0, debug_reg_write = 0;
    reg [5:0] debug_reg_addr = 0;
    reg [63:0] debug_reg_wdata = 0;
    wire debug_reg_ready, debug_halted;
    wire [63:0] debug_reg_rdata;
    wire [31:0] debug_dpc;
    wire imem_req_valid, imem_rsp_ready;
    reg imem_req_ready = 1, imem_rsp_valid = 0;
    wire [31:0] imem_req_addr;
    reg [31:0] imem_rsp_rdata = 0;
    reg imem_rsp_error = 0;
    wire dmem_req_valid, dmem_req_write, dmem_rsp_ready;
    reg dmem_req_ready = 1, dmem_rsp_valid = 0;
    wire [31:0] dmem_req_addr, dmem_req_wdata;
    wire [3:0] dmem_req_be;
    wire dmem_req_amo;
    wire [4:0] dmem_req_amo_op;
    reg reservation_invalidate = 0;
    reg [31:0] dmem_rsp_rdata = 0;
    reg dmem_rsp_error = 0;
    reg [31:0] imem [0:8191];
    reg [31:0] dmem [0:8191];
    reg [31:0] max_imem_addr = 0;
    integer index, lane, program_timeout;

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (!rst_n)
            imem_rsp_valid <= 0;
        else begin
            if (imem_rsp_valid && imem_rsp_ready)
                imem_rsp_valid <= 0;
            if (imem_req_valid && imem_req_ready) begin
                imem_rsp_valid <= 1;
                imem_rsp_rdata <= imem[imem_req_addr[14:2]];
                imem_rsp_error <= 0;
                if (imem_req_addr > max_imem_addr)
                    max_imem_addr <= imem_req_addr;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n)
            dmem_rsp_valid <= 0;
        else begin
            if (dmem_rsp_valid && dmem_rsp_ready)
                dmem_rsp_valid <= 0;
            if (dmem_req_valid && dmem_req_ready) begin
                dmem_rsp_valid <= 1;
                dmem_rsp_rdata <= dmem[dmem_req_addr[14:2]];
                dmem_rsp_error <= 0;
                if (dmem_req_write)
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (dmem_req_be[lane])
                            dmem[dmem_req_addr[14:2]][lane*8 +: 8] <=
                                dmem_req_wdata[lane*8 +: 8];
            end
        end
    end

    top dut (
        .clk(clk), .rst_n(rst_n),
        .irq_m_software(irq_m_software), .irq_m_timer(irq_m_timer),
        .irq_m_external(irq_m_external), .irq_s_software(irq_s_software),
        .irq_s_timer(irq_s_timer), .irq_s_external(irq_s_external), .nmi(nmi),
        .debug_req(debug_req), .debug_resume(debug_resume),
        .debug_reg_valid(debug_reg_valid), .debug_reg_write(debug_reg_write),
        .debug_reg_addr(debug_reg_addr), .debug_reg_wdata(debug_reg_wdata),
        .debug_reg_ready(debug_reg_ready), .debug_reg_rdata(debug_reg_rdata),
        .debug_halted(debug_halted), .debug_dpc(debug_dpc),
        .debug_dpc_write(1'b0), .debug_dpc_wdata(32'b0),
        .debug_step(1'b0), .debug_privilege(),
        .imem_req_valid(imem_req_valid), .imem_req_ready(imem_req_ready),
        .imem_req_addr(imem_req_addr), .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_ready(imem_rsp_ready), .imem_rsp_rdata(imem_rsp_rdata),
        .imem_rsp_error(imem_rsp_error), .dmem_req_valid(dmem_req_valid),
        .dmem_req_ready(dmem_req_ready), .dmem_req_write(dmem_req_write),
        .dmem_req_addr(dmem_req_addr), .dmem_req_wdata(dmem_req_wdata),
        .dmem_req_be(dmem_req_be), .dmem_req_amo(dmem_req_amo),
        .dmem_req_amo_op(dmem_req_amo_op),
        .reservation_invalidate(reservation_invalidate),
        .dmem_rsp_valid(dmem_rsp_valid), .dmem_rsp_ready(dmem_rsp_ready),
        .dmem_rsp_rdata(dmem_rsp_rdata), .dmem_rsp_error(dmem_rsp_error)
    );

    wire [208:0] external_outputs = {
        debug_reg_ready, debug_reg_rdata, debug_halted, debug_dpc,
        imem_req_valid, imem_req_addr, imem_rsp_ready,
        dmem_req_valid, dmem_req_write, dmem_req_addr, dmem_req_wdata,
        dmem_req_be, dmem_req_amo, dmem_req_amo_op, dmem_rsp_ready
    };

    always @(negedge clk)
        if (rst_n && $isunknown(external_outputs))
            $fatal(1, "mapped outputs became unknown after reset");

    initial begin
        for (index = 0; index < 8192; index = index + 1) begin
            imem[index] = 32'h0000_0013;
            dmem[index] = 0;
        end
        $readmemh("build/programs/rv32gc_stress.hex", imem);
        $dumpfile("build/photonic/known_state.vcd");
        $dumpvars(0, tb_mapped_known);
        repeat (8) @(posedge clk);
        #1;
        if ($isunknown(external_outputs))
            $fatal(1, "mapped outputs unknown during reset");
        rst_n = 1;
        repeat (1024) @(posedge clk);
        #1;
        if ($isunknown(external_outputs))
            $fatal(1, "mapped outputs unknown after reset");
        if (max_imem_addr < 32'hc0)
            $fatal(1, "mapped stress did not progress: max_pc=%h",
                   max_imem_addr);
        $dumpoff;
        program_timeout = 1024;
        while (dmem[256] != 32'h600d_600d && program_timeout < 15000) begin
            @(posedge clk);
            program_timeout = program_timeout + 1;
        end
        if (dmem[256] != 32'h600d_600d ||
            dmem[257] != 32'h8d94_4133 || dmem[258] != 32'h7f20_9540 ||
            dmem[259] != 32'h25fc_f0ad || dmem[260] != 21 ||
            dmem[261] != 8 || dmem[262] != 32'h4a ||
            dmem[263] != 32'h126 || dmem[264] != 32'hc03d_3ad1 ||
            dmem[265] != 32'h4170_0000 || dmem[266] != 32'h4080_0000 ||
            dmem[268] != 0 || dmem[269] != 32'h402e_0000 ||
            dmem[270] != 32'h5555_5555 || dmem[271] != 32'h3ff5_5555 ||
            dmem[276] != 32'h4000_0000 || dmem[278] != 0 ||
            dmem[279] != 32'h401c_0000 || dmem[280] != 32'h40 ||
            dmem[281] != 32'haaaa_aabb || dmem[282] != 32'h0005_105e)
            $fatal(1, "mapped RV32GC workload signature failure");
        $display("PASS: mapped RV32GC signatures in %0d cycles",
                 program_timeout);
        $finish;
    end
endmodule
