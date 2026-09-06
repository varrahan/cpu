`timescale 1ns/1ps

module tb_act4;
    localparam integer MEM_BYTES = 1 << 22;
    localparam [31:0] CONSOLE_ADDR = 32'h1000_0000;
    localparam [31:0] HALT_ADDR = 32'h2000_0000;
    localparam [31:0] PASS_VALUE = 32'd123456789;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    wire        imem_req_valid;
    wire        imem_req_ready;
    wire [31:0] imem_req_addr;
    reg         imem_rsp_valid = 0;
    wire        imem_rsp_ready;
    reg  [31:0] imem_rsp_rdata = 0;
    reg         imem_rsp_error = 0;

    wire        dmem_req_valid;
    wire        dmem_req_ready;
    wire        dmem_req_write;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [3:0]  dmem_req_be;
    wire        dmem_req_amo;
    wire [4:0]  dmem_req_amo_op;
    reg         dmem_rsp_valid = 0;
    wire        dmem_rsp_ready;
    reg  [31:0] dmem_rsp_rdata = 0;
    reg         dmem_rsp_error = 0;

    wire        debug_reg_ready;
    wire [63:0] debug_reg_rdata;
    wire        debug_halted;
    wire [31:0] debug_dpc;

    reg [7:0] memory [0:MEM_BYTES-1];
    string hex_path;
    string test_name;
    string rvfi_path;
    integer i;
    integer lane;
    integer cycles = 0;
    integer timeout = 5_000_000;
    integer rvfi_fd = 0;
    reg [31:0] amo_write_value;
    reg [31:0] tohost_addr = 0;
    reg reset_high = 0;
    reg irq_m_software = 0;
    reg irq_m_timer_force = 0;
    reg irq_m_external = 0;
    reg irq_s_software = 0;
    reg irq_s_timer = 0;
    reg irq_s_external = 0;
    reg [63:0] mtime = 0;
    reg [63:0] mtimecmp = {64{1'b1}};
    reg [3:0] mtime_divider = 0;
    wire mtimecmp_write = dmem_req_valid && dmem_req_ready &&
                          dmem_req_write &&
                          (dmem_req_addr == 32'h0200_4000 ||
                           dmem_req_addr == 32'h0200_4004);
    wire [63:0] mtimecmp_write_value = dmem_req_addr[2]
        ? {dmem_req_wdata, mtimecmp[31:0]}
        : {mtimecmp[63:32], dmem_req_wdata};
    wire irq_m_timer = irq_m_timer_force || mtime >= mtimecmp ||
                       (mtimecmp_write && mtime >= mtimecmp_write_value);
    reg require_os = 0;
    reg saw_supervisor = 0;
    reg saw_user = 0;
    reg saw_sv32 = 0;

    assign imem_req_ready = !imem_rsp_valid;
    assign dmem_req_ready = !dmem_rsp_valid;

    function automatic memory_range(input [31:0] addr);
        memory_range = (!reset_high && addr < MEM_BYTES) ||
                       (addr >= 32'h8000_0000 && addr < 32'h8040_0000);
    endfunction

    function automatic [31:0] memory_addr(input [31:0] addr);
        memory_addr = {10'b0, addr[21:0]};
    endfunction

    function automatic [31:0] load_word(input [31:0] addr);
        reg [31:0] mapped;
        begin
            mapped = memory_addr(addr);
            load_word = {memory[mapped + 3], memory[mapped + 2],
                         memory[mapped + 1], memory[mapped]};
        end
    endfunction

    function automatic [31:0] amo_result(
        input [4:0] op, input [31:0] old_value, input [31:0] operand);
        begin
            case (op)
                5'b00001, 5'b00011: amo_result = operand;
                5'b00000: amo_result = old_value + operand;
                5'b00100: amo_result = old_value ^ operand;
                5'b01100: amo_result = old_value & operand;
                5'b01000: amo_result = old_value | operand;
                5'b10000: amo_result = $signed(old_value) < $signed(operand)
                                         ? old_value : operand;
                5'b10100: amo_result = $signed(old_value) > $signed(operand)
                                         ? old_value : operand;
                5'b11000: amo_result = old_value < operand ? old_value : operand;
                5'b11100: amo_result = old_value > operand ? old_value : operand;
                default:  amo_result = old_value;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            imem_rsp_valid <= 0;
            imem_rsp_rdata <= 0;
            imem_rsp_error <= 0;
        end else begin
            if (imem_rsp_valid && imem_rsp_ready)
                imem_rsp_valid <= 0;
            if (imem_req_valid && imem_req_ready) begin
                imem_rsp_valid <= 1;
                imem_rsp_error <= !memory_range(imem_req_addr) ||
                                  memory_addr(imem_req_addr) + 3 >= MEM_BYTES;
                if (!memory_range(imem_req_addr) ||
                    memory_addr(imem_req_addr) + 3 >= MEM_BYTES)
                    imem_rsp_rdata <= 0;
                else if (reset_high && imem_req_addr == 0)
                    imem_rsp_rdata <= 32'h8000_02b7;
                else if (reset_high && imem_req_addr == 4)
                    imem_rsp_rdata <= 32'h0002_8067;
                else
                    imem_rsp_rdata <= load_word(imem_req_addr);
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            dmem_rsp_valid <= 0;
            dmem_rsp_rdata <= 0;
            dmem_rsp_error <= 0;
            irq_m_software <= 0;
            irq_m_timer_force <= 0;
            irq_m_external <= 0;
            irq_s_software <= 0;
            irq_s_timer <= 0;
            irq_s_external <= 0;
            mtime <= 0;
            mtimecmp <= {64{1'b1}};
            mtime_divider <= 0;
        end else begin
            mtime_divider <= mtime_divider + 1;
            if (&mtime_divider) mtime <= mtime + 1;
            if (dmem_rsp_valid && dmem_rsp_ready)
                dmem_rsp_valid <= 0;
            if (dmem_req_valid && dmem_req_ready) begin
                dmem_rsp_valid <= 1;
                dmem_rsp_rdata <= 0;
                dmem_rsp_error <= 0;

                if (dmem_req_addr == CONSOLE_ADDR && dmem_req_write) begin
                    $write("%c", dmem_req_wdata[7:0]);
                end else if (dmem_req_addr == 32'h0c00_0004 &&
                             dmem_req_write) begin
                    if (dmem_req_wdata[1]) irq_s_software <= dmem_req_wdata[31];
                    if (dmem_req_wdata[3]) irq_m_software <= dmem_req_wdata[31];
                    if (dmem_req_wdata[5]) irq_s_timer <= dmem_req_wdata[31];
                    if (dmem_req_wdata[7]) irq_m_timer_force <= dmem_req_wdata[31];
                    if (dmem_req_wdata[9]) irq_s_external <= dmem_req_wdata[31];
                    if (dmem_req_wdata[11]) irq_m_external <= dmem_req_wdata[31];
                end else if (dmem_req_addr == 32'h0200_0000) begin
                    if (dmem_req_write) irq_m_software <= dmem_req_wdata[0];
                    else dmem_rsp_rdata <= {31'b0, irq_m_software};
                end else if (dmem_req_addr == 32'h0200_4000) begin
                    if (dmem_req_write) mtimecmp[31:0] <= dmem_req_wdata;
                    else dmem_rsp_rdata <= mtimecmp[31:0];
                end else if (dmem_req_addr == 32'h0200_4004) begin
                    if (dmem_req_write) mtimecmp[63:32] <= dmem_req_wdata;
                    else dmem_rsp_rdata <= mtimecmp[63:32];
                end else if (dmem_req_addr == 32'h0200_bff8) begin
                    if (dmem_req_write) mtime[31:0] <= dmem_req_wdata;
                    else dmem_rsp_rdata <= mtime[31:0];
                end else if (dmem_req_addr == 32'h0200_bffc) begin
                    if (dmem_req_write) mtime[63:32] <= dmem_req_wdata;
                    else dmem_rsp_rdata <= mtime[63:32];
                end else if (tohost_addr != 0 && dmem_req_write &&
                             dmem_req_addr == tohost_addr + 4 &&
                             dmem_req_wdata == 32'h0101_0000) begin
                    $write("%c", memory[memory_addr(tohost_addr)]);
                end else if (tohost_addr != 0 &&
                             (dmem_req_addr == tohost_addr ||
                              dmem_req_addr == memory_addr(tohost_addr)) &&
                             dmem_req_write &&
                             (dmem_req_wdata == 1 || dmem_req_wdata == 3)) begin
                    if (dmem_req_wdata == 1) begin
                        $display("PASS: ACT4 %s (%0d cycles)", test_name, cycles);
                        $finish;
                    end else begin
                        $fatal(1, "FAIL: ACT4 %s tohost=%08x",
                               test_name, dmem_req_wdata);
                    end
                end else if (dmem_req_addr == HALT_ADDR && dmem_req_write) begin
                    if (dmem_req_wdata == PASS_VALUE) begin
                        if (require_os && !(saw_supervisor && saw_user && saw_sv32))
                            $fatal(1, "Sv32 OS coverage missing: S=%0d U=%0d satp=%0d",
                                   saw_supervisor, saw_user, saw_sv32);
                        $display("PASS: ACT4 %s (%0d cycles)", test_name, cycles);
                        $finish;
                    end else begin
                        $fatal(1, "FAIL: ACT4 %s code=%08x",
                               test_name, dmem_req_wdata);
                    end
                end else if (dmem_req_addr >= 32'h0200_0000 &&
                             dmem_req_addr < 32'h1200_0000) begin
                    dmem_rsp_rdata <= 0;
                end else if (memory_range(dmem_req_addr) &&
                             memory_addr(dmem_req_addr) + 3 < MEM_BYTES) begin
                    dmem_rsp_rdata <= load_word({dmem_req_addr[31:2], 2'b00});
                    if (dmem_req_amo && dmem_req_amo_op != 5'b00010) begin
                        amo_write_value = amo_result(
                            dmem_req_amo_op,
                            load_word({dmem_req_addr[31:2], 2'b00}),
                            dmem_req_wdata);
                        for (lane = 0; lane < 4; lane = lane + 1)
                            memory[memory_addr({dmem_req_addr[31:2], 2'b00}) + lane]
                                <= amo_write_value[lane*8 +: 8];
                    end else if (dmem_req_write)
                        for (lane = 0; lane < 4; lane = lane + 1)
                            if (dmem_req_be[lane])
                                memory[memory_addr({dmem_req_addr[31:2], 2'b00}) + lane]
                                    <= dmem_req_wdata[lane*8 +: 8];
                end else begin
                    dmem_rsp_error <= 1;
                end
            end
        end
    end

`ifdef RISCV_FORMAL
`ifdef HYBRID
    localparam RETIRE_LANES=4;
`else
    localparam RETIRE_LANES=1;
`endif
    wire [RETIRE_LANES-1:0] rvfi_valid, rvfi_trap, rvfi_halt, rvfi_intr;
    wire [RETIRE_LANES-1:0] [63:0] rvfi_order;
    wire [RETIRE_LANES-1:0] [31:0] rvfi_insn, rvfi_rs1_rdata, rvfi_rs2_rdata;
    wire [RETIRE_LANES-1:0] [31:0] rvfi_rd_wdata, rvfi_pc_rdata, rvfi_pc_wdata;
    wire [RETIRE_LANES-1:0] [31:0] rvfi_mem_addr, rvfi_mem_rdata, rvfi_mem_wdata;
    wire [RETIRE_LANES-1:0] [4:0] rvfi_rs1_addr, rvfi_rs2_addr, rvfi_rd_addr;
    wire [RETIRE_LANES-1:0] [3:0] rvfi_mem_rmask, rvfi_mem_wmask;
    wire [RETIRE_LANES-1:0] [1:0] rvfi_mode, rvfi_ixl;
    wire [RETIRE_LANES-1:0] rvfi_frd_valid, rvfi_csr_valid;
    wire [RETIRE_LANES-1:0] [4:0] rvfi_frd_addr;
    wire [RETIRE_LANES-1:0] [63:0] rvfi_frd_wdata;
    wire [RETIRE_LANES-1:0] [11:0] rvfi_csr_addr;
    wire [RETIRE_LANES-1:0] [31:0] rvfi_csr_wdata;
    reg [63:0] expected_order = 0;

    always @(posedge clk) begin
        if (!rst_n) expected_order = 0;
        else for(int lane=0;lane<RETIRE_LANES;lane++) if(rvfi_valid[lane]) begin
            if (rvfi_mode[lane] == 2'b01) saw_supervisor <= 1;
            if (rvfi_mode[lane] == 2'b00) saw_user <= 1;
            if (rvfi_csr_valid[lane] && rvfi_csr_addr[lane] == 12'h180 && rvfi_csr_wdata[lane][31])
                saw_sv32 <= 1;
            if (rvfi_order[lane] != expected_order)
                $fatal(1, "RVFI order discontinuity: got %0d expected %0d",
                       rvfi_order[lane], expected_order);
            expected_order = expected_order + 1;
            if (rvfi_fd)
                $fdisplay(rvfi_fd,
                          "%0d %0d %08x %08x %0d %0d %0d %08x %08x %01x %01x %08x %08x %0d %0d %016x %0d %03x %08x",
                          rvfi_order[lane], rvfi_mode[lane], rvfi_pc_rdata[lane], rvfi_insn[lane],
                          rvfi_trap[lane], rvfi_intr[lane], rvfi_rd_addr[lane], rvfi_rd_wdata[lane],
                          rvfi_mem_addr[lane], rvfi_mem_rmask[lane], rvfi_mem_wmask[lane],
                          rvfi_mem_rdata[lane], rvfi_mem_wdata[lane],
                          rvfi_frd_valid[lane], rvfi_frd_addr[lane], rvfi_frd_wdata[lane],
                          rvfi_csr_valid[lane], rvfi_csr_addr[lane], rvfi_csr_wdata[lane]);
        end
    end
`endif

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (cycles >= timeout)
                $fatal(1, "TIMEOUT: ACT4 %s after %0d cycles", test_name, cycles);
        end
    end

`ifdef HYBRID
    hybrid_top dut (
`else
    top dut (
`endif
        .clk(clk),
        .rst_n(rst_n),
        .irq_m_software(irq_m_software),
        .irq_m_timer(irq_m_timer),
        .irq_m_external(irq_m_external),
        .irq_s_software(irq_s_software),
        .irq_s_timer(irq_s_timer),
        .irq_s_external(irq_s_external),
        .nmi(1'b0),
        .mtime(mtime),
        .debug_req(1'b0),
        .debug_resume(1'b0),
        .debug_reg_valid(1'b0),
        .debug_reg_write(1'b0),
        .debug_reg_addr(6'b0),
        .debug_reg_wdata(64'b0),
        .debug_reg_ready(debug_reg_ready),
        .debug_reg_rdata(debug_reg_rdata),
        .debug_halted(debug_halted),
        .debug_dpc(debug_dpc),
        .debug_dpc_write(1'b0), .debug_dpc_wdata(32'b0),
        .debug_step(1'b0), .debug_privilege(),
        .imem_req_valid(imem_req_valid),
        .imem_req_ready(imem_req_ready),
        .imem_req_addr(imem_req_addr),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_ready(imem_rsp_ready),
        .imem_rsp_rdata(imem_rsp_rdata),
        .imem_rsp_error(imem_rsp_error),
        .dmem_req_valid(dmem_req_valid),
        .dmem_req_ready(dmem_req_ready),
        .dmem_req_write(dmem_req_write),
        .dmem_req_addr(dmem_req_addr),
        .dmem_req_wdata(dmem_req_wdata),
        .dmem_req_be(dmem_req_be),
        .dmem_req_amo(dmem_req_amo),
        .dmem_req_amo_op(dmem_req_amo_op),
        .reservation_invalidate(1'b0),
        .dmem_rsp_valid(dmem_rsp_valid),
        .dmem_rsp_ready(dmem_rsp_ready),
        .dmem_rsp_rdata(dmem_rsp_rdata),
        .dmem_rsp_error(dmem_rsp_error)
`ifdef RISCV_FORMAL
        , .rvfi_valid(rvfi_valid), .rvfi_order(rvfi_order),
        .rvfi_insn(rvfi_insn), .rvfi_trap(rvfi_trap), .rvfi_halt(rvfi_halt),
        .rvfi_intr(rvfi_intr), .rvfi_mode(rvfi_mode), .rvfi_ixl(rvfi_ixl),
        .rvfi_rs1_addr(rvfi_rs1_addr), .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata), .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr), .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata), .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_mem_addr(rvfi_mem_addr), .rvfi_mem_rmask(rvfi_mem_rmask),
        .rvfi_mem_wmask(rvfi_mem_wmask), .rvfi_mem_rdata(rvfi_mem_rdata),
        .rvfi_mem_wdata(rvfi_mem_wdata),
        .rvfi_frd_valid(rvfi_frd_valid), .rvfi_frd_addr(rvfi_frd_addr),
        .rvfi_frd_wdata(rvfi_frd_wdata),
        .rvfi_csr_valid(rvfi_csr_valid), .rvfi_csr_addr(rvfi_csr_addr),
        .rvfi_csr_wdata(rvfi_csr_wdata)
`endif
    );

    initial begin
        if (!$value$plusargs("hex=%s", hex_path))
            $fatal(1, "missing +hex=<file>");
        if (!$value$plusargs("test=%s", test_name))
            test_name = hex_path;
        void'($value$plusargs("tohost=%h", tohost_addr));
        reset_high = $test$plusargs("reset_high");
        require_os = $test$plusargs("require_os");
        void'($value$plusargs("timeout=%d", timeout));
`ifdef RISCV_FORMAL
        if ($value$plusargs("rvfi=%s", rvfi_path)) begin
            rvfi_fd = $fopen(rvfi_path, "w");
            if (!rvfi_fd) $fatal(1, "cannot open RVFI trace: %s", rvfi_path);
        end
`endif

        for (i = 0; i < MEM_BYTES; i = i + 1)
            memory[i] = 0;
        for (i = 0; i < 128; i = i + 4) begin
            memory[i] = 8'h13;
            memory[i + 1] = 0;
            memory[i + 2] = 0;
            memory[i + 3] = 0;
        end
        $readmemh(hex_path, memory);

        repeat (5) @(posedge clk);
        @(negedge clk);
        if (reset_high) begin
`ifdef HYBRID
            dut.pc = 32'h8000_0000;
            dut.fetch_cursor = 32'h8000_0000;
`else
            dut.u_fetch.u_pc.pc_state = 32'h8000_0000;
`endif
        end
        rst_n = 1;
    end
endmodule
