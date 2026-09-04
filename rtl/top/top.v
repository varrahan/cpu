module top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq_m_software,
    input  wire        irq_m_timer,
    input  wire        irq_m_external,
    input  wire        irq_s_software,
    input  wire        irq_s_timer,
    input  wire        irq_s_external,
    input  wire        nmi,
    input  wire [63:0] mtime,
    input  wire        debug_req,
    input  wire        debug_resume,
    input  wire        debug_reg_valid,
    input  wire        debug_reg_write,
    input  wire [5:0]  debug_reg_addr,
    input  wire [63:0] debug_reg_wdata,
    output wire        debug_reg_ready,
    output wire [63:0] debug_reg_rdata,
    output wire        debug_halted,
    output wire [31:0] debug_dpc,
    input  wire        debug_dpc_write,
    input  wire [31:0] debug_dpc_wdata,
    input  wire        debug_step,
    output wire [1:0]  debug_privilege,

    output wire        imem_req_valid,
    input  wire        imem_req_ready,
    output wire [31:0] imem_req_addr,
    input  wire        imem_rsp_valid,
    output wire        imem_rsp_ready,
    input  wire [31:0] imem_rsp_rdata,
    input  wire        imem_rsp_error,

    output wire        dmem_req_valid,
    input  wire        dmem_req_ready,
    output wire        dmem_req_write,
    output wire [31:0] dmem_req_addr,
    output wire [31:0] dmem_req_wdata,
    output wire [3:0]  dmem_req_be,
    output wire        dmem_req_amo,
    output wire [4:0]  dmem_req_amo_op,
    input  wire        reservation_invalidate,
    input  wire        dmem_rsp_valid,
    output wire        dmem_rsp_ready,
    input  wire [31:0] dmem_rsp_rdata,
    input  wire        dmem_rsp_error
`ifdef RISCV_FORMAL
    ,
    output reg         rvfi_valid,
    output reg  [63:0] rvfi_order,
    output reg  [31:0] rvfi_insn,
    output reg         rvfi_trap,
    output reg         rvfi_halt,
    output reg         rvfi_intr,
    output reg  [1:0]  rvfi_mode,
    output wire [1:0]  rvfi_ixl,
    output reg  [4:0]  rvfi_rs1_addr,
    output reg  [4:0]  rvfi_rs2_addr,
    output reg  [31:0] rvfi_rs1_rdata,
    output reg  [31:0] rvfi_rs2_rdata,
    output reg  [4:0]  rvfi_rd_addr,
    output reg  [31:0] rvfi_rd_wdata,
    output reg  [31:0] rvfi_pc_rdata,
    output reg  [31:0] rvfi_pc_wdata,
    output reg  [31:0] rvfi_mem_addr,
    output reg  [3:0]  rvfi_mem_rmask,
    output reg  [3:0]  rvfi_mem_wmask,
    output reg  [31:0] rvfi_mem_rdata,
    output reg  [31:0] rvfi_mem_wdata,
    output reg         rvfi_frd_valid,
    output reg  [4:0]  rvfi_frd_addr,
    output reg  [63:0] rvfi_frd_wdata,
    output reg         rvfi_csr_valid,
    output reg  [11:0] rvfi_csr_addr,
    output reg  [31:0] rvfi_csr_wdata
`endif
);
    localparam [31:0] CAUSE_INST_MISALIGNED = 0;
    localparam [31:0] CAUSE_INST_ACCESS     = 1;
    localparam [31:0] CAUSE_ILLEGAL         = 2;
    localparam [31:0] CAUSE_BREAKPOINT      = 3;
    localparam [31:0] CAUSE_LOAD_MISALIGNED = 4;
    localparam [31:0] CAUSE_LOAD_ACCESS     = 5;
    localparam [31:0] CAUSE_STORE_MISALIGNED = 6;
    localparam [31:0] CAUSE_STORE_ACCESS    = 7;
    localparam [31:0] CAUSE_ECALL_U         = 8;
    localparam [31:0] CAUSE_ECALL_S         = 9;
    localparam [31:0] CAUSE_ECALL_M         = 11;
    localparam [31:0] CAUSE_INST_PAGE       = 12;
    localparam [31:0] CAUSE_LOAD_PAGE       = 13;
    localparam [31:0] CAUSE_STORE_PAGE      = 15;

    wire redirect_fire;
    wire retirement_redirect_fire;
    wire ex_reset = !rst_n || retirement_redirect_fire;
    wire id_reset = !rst_n || redirect_fire;
    wire [31:0] redirect_pc;
    wire mem_hold;
    wire execute_hold;
    wire dmmu_hold;
    wire stall_haz;
    wire stall_fp_haz;
    wire stall_csr;
    wire [1:0] csr_privilege;
    wire [1:0] csr_data_privilege;
    wire [31:0] csr_pmpcfg0, csr_pmpaddr0, csr_pmpaddr1;
    wire [31:0] csr_pmpaddr2, csr_pmpaddr3;
    wire [31:0] csr_satp;
    wire csr_mstatus_sum, csr_mstatus_mxr;
    wire sfence_take;
    wire debug_enter, debug_resume_fire;
    reg wfi_sleep;
    reg [31:0] wfi_resume_pc;
    wire wfi_wake, wfi_wake_trap, wfi_wake_resume;

    (* ASYNC_REG = "TRUE" *) reg [1:0] irq_m_software_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] irq_m_timer_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] irq_m_external_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] irq_s_software_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] irq_s_timer_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] irq_s_external_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] nmi_sync;

    always @(posedge clk) begin
        if (!rst_n) begin
            irq_m_software_sync <= 0; irq_m_timer_sync <= 0;
            irq_m_external_sync <= 0; irq_s_software_sync <= 0;
            irq_s_timer_sync <= 0; irq_s_external_sync <= 0; nmi_sync <= 0;
        end else begin
            irq_m_software_sync <= {irq_m_software_sync[0], irq_m_software};
            irq_m_timer_sync <= {irq_m_timer_sync[0], irq_m_timer};
            irq_m_external_sync <= {irq_m_external_sync[0], irq_m_external};
            irq_s_software_sync <= {irq_s_software_sync[0], irq_s_software};
            irq_s_timer_sync <= {irq_s_timer_sync[0], irq_s_timer};
            irq_s_external_sync <= {irq_s_external_sync[0], irq_s_external};
            nmi_sync <= {nmi_sync[0], nmi};
        end
    end

    // Fetch and instruction cache
    wire [31:0] if_pc;
    wire [31:0] if_raw_instr;
    wire [2:0]  if_instr_length;
    wire        fetch_issue_window;
    wire [31:0] fetch_addr_unused;
    wire        if_pred_taken;
    wire [31:0] icache_rdata;
    wire [15:0] icache_rdata_next;
    wire        icache_current_ready;
    wire        icache_ready;
    wire        icache_error;
    wire        icache_cancel;
    wire        icache_need_next_raw = if_pc[1] &&
                                        icache_rdata[17:16] == 2'b11;
    wire        icache_invalidate;
    wire        if_pmp_allow_main, if_pmp_allow_next, imem_fill_allow;

    wire immu_ready, immu_page_fault, immu_access_fault;
    wire [31:0] immu_paddr;
    wire immu_next_ready, immu_next_page_fault, immu_next_access_fault;
    wire [31:0] immu_next_paddr;
    wire boundary_instruction = if_pc[11:0] == 12'hffe;
    wire boundary_translate = boundary_instruction && icache_current_ready &&
                              icache_need_next_raw;
    wire if_need_next_pmp = icache_current_ready && icache_need_next_raw;
    wire [31:0] if_next_pmp_addr = boundary_translate
                                   ? immu_next_paddr : immu_paddr + 2;
    wire instruction_translation_fault = immu_page_fault || immu_access_fault ||
        (boundary_translate &&
         (immu_next_page_fault || immu_next_access_fault));
    wire instruction_page_fault = immu_page_fault ||
                                  (boundary_translate && immu_next_page_fault);
    wire instruction_translation_ready = immu_ready &&
        (!boundary_translate || immu_next_ready);
    wire [31:2] icache_next_paddr = boundary_instruction
                                    ? immu_next_paddr[31:2]
                                    : immu_paddr[31:2] + 1;
    wire icache_need_next = icache_need_next_raw &&
                            (!boundary_instruction || immu_next_ready);
    wire icache_cpu_valid = immu_ready && !immu_page_fault &&
                            !immu_access_fault;
    wire instruction_pmp_fault = instruction_translation_ready &&
        !instruction_translation_fault &&
        (!if_pmp_allow_main ||
         (if_need_next_pmp && !if_pmp_allow_next));
    wire if_fetch_ready = fetch_issue_window && instruction_translation_ready &&
        (instruction_translation_fault || instruction_pmp_fault ||
         icache_ready);
    wire stall_fetch = debug_halted || wfi_sleep || mem_hold || execute_hold ||
                       stall_haz || stall_fp_haz || stall_csr ||
                       !if_fetch_ready;
    wire im0_req_valid, im0_req_ready, im0_req_write, im0_req_amo;
    wire [31:0] im0_req_addr, im0_req_wdata, im0_rsp_rdata;
    wire [3:0] im0_req_be; wire [4:0] im0_req_amo_op;
    wire im0_rsp_valid, im0_rsp_ready, im0_rsp_error, im0_req_allow;
    sv32_mmu u_immu (
        .clk(clk), .rst_n(rst_n), .flush(sfence_take),
        .req_valid(1'b1), .vaddr(if_pc), .privilege(csr_privilege),
        .access_read(1'b0), .access_write(1'b0), .access_execute(1'b1),
        .mstatus_sum(csr_mstatus_sum), .mstatus_mxr(csr_mstatus_mxr),
        .satp(csr_satp), .resp_ready(immu_ready), .paddr(immu_paddr),
        .page_fault(immu_page_fault), .access_fault(immu_access_fault),
        .mem_req_valid(im0_req_valid), .mem_req_ready(im0_req_ready),
        .mem_req_allow(im0_req_allow), .mem_req_write(im0_req_write),
        .mem_req_addr(im0_req_addr), .mem_req_wdata(im0_req_wdata),
        .mem_req_be(im0_req_be), .mem_req_amo(im0_req_amo),
        .mem_req_amo_op(im0_req_amo_op), .mem_rsp_valid(im0_rsp_valid),
        .mem_rsp_ready(im0_rsp_ready), .mem_rsp_rdata(im0_rsp_rdata),
        .mem_rsp_error(im0_rsp_error)
    );

    wire im1_req_valid, im1_req_ready, im1_req_write, im1_req_amo;
    wire [31:0] im1_req_addr, im1_req_wdata, im1_rsp_rdata;
    wire [3:0] im1_req_be; wire [4:0] im1_req_amo_op;
    wire im1_rsp_valid, im1_rsp_ready, im1_rsp_error, im1_req_allow;
    sv32_mmu u_immu_boundary (
        .clk(clk), .rst_n(rst_n), .flush(sfence_take),
        .req_valid(boundary_translate), .vaddr(if_pc + 2),
        .privilege(csr_privilege), .access_read(1'b0), .access_write(1'b0),
        .access_execute(1'b1), .mstatus_sum(csr_mstatus_sum),
        .mstatus_mxr(csr_mstatus_mxr), .satp(csr_satp),
        .resp_ready(immu_next_ready), .paddr(immu_next_paddr),
        .page_fault(immu_next_page_fault),
        .access_fault(immu_next_access_fault),
        .mem_req_valid(im1_req_valid), .mem_req_ready(im1_req_ready),
        .mem_req_allow(im1_req_allow), .mem_req_write(im1_req_write),
        .mem_req_addr(im1_req_addr), .mem_req_wdata(im1_req_wdata),
        .mem_req_be(im1_req_be), .mem_req_amo(im1_req_amo),
        .mem_req_amo_op(im1_req_amo_op), .mem_rsp_valid(im1_rsp_valid),
        .mem_rsp_ready(im1_rsp_ready), .mem_rsp_rdata(im1_rsp_rdata),
        .mem_rsp_error(im1_rsp_error)
    );

    pmp_checker u_if_pmp (
        .addr(immu_paddr),
        .size(4'd2),
        .privilege(csr_privilege), .access_read(1'b0),
        .access_write(1'b0), .access_execute(1'b1),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(if_pmp_allow_main)
    );

    pmp_checker u_if_next_pmp (
        .addr(if_next_pmp_addr), .size(4'd2),
        .privilege(csr_privilege), .access_read(1'b0),
        .access_write(1'b0), .access_execute(1'b1),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(if_pmp_allow_next)
    );

    pmp_checker u_if_fill_pmp (
        .addr(imem_req_addr), .size(4'd4), .privilege(csr_privilege),
        .access_read(1'b0), .access_write(1'b0), .access_execute(1'b1),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(imem_fill_allow)
    );

    icache u_icache (
        .clk           (clk),
        .rst_n         (rst_n),
        .cancel        (icache_cancel),
        .invalidate    (icache_invalidate),
        .cpu_valid     (icache_cpu_valid),
        .cpu_addr      (immu_paddr[31:2]),
        .cpu_next_addr (icache_next_paddr),
        .cpu_need_next (icache_need_next),
        .cpu_rdata     (icache_rdata),
        .cpu_rdata_next(icache_rdata_next),
        .cpu_current_ready(icache_current_ready),
        .cpu_ready     (icache_ready),
        .cpu_error     (icache_error),
        .mem_req_valid (imem_req_valid),
        .mem_req_allow (imem_fill_allow),
        .mem_req_ready (imem_req_ready),
        .mem_req_addr  (imem_req_addr),
        .mem_rsp_valid (imem_rsp_valid),
        .mem_rsp_ready (imem_rsp_ready),
        .mem_rsp_rdata (imem_rsp_rdata),
        .mem_rsp_error (imem_rsp_error)
    );

    fetch_stage u_fetch (
        .clk         (clk),
        .rst_n       (rst_n),
        .stall       (stall_fetch),
        .flush       (redirect_fire),
        .redirect_pc (redirect_pc),
        .pc_out      (if_pc),
        .raw_instr_out(if_raw_instr),
        .instr_length(if_instr_length),
        .issue_window(fetch_issue_window),
        .imem_addr   (fetch_addr_unused),
        .imem_data   (icache_rdata),
        .imem_data_next(icache_rdata_next),
        .pred_taken  (if_pred_taken)
    );

    // IF/ID pipeline state
    reg        id_valid;
    reg [31:0] id_pc;
    reg [31:0] id_encoded_instr;
    reg [2:0]  id_instr_length;
    reg        id_pred_taken;
    reg        id_fetch_exception;
    reg [31:0] id_fetch_cause;
    reg [31:0] id_fetch_tval;

    always @(posedge clk) begin
        if (id_reset) begin
            id_valid <= 0;
        end else if (debug_halted || wfi_sleep) begin
            id_valid <= 0;
        end else if (mem_hold || execute_hold || stall_haz || stall_fp_haz ||
                     stall_csr) begin
            // Hold the instruction feeding a blocked decode stage.
        end else begin
            id_valid <= if_fetch_ready;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            id_pc <= 0;
            id_encoded_instr <= 0;
            id_instr_length <= 4;
            id_pred_taken <= 0;
            id_fetch_exception <= 0;
            id_fetch_cause <= 0;
            id_fetch_tval <= 0;
        end else if (!debug_halted && !wfi_sleep && !mem_hold && !execute_hold &&
            !stall_haz && !stall_fp_haz && !stall_csr) begin
            id_pc <= if_pc;
            id_encoded_instr <= if_raw_instr;
            id_instr_length <= if_instr_length;
            id_pred_taken <= if_pred_taken;
            id_fetch_exception <= icache_error ||
                                  instruction_translation_fault ||
                                  instruction_pmp_fault;
            id_fetch_cause <= instruction_page_fault
                              ? CAUSE_INST_PAGE : CAUSE_INST_ACCESS;
            id_fetch_tval <= ((boundary_translate &&
                               (immu_next_page_fault ||
                                immu_next_access_fault)) ||
                              (if_need_next_pmp && !if_pmp_allow_next))
                             ? if_pc + 2 : if_pc;
        end
    end

    // Decode
    wire [31:0] id_raw_instr = id_encoded_instr;
    wire [31:0] id_decompressed_instr;
    wire id_decompression_illegal;
    wire [31:0] id_instr = id_instr_length == 2
                           ? id_decompressed_instr : id_encoded_instr;
    wire id_instr_illegal = id_instr_length == 2 &&
                            id_decompression_illegal;
    rvc_decompressor u_id_rvc (
        .compressed(id_encoded_instr[15:0]),
        .instruction(id_decompressed_instr),
        .illegal(id_decompression_illegal)
    );

    wire [4:0]  id_rs1_addr, id_rs2_addr, id_rd;
    wire [31:0] id_rs1_data, id_rs2_data, id_imm;
    wire [3:0]  id_alu_op;
    wire [2:0]  id_funct3;
    wire        id_alu_src, id_mem_read, id_mem_write, id_reg_write;
    wire        id_branch, id_jal, id_jalr, id_lui, id_auipc;
    wire        id_uses_rs1, id_uses_rs2, id_illegal, id_fence;
    wire        id_fence_i, id_muldiv, id_amo;
    wire [2:0]  id_muldiv_op;
    wire [4:0]  id_amo_op;
    wire        id_fp_compute, id_fp_load, id_fp_store;
    wire        id_fp_uses_rs1, id_fp_uses_rs2, id_fp_uses_rs3;
    wire        id_csr_en, id_csr_imm, id_ecall, id_ebreak, id_mret, id_sret;
    wire        id_sfence_vma, id_wfi;
    wire [1:0]  id_csr_cmd;
    wire        id_serializing_noop = id_fence || id_fence_i ||
                                      id_sfence_vma || id_wfi;

    decoder u_dec (
        .instr      (id_instr),
        .rs1        (id_rs1_addr),
        .rs2        (id_rs2_addr),
        .rd         (id_rd),
        .imm        (id_imm),
        .alu_op     (id_alu_op),
        .alu_src    (id_alu_src),
        .mem_read   (id_mem_read),
        .mem_write  (id_mem_write),
        .reg_write  (id_reg_write),
        .branch     (id_branch),
        .jal        (id_jal),
        .jalr       (id_jalr),
        .funct3     (id_funct3),
        .lui        (id_lui),
        .auipc      (id_auipc),
        .uses_rs1   (id_uses_rs1),
        .uses_rs2   (id_uses_rs2),
        .illegal    (id_illegal),
        .fence      (id_fence),
        .fence_i    (id_fence_i),
        .muldiv     (id_muldiv),
        .muldiv_op  (id_muldiv_op),
        .amo        (id_amo),
        .amo_op     (id_amo_op),
        .fp_compute (id_fp_compute),
        .fp_load    (id_fp_load),
        .fp_store   (id_fp_store),
        .fp_uses_rs1(id_fp_uses_rs1),
        .fp_uses_rs2(id_fp_uses_rs2),
        .fp_uses_rs3(id_fp_uses_rs3),
        .csr_en     (id_csr_en),
        .csr_cmd    (id_csr_cmd),
        .csr_imm    (id_csr_imm),
        .ecall      (id_ecall),
        .ebreak     (id_ebreak),
        .mret       (id_mret),
        .sret       (id_sret),
        .sfence_vma (id_sfence_vma),
        .wfi        (id_wfi)
    );

    reg        wb_valid;
    reg [4:0]  wb_rd;
    reg [31:0] wb_data;
    reg        wb_reg_write;
    wire       wb_reg_write_effective = wb_valid && wb_reg_write && wb_rd != 0;
    reg        wb_fp_write;
    reg [4:0]  wb_fp_rd;
    reg [63:0] wb_fp_data;
    wire       wb_fp_write_effective = wb_valid && wb_fp_write;
    wire [31:0] debug_int_rdata;
    wire [63:0] debug_fp_rdata;
    wire debug_int_we = debug_halted && debug_reg_valid && debug_reg_write &&
                        !debug_reg_addr[5];
    wire debug_fp_we = debug_halted && debug_reg_valid && debug_reg_write &&
                       debug_reg_addr[5];
    wire debug_int_re = debug_halted && !debug_reg_addr[5];
    wire debug_fp_re = debug_halted && debug_reg_addr[5];
    assign debug_reg_ready = debug_halted && debug_reg_valid;
    assign debug_reg_rdata = debug_reg_addr[5]
                             ? debug_fp_rdata : {32'b0, debug_int_rdata};
    assign debug_privilege = csr_privilege;

    regfile u_rf (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_rs1_addr),
        .rs2_addr (id_rs2_addr),
        .rd_addr  (wb_rd),
        .rd_data  (wb_data),
        .wr_en    (wb_reg_write_effective),
        .debug_addr(debug_reg_addr[4:0]),
        .debug_wdata(debug_reg_wdata[31:0]),
        .debug_re(debug_int_re),
        .debug_we(debug_int_we),
        .debug_rdata(debug_int_rdata),
        .rs1_data (id_rs1_data),
        .rs2_data (id_rs2_data)
    );

    wire [63:0] id_frs1_data, id_frs2_data, id_frs3_data;
    fp_regfile u_fp_rf (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (id_instr[19:15]),
        .rs2_addr (id_instr[24:20]),
        .rs3_addr (id_instr[31:27]),
        .rd_addr  (wb_fp_rd),
        .rd_data  (wb_fp_data),
        .wr_en    (wb_fp_write_effective),
        .debug_addr(debug_reg_addr[4:0]),
        .debug_wdata(debug_reg_wdata),
        .debug_re(debug_fp_re),
        .debug_we(debug_fp_we),
        .debug_rdata(debug_fp_rdata),
        .rs1_data (id_frs1_data),
        .rs2_data (id_frs2_data),
        .rs3_data (id_frs3_data)
    );

    // ID/EX pipeline state
    reg        ex_valid;
    reg [31:0] ex_pc;
    reg [31:0] ex_instr;
    reg [31:0] ex_raw_instr;
    reg [2:0]  ex_instr_length;
    reg        ex_pred_taken;
    reg [31:0] ex_rs1_data, ex_rs2_data, ex_imm;
    reg [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd;
    reg [3:0]  ex_alu_op;
    reg [2:0]  ex_funct3;
    reg        ex_alu_src, ex_mem_read, ex_mem_write, ex_reg_write;
    reg        ex_branch, ex_jal, ex_jalr, ex_lui, ex_auipc;
    reg        ex_csr_en, ex_csr_imm, ex_mret, ex_sret, ex_sfence_vma;
    reg        ex_wfi;
    reg        ex_fence_i;
    reg        ex_muldiv;
    reg [2:0]  ex_muldiv_op;
    reg        ex_amo;
    reg [4:0]  ex_amo_op;
    reg        ex_fp_compute, ex_fp_load, ex_fp_store;
    reg [63:0] ex_frs1_data, ex_frs2_data, ex_frs3_data;
    reg        ex_operands_latched;
    reg [1:0]  ex_csr_cmd;
    reg        ex_exception;
    reg [31:0] ex_exception_cause, ex_exception_tval;
`ifdef RISCV_FORMAL
    reg [4:0] ex_trace_rs1_addr, ex_trace_rs2_addr;
`endif
    wire flush_id_ex_haz;

    hazard_unit u_haz (
        .id_rs1      (id_rs1_addr),
        .id_rs2      (id_rs2_addr),
        .id_uses_rs1 (id_valid && id_uses_rs1),
        .id_uses_rs2 (id_valid && id_uses_rs2),
        .ex_rd       (ex_rd),
        .ex_mem_read (ex_valid && (ex_mem_read || ex_amo)),
        .stall       (stall_haz),
        .flush_id_ex (flush_id_ex_haz)
    );

    assign stall_fp_haz = id_valid && ex_valid && ex_fp_load &&
                           ((id_fp_uses_rs1 && id_instr[19:15] == ex_rd) ||
                            (id_fp_uses_rs2 && id_instr[24:20] == ex_rd) ||
                            (id_fp_uses_rs3 && id_instr[31:27] == ex_rd));
    assign stall_csr = (ex_valid && ex_csr_en) ||
                       (mem_valid && mem_csr_en);

    always @(posedge clk) begin
        if (ex_reset) begin
            ex_valid <= 0;
            ex_exception <= 0;
        end else if (branch_mispredict_ex) begin
            ex_valid <= 0;
            ex_exception <= 0;
        end else if (debug_halted || wfi_sleep) begin
            ex_valid <= 0;
            ex_exception <= 0;
        end else if (mem_hold || execute_hold) begin
        end else if (flush_id_ex_haz || stall_fp_haz || stall_csr) begin
            ex_valid <= 0;
            ex_exception <= 0;
        end else begin
            ex_valid      <= id_valid;
            ex_exception <= id_valid &&
                            (id_fetch_exception || id_instr_illegal || id_illegal ||
                             id_ebreak || id_ecall);
        end
    end

    always @(posedge clk) begin
        if (!rst_n)
            ex_operands_latched <= 0;
        else if ((mem_hold || execute_hold) && !ex_operands_latched)
            ex_operands_latched <= 1;
        else if (!mem_hold && !execute_hold)
            ex_operands_latched <= 0;
    end

    // Payload is irrelevant while ex_valid is clear, so redirects only clear
    // validity and do not sit on every wide EX-register data path.
    always @(posedge clk) begin
        if (!rst_n) begin
            ex_rs1_data <= 0;
            ex_rs2_data <= 0;
            ex_frs1_data <= 0;
            ex_frs2_data <= 0;
            ex_frs3_data <= 0;
        end else if ((mem_hold || execute_hold) && !ex_operands_latched) begin
            ex_rs1_data <= fwd_rs1;
            ex_rs2_data <= fwd_rs2;
            ex_frs1_data <= fwd_frs1;
            ex_frs2_data <= fwd_frs2;
            ex_frs3_data <= fwd_frs3;
        end else if (!mem_hold && !execute_hold) begin
            ex_rs1_data <= id_rs1_data;
            ex_rs2_data <= id_rs2_data;
            ex_frs1_data <= id_frs1_data;
            ex_frs2_data <= id_frs2_data;
            ex_frs3_data <= id_frs3_data;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ex_pc <= 0;
            ex_instr <= 0;
            ex_raw_instr <= 0;
            ex_instr_length <= 4;
            ex_pred_taken <= 0;
            ex_imm <= 0;
            ex_rs1_addr <= 0;
            ex_rs2_addr <= 0;
            ex_rd <= 0;
            ex_alu_op <= 0;
            ex_funct3 <= 0;
            ex_alu_src <= 0;
            ex_mem_read <= 0;
            ex_mem_write <= 0;
            ex_reg_write <= 0;
            ex_branch <= 0;
            ex_jal <= 0;
            ex_jalr <= 0;
            ex_lui <= 0;
            ex_auipc <= 0;
            ex_csr_en <= 0;
            ex_csr_cmd <= 0;
            ex_csr_imm <= 0;
            ex_mret <= 0;
            ex_sret <= 0;
            ex_sfence_vma <= 0;
            ex_wfi <= 0;
            ex_fence_i <= 0;
            ex_muldiv <= 0;
            ex_muldiv_op <= 0;
            ex_amo <= 0;
            ex_amo_op <= 0;
            ex_fp_compute <= 0;
            ex_fp_load <= 0;
            ex_fp_store <= 0;
            ex_exception_cause <= 0;
            ex_exception_tval <= 0;
`ifdef RISCV_FORMAL
            ex_trace_rs1_addr <= 0;
            ex_trace_rs2_addr <= 0;
`endif
        end else if (!mem_hold && !execute_hold) begin
            ex_pc         <= id_pc;
            ex_instr      <= id_instr;
            ex_raw_instr  <= id_raw_instr;
            ex_instr_length <= id_instr_length;
            ex_pred_taken <= id_pred_taken;
            ex_imm        <= id_imm;
            ex_rs1_addr   <= id_rs1_addr;
            ex_rs2_addr   <= id_rs2_addr;
            ex_rd         <= id_rd;
            ex_alu_op     <= id_alu_op;
            ex_funct3     <= id_funct3;
            ex_alu_src    <= id_alu_src;
            ex_mem_read   <= id_mem_read;
            ex_mem_write  <= id_mem_write;
            ex_reg_write  <= id_reg_write && !id_serializing_noop;
            ex_branch     <= id_branch;
            ex_jal        <= id_jal;
            ex_jalr       <= id_jalr;
            ex_lui        <= id_lui;
            ex_auipc      <= id_auipc;
            ex_csr_en     <= id_csr_en;
            ex_csr_cmd    <= id_csr_cmd;
            ex_csr_imm    <= id_csr_imm;
            ex_mret       <= id_mret;
            ex_sret       <= id_sret;
            ex_sfence_vma <= id_sfence_vma;
            ex_wfi        <= id_wfi;
            ex_fence_i    <= id_fence_i;
            ex_muldiv     <= id_muldiv;
            ex_muldiv_op  <= id_muldiv_op;
            ex_amo        <= id_amo;
            ex_amo_op     <= id_amo_op;
            ex_fp_compute <= id_fp_compute;
            ex_fp_load    <= id_fp_load;
            ex_fp_store   <= id_fp_store;
`ifdef RISCV_FORMAL
            ex_trace_rs1_addr <= id_uses_rs1 ? id_rs1_addr : 0;
            ex_trace_rs2_addr <= id_uses_rs2 ? id_rs2_addr : 0;
`endif

            if (id_fetch_exception) begin
                ex_exception_cause <= id_fetch_cause;
                ex_exception_tval  <= id_fetch_tval;
            end else if (id_instr_illegal || id_illegal) begin
                ex_exception_cause <= CAUSE_ILLEGAL;
                ex_exception_tval  <= id_raw_instr;
            end else if (id_ebreak) begin
                ex_exception_cause <= CAUSE_BREAKPOINT;
                ex_exception_tval  <= 0;
            end else begin
                ex_exception_cause <= csr_privilege == 2'b00 ? CAUSE_ECALL_U :
                                      csr_privilege == 2'b01 ? CAUSE_ECALL_S :
                                                               CAUSE_ECALL_M;
                ex_exception_tval  <= 0;
            end
        end
    end

    // Execute forwarding and datapath
    reg [31:0] mem_pc;
`ifdef RISCV_FORMAL
    reg [31:0] mem_instr;
`endif
    reg [2:0]  mem_instr_length;
    reg        mem_valid;
    reg [31:0] mem_alu_result;
    reg [31:0] mem_vaddr;
    reg [31:0] mem_rs2_data;
    reg [4:0]  mem_rd;
    reg [2:0]  mem_funct3;
    reg        mem_mem_read, mem_mem_write, mem_reg_write;
    reg        mem_csr_en, mem_csr_write_intent, mem_mret;
    reg        mem_fence_i;
    reg        mem_sret, mem_sfence_vma;
    reg        mem_wfi;
    reg        mem_amo;
    reg [4:0]  mem_amo_op;
    reg        mem_fp_load, mem_fp_store, mem_fp_write;
    reg [63:0] mem_fp_data;
    reg [4:0]  mem_fp_flags;
    reg        mem_fp_flags_valid;
    reg [11:0] mem_csr_addr;
    reg [31:0] mem_csr_wdata;
    reg        mem_exception;
    reg [31:0] mem_exception_cause, mem_exception_tval;
    reg [31:0] mem_next_pc;
`ifdef RISCV_FORMAL
    reg [4:0]  mem_trace_rs1_addr, mem_trace_rs2_addr;
    reg [31:0] mem_trace_rs1_rdata, mem_trace_rs2_rdata;
    reg [31:0] mem_trace_next_pc;
`endif

    wire [1:0] fwd_a, fwd_b;
    wire [31:0] fwd_rs1, fwd_rs2;
    wire [31:0] mem_forward_data;

    forwarding_unit u_fwd (
        .ex_rs1        (ex_rs1_addr),
        .ex_rs2        (ex_rs2_addr),
        .mem_rd        (mem_rd),
        .mem_reg_write (mem_valid && mem_reg_write && !mem_exception &&
                        !mem_mem_read && !mem_amo),
        .wb_rd         (wb_rd),
        .wb_reg_write  (wb_reg_write_effective),
        .fwd_a         (fwd_a),
        .fwd_b         (fwd_b)
    );

    assign fwd_rs1 = (fwd_a == 2'b10) ? mem_forward_data :
                     (fwd_a == 2'b01) ? wb_data : ex_rs1_data;
    assign fwd_rs2 = (fwd_b == 2'b10) ? mem_forward_data :
                     (fwd_b == 2'b01) ? wb_data : ex_rs2_data;

    wire [63:0] fwd_frs1 = mem_valid && mem_fp_write &&
                            mem_rd == ex_instr[19:15] ? mem_fp_data :
                            wb_fp_write_effective &&
                            wb_fp_rd == ex_instr[19:15] ? wb_fp_data
                                                        : ex_frs1_data;
    wire [63:0] fwd_frs2 = mem_valid && mem_fp_write &&
                            mem_rd == ex_instr[24:20] ? mem_fp_data :
                            wb_fp_write_effective &&
                            wb_fp_rd == ex_instr[24:20] ? wb_fp_data
                                                        : ex_frs2_data;
    wire [63:0] fwd_frs3 = mem_valid && mem_fp_write &&
                            mem_rd == ex_instr[31:27] ? mem_fp_data :
                            wb_fp_write_effective &&
                            wb_fp_rd == ex_instr[31:27] ? wb_fp_data
                                                        : ex_frs3_data;

    wire [31:0] alu_a = ex_lui ? 0 : ex_auipc ? ex_pc : fwd_rs1;
    wire [31:0] alu_b = (ex_alu_src || ex_lui || ex_auipc)
                        ? ex_imm : fwd_rs2;
    wire [31:0] alu_result;
    wire        alu_zero_unused;

    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .alu_op (ex_alu_op),
        .result (alu_result),
        .zero   (alu_zero_unused)
    );

    reg         ex_unit_started;
    reg         ex_unit_complete;
    reg  [63:0] ex_unit_result;
    reg  [4:0]  ex_unit_flags;
    reg         ex_unit_result_to_int;
    reg         ex_unit_write_fp;
    wire        unused_muldiv_ready, unused_muldiv_busy, muldiv_done;
    wire [31:0] muldiv_result;
    wire        unused_fpu_ready, unused_fpu_busy, fpu_done, fpu_illegal;
    wire [63:0] fpu_result;
    wire [4:0]  fpu_flags;
    wire        fpu_result_to_int, fpu_write_fp;
    wire [2:0]  csr_frm;
    wire        csr_fp_enabled;
    wire        csr_mret_allowed, csr_sret_allowed, csr_sfence_allowed;
    wire        csr_wfi_allowed;
    wire        muldiv_start = ex_valid && ex_muldiv && !ex_exception &&
                               !ex_unit_started && !ex_unit_complete;
    wire        fpu_start = ex_valid && ex_fp_compute && !ex_exception &&
                            csr_fp_enabled && !fpu_illegal &&
                            !ex_unit_started && !ex_unit_complete;

    P_MULDIV32 u_muldiv (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (muldiv_start),
        .flush  (redirect_fire),
        .op     (ex_muldiv_op),
        .a      (fwd_rs1),
        .b      (fwd_rs2),
        .ready  (unused_muldiv_ready),
        .busy   (unused_muldiv_busy),
        .done   (muldiv_done),
        .result (muldiv_result)
    );

    P_FPU64 u_fpu (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (fpu_start),
        .flush        (redirect_fire),
        .instr        (ex_instr),
        .rs1_int      (fwd_rs1),
        .frs1         (fwd_frs1),
        .frs2         (fwd_frs2),
        .frs3         (fwd_frs3),
        .frm          (csr_frm),
        .ready        (unused_fpu_ready),
        .busy         (unused_fpu_busy),
        .done         (fpu_done),
        .illegal      (fpu_illegal),
        .result       (fpu_result),
        .flags        (fpu_flags),
        .result_to_int(fpu_result_to_int),
        .write_fp     (fpu_write_fp)
    );

    wire long_execute_hold = ex_valid && !ex_exception &&
        !ex_unit_complete &&
        (ex_muldiv || (ex_fp_compute && csr_fp_enabled && !fpu_illegal));
    assign execute_hold = long_execute_hold || dmmu_hold;

    always @(posedge clk) begin
        if (ex_reset) begin
            ex_unit_started <= 0;
            ex_unit_complete <= 0;
        end else if (branch_mispredict_ex) begin
            ex_unit_started <= 0;
            ex_unit_complete <= 0;
        end else begin
            if (muldiv_start || fpu_start) ex_unit_started <= 1;
            if (muldiv_done || fpu_done) ex_unit_complete <= 1;
            if (!mem_hold && !execute_hold) begin
                ex_unit_started <= 0;
                ex_unit_complete <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ex_unit_result <= 0;
            ex_unit_flags <= 0;
            ex_unit_result_to_int <= 0;
            ex_unit_write_fp <= 0;
        end else if (muldiv_done) begin
            ex_unit_result <= {32'b0, muldiv_result};
            ex_unit_flags <= 0;
            ex_unit_result_to_int <= 1;
            ex_unit_write_fp <= 0;
        end
        if (rst_n && fpu_done) begin
            ex_unit_result <= fpu_result;
            ex_unit_flags <= fpu_flags;
            ex_unit_result_to_int <= fpu_result_to_int;
            ex_unit_write_fp <= fpu_write_fp;
        end
    end

    wire branch_taken_ex;
    branch_unit u_branch (
        .rs1    (fwd_rs1),
        .rs2    (fwd_rs2),
        .funct3 (ex_funct3),
        .branch (ex_branch),
        .jal    (ex_jal),
        .jalr   (ex_jalr),
        .taken  (branch_taken_ex)
    );

    wire [31:0] branch_target_ex = ex_jalr
                                   ? (fwd_rs1 + ex_imm) & ~32'b1
                                   : ex_pc + ex_imm;
    wire branch_target_misaligned = ex_valid && branch_taken_ex &&
                                    (ex_branch || ex_jal || ex_jalr) &&
                                    branch_target_ex[0];
    wire data_halfword = ex_funct3 == 3'b001 || ex_funct3 == 3'b101;
    wire data_word = ex_funct3 == 3'b010;
    wire data_double = ex_funct3 == 3'b011;
    wire data_access_ex = ex_mem_read || ex_mem_write || ex_amo ||
                          ex_fp_load || ex_fp_store;
    wire data_store_ex = ex_mem_write || ex_fp_store ||
                         (ex_amo && ex_amo_op != 5'b00010);
    wire [3:0] data_access_size = data_double ? 8 :
                                  data_word || ex_amo ? 4 :
                                  data_halfword ? 2 : 1;
    wire data_misaligned = ex_valid &&
                           data_access_ex &&
                           ((data_halfword && alu_result[0]) ||
                            ((data_word || ex_amo) && |alu_result[1:0]) ||
                            (data_double && |alu_result[2:0]));

    wire dmmu_request = ex_valid && data_access_ex && !ex_exception &&
                        !data_misaligned;
    wire dmmu_ready, dmmu_page_fault, dmmu_access_fault;
    wire [31:0] dmmu_paddr;
    wire dm_req_valid, dm_req_ready, dm_req_write, dm_req_amo;
    wire [31:0] dm_req_addr, dm_req_wdata, dm_rsp_rdata;
    wire [3:0] dm_req_be; wire [4:0] dm_req_amo_op;
    wire dm_rsp_valid, dm_rsp_ready, dm_rsp_error, dm_req_allow;
    sv32_mmu u_dmmu (
        .clk(clk), .rst_n(rst_n), .flush(sfence_take),
        .req_valid(dmmu_request), .vaddr(alu_result),
        .privilege(csr_data_privilege),
        .access_read(ex_mem_read || ex_fp_load ||
                     (ex_amo && ex_amo_op != 5'b00011)),
        .access_write(data_store_ex), .access_execute(1'b0),
        .mstatus_sum(csr_mstatus_sum), .mstatus_mxr(csr_mstatus_mxr),
        .satp(csr_satp), .resp_ready(dmmu_ready), .paddr(dmmu_paddr),
        .page_fault(dmmu_page_fault), .access_fault(dmmu_access_fault),
        .mem_req_valid(dm_req_valid), .mem_req_ready(dm_req_ready),
        .mem_req_allow(dm_req_allow), .mem_req_write(dm_req_write),
        .mem_req_addr(dm_req_addr), .mem_req_wdata(dm_req_wdata),
        .mem_req_be(dm_req_be), .mem_req_amo(dm_req_amo),
        .mem_req_amo_op(dm_req_amo_op), .mem_rsp_valid(dm_rsp_valid),
        .mem_rsp_ready(dm_rsp_ready), .mem_rsp_rdata(dm_rsp_rdata),
        .mem_rsp_error(dm_rsp_error)
    );
    assign dmmu_hold = dmmu_request && !dmmu_ready;

    wire data_pmp_allow;
    pmp_checker u_data_pmp (
        .addr(dmmu_paddr), .size(data_access_size),
        .privilege(csr_data_privilege),
        .access_read(ex_mem_read || ex_fp_load ||
                     (ex_amo && ex_amo_op != 5'b00011)),
        .access_write(data_store_ex), .access_execute(1'b0),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(data_pmp_allow)
    );
    wire data_page_fault = dmmu_request && dmmu_ready && dmmu_page_fault;
    wire data_translation_access_fault = dmmu_request && dmmu_ready &&
                                         dmmu_access_fault;
    wire data_pmp_fault = dmmu_request && dmmu_ready &&
                          !dmmu_page_fault && !dmmu_access_fault &&
                          !data_pmp_allow;

    wire [31:0] csr_read_data;
    wire [31:0] csr_read_modify_data;
    wire        csr_read_illegal;
    wire [31:0] csr_source = ex_csr_imm
                             ? {27'b0, ex_instr[19:15]} : fwd_rs1;
    wire csr_write_intent_ex = ex_csr_en &&
                               (ex_csr_cmd == 2'b01 || csr_source != 0);
    wire [31:0] csr_write_data_ex = ex_csr_cmd == 2'b01 ? csr_source :
                                    ex_csr_cmd == 2'b10
                                        ? csr_read_modify_data | csr_source
                                        : csr_read_modify_data & ~csr_source;

    wire execute_exception = ex_exception ||
                             (ex_valid && ex_csr_en && csr_read_illegal) ||
                             (ex_valid && (ex_fp_compute || ex_fp_load ||
                                           ex_fp_store) && !csr_fp_enabled) ||
                             (ex_valid && ex_fp_compute && fpu_illegal) ||
                             (ex_valid && ex_mret && !csr_mret_allowed) ||
                             (ex_valid && ex_sret && !csr_sret_allowed) ||
                             (ex_valid && ex_sfence_vma &&
                              !csr_sfence_allowed) ||
                             (ex_valid && ex_wfi && !csr_wfi_allowed) ||
                             data_page_fault || data_translation_access_fault ||
                             data_pmp_fault ||
                             data_misaligned || branch_target_misaligned;
    wire [31:0] execute_exception_cause = ex_exception
        ? ex_exception_cause
        : ((ex_csr_en && csr_read_illegal) ||
           ((ex_fp_compute || ex_fp_load || ex_fp_store) && !csr_fp_enabled) ||
           (ex_fp_compute && fpu_illegal) ||
           (ex_mret && !csr_mret_allowed) ||
           (ex_sret && !csr_sret_allowed) ||
           (ex_sfence_vma && !csr_sfence_allowed) ||
           (ex_wfi && !csr_wfi_allowed)) ? CAUSE_ILLEGAL
        : data_page_fault ? (data_store_ex ? CAUSE_STORE_PAGE
                                            : CAUSE_LOAD_PAGE)
        : data_translation_access_fault
          ? (data_store_ex ? CAUSE_STORE_ACCESS : CAUSE_LOAD_ACCESS)
        : data_pmp_fault ? (data_store_ex ? CAUSE_STORE_ACCESS
                                           : CAUSE_LOAD_ACCESS)
        : data_misaligned ? ((ex_mem_write ||
                              (ex_amo && ex_amo_op != 5'b00010))
                              || ex_fp_store) ? CAUSE_STORE_MISALIGNED
                             : CAUSE_LOAD_MISALIGNED
        : CAUSE_INST_MISALIGNED;
    wire [31:0] execute_exception_tval = ex_exception
        ? ex_exception_tval
        : ((ex_csr_en && csr_read_illegal) ||
           ((ex_fp_compute || ex_fp_load || ex_fp_store) && !csr_fp_enabled) ||
           (ex_fp_compute && fpu_illegal) ||
           (ex_mret && !csr_mret_allowed) ||
           (ex_sret && !csr_sret_allowed) ||
           (ex_sfence_vma && !csr_sfence_allowed) ||
           (ex_wfi && !csr_wfi_allowed)) ? ex_raw_instr
        : (data_page_fault || data_translation_access_fault) ? alu_result
        : data_pmp_fault ? alu_result
        : data_misaligned ? alu_result : branch_target_ex;

    wire [31:0] execute_result = ex_muldiv ? ex_unit_result[31:0] :
                                 (ex_fp_compute && ex_unit_result_to_int)
                                 ? ex_unit_result[31:0] :
                                 ex_csr_en ? csr_read_data :
                                 (ex_jal || ex_jalr) ? ex_pc + ex_instr_length
                                                    : alu_result;

    wire branch_mispredict_raw = ex_valid && !execute_exception &&
                                 (ex_branch || ex_jal || ex_jalr) &&
                                 ex_pred_taken != branch_taken_ex;
    wire branch_mispredict_ex = branch_mispredict_raw && !mem_hold;
    wire [31:0] branch_recovery_pc_ex = branch_taken_ex
                                        ? branch_target_ex
                                        : ex_pc + ex_instr_length;

    // Memory access formatting and cache
    wire [31:0] dcache_cpu_rdata;
    wire [63:0] dcache_cpu_rdata64;
    wire        dcache_cpu_ready, dcache_cpu_error;
    wire [31:0] mem_store_wdata, mem_load_rdata;
    wire [3:0]  mem_store_be;
    wire        mem_misaligned_unused;
    assign mem_forward_data = mem_alu_result;

    memory_stage u_memory_format (
        .addr        (mem_alu_result[1:0]),
        .wdata       (mem_rs2_data),
        .funct3      (mem_funct3),
        .word_rdata  (dcache_cpu_rdata),
        .store_wdata (mem_store_wdata),
        .store_be    (mem_store_be),
        .load_rdata  (mem_load_rdata),
        .misaligned  (mem_misaligned_unused)
    );

    wire dcache_cpu_valid = mem_valid && !mem_exception &&
                            (mem_mem_read || mem_mem_write || mem_amo ||
                             mem_fp_load || mem_fp_store);
    wire dcache_cpu_write = mem_mem_write || mem_fp_store;
    wire dcache_cpu_double = (mem_fp_load || mem_fp_store) &&
                              mem_funct3 == 3'b011;
    wire [31:0] dcache_store_wdata = mem_fp_store
                                     ? mem_fp_data[31:0] : mem_store_wdata;
    wire [3:0] dcache_store_be = mem_fp_store ? 4'b1111 : mem_store_be;
    wire dc_req_valid, dc_req_ready, dc_req_write, dc_req_amo;
    wire [31:0] dc_req_addr, dc_req_wdata, dc_rsp_rdata;
    wire [3:0] dc_req_be; wire [4:0] dc_req_amo_op;
    wire dc_rsp_valid, dc_rsp_ready, dc_rsp_error, dc_req_allow;
    pmp_checker u_dmem_fill_pmp (
        .addr(dc_req_addr), .size(4'd4), .privilege(csr_data_privilege),
        .access_read(!dc_req_write ||
                     (dc_req_amo && dc_req_amo_op != 5'b00011)),
        .access_write(dc_req_write ||
                      (dc_req_amo && dc_req_amo_op != 5'b00010)),
        .access_execute(1'b0), .pmpcfg0(csr_pmpcfg0),
        .pmpaddr0(csr_pmpaddr0), .pmpaddr1(csr_pmpaddr1),
        .pmpaddr2(csr_pmpaddr2), .pmpaddr3(csr_pmpaddr3),
        .allow(dc_req_allow)
    );

    dcache u_dcache (
        .clk           (clk),
        .rst_n         (rst_n),
        .cpu_valid     (dcache_cpu_valid),
        .cpu_write     (dcache_cpu_write),
        .cpu_double    (dcache_cpu_double),
        .cpu_cacheable (mem_alu_result < 32'h0200_0000 ||
                        mem_alu_result >= 32'h2000_0000),
        .cpu_amo       (mem_amo),
        .cpu_amo_op    (mem_amo_op),
        .cpu_addr      (mem_alu_result),
        .cpu_wdata     (dcache_store_wdata),
        .cpu_wdata64   (mem_fp_data),
        .cpu_be        (dcache_store_be),
        .cpu_rdata     (dcache_cpu_rdata),
        .cpu_rdata64   (dcache_cpu_rdata64),
        .cpu_ready     (dcache_cpu_ready),
        .cpu_error     (dcache_cpu_error),
        .reservation_invalidate(reservation_invalidate ||
            (dmem_req_valid && dmem_req_ready && dmem_req_amo)),
        .mem_req_valid (dc_req_valid),
        .mem_req_allow (dc_req_allow),
        .mem_req_ready (dc_req_ready),
        .mem_req_write (dc_req_write),
        .mem_req_addr  (dc_req_addr),
        .mem_req_wdata (dc_req_wdata),
        .mem_req_be    (dc_req_be),
        .mem_req_amo   (dc_req_amo),
        .mem_req_amo_op(dc_req_amo_op),
        .mem_rsp_valid (dc_rsp_valid),
        .mem_rsp_ready (dc_rsp_ready),
        .mem_rsp_rdata (dc_rsp_rdata),
        .mem_rsp_error (dc_rsp_error)
    );

    pmp_checker u_im0_ptw_pmp (
        .addr(im0_req_addr), .size(4'd4), .privilege(2'b01),
        .access_read(1'b1), .access_write(im0_req_amo), .access_execute(1'b0),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(im0_req_allow)
    );
    pmp_checker u_im1_ptw_pmp (
        .addr(im1_req_addr), .size(4'd4), .privilege(2'b01),
        .access_read(1'b1), .access_write(im1_req_amo), .access_execute(1'b0),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(im1_req_allow)
    );
    pmp_checker u_dm_ptw_pmp (
        .addr(dm_req_addr), .size(4'd4), .privilege(2'b01),
        .access_read(1'b1), .access_write(dm_req_amo), .access_execute(1'b0),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(dm_req_allow)
    );

    memory_arbiter4 u_dmem_arbiter (
        .clk(clk), .rst_n(rst_n),
        .m0_req_valid(dm_req_valid), .m0_req_ready(dm_req_ready),
        .m0_req_write(dm_req_write), .m0_req_addr(dm_req_addr),
        .m0_req_wdata(dm_req_wdata), .m0_req_be(dm_req_be),
        .m0_req_amo(dm_req_amo), .m0_req_amo_op(dm_req_amo_op),
        .m0_rsp_valid(dm_rsp_valid), .m0_rsp_ready(dm_rsp_ready),
        .m0_rsp_rdata(dm_rsp_rdata), .m0_rsp_error(dm_rsp_error),
        .m1_req_valid(im1_req_valid), .m1_req_ready(im1_req_ready),
        .m1_req_write(im1_req_write), .m1_req_addr(im1_req_addr),
        .m1_req_wdata(im1_req_wdata), .m1_req_be(im1_req_be),
        .m1_req_amo(im1_req_amo), .m1_req_amo_op(im1_req_amo_op),
        .m1_rsp_valid(im1_rsp_valid), .m1_rsp_ready(im1_rsp_ready),
        .m1_rsp_rdata(im1_rsp_rdata), .m1_rsp_error(im1_rsp_error),
        .m2_req_valid(im0_req_valid), .m2_req_ready(im0_req_ready),
        .m2_req_write(im0_req_write), .m2_req_addr(im0_req_addr),
        .m2_req_wdata(im0_req_wdata), .m2_req_be(im0_req_be),
        .m2_req_amo(im0_req_amo), .m2_req_amo_op(im0_req_amo_op),
        .m2_rsp_valid(im0_rsp_valid), .m2_rsp_ready(im0_rsp_ready),
        .m2_rsp_rdata(im0_rsp_rdata), .m2_rsp_error(im0_rsp_error),
        .m3_req_valid(dc_req_valid), .m3_req_ready(dc_req_ready),
        .m3_req_write(dc_req_write), .m3_req_addr(dc_req_addr),
        .m3_req_wdata(dc_req_wdata), .m3_req_be(dc_req_be),
        .m3_req_amo(dc_req_amo), .m3_req_amo_op(dc_req_amo_op),
        .m3_rsp_valid(dc_rsp_valid), .m3_rsp_ready(dc_rsp_ready),
        .m3_rsp_rdata(dc_rsp_rdata), .m3_rsp_error(dc_rsp_error),
        .ext_req_valid(dmem_req_valid), .ext_req_ready(dmem_req_ready),
        .ext_req_write(dmem_req_write), .ext_req_addr(dmem_req_addr),
        .ext_req_wdata(dmem_req_wdata), .ext_req_be(dmem_req_be),
        .ext_req_amo(dmem_req_amo), .ext_req_amo_op(dmem_req_amo_op),
        .ext_rsp_valid(dmem_rsp_valid), .ext_rsp_ready(dmem_rsp_ready),
        .ext_rsp_rdata(dmem_rsp_rdata), .ext_rsp_error(dmem_rsp_error)
    );

    assign mem_hold = dcache_cpu_valid && !dcache_cpu_ready;
    wire mem_access_error = dcache_cpu_valid && dcache_cpu_ready &&
                            dcache_cpu_error;
    wire exception_take = mem_valid && !mem_hold &&
                          (mem_exception || mem_access_error);
    wire retire_event = mem_valid && !mem_hold && !exception_take;
    wire [31:0] exception_cause = mem_exception ? mem_exception_cause :
                             (mem_mem_write || mem_fp_store ||
                              (mem_amo && mem_amo_op != 5'b00010))
                             ? CAUSE_STORE_ACCESS : CAUSE_LOAD_ACCESS;
    wire [31:0] exception_tval = mem_exception ? mem_exception_tval
                                               : mem_vaddr;
    wire csr_interrupt_pending;
    wire csr_wfi_wake_pending;
    wire [31:0] csr_interrupt_cause;
    wire interrupt_take = mem_valid && !mem_hold && !exception_take &&
                          !mem_mret && !mem_sret && !mem_fence_i &&
                          !mem_sfence_vma && !debug_req &&
                          csr_interrupt_pending;
    assign wfi_wake = wfi_sleep && csr_wfi_wake_pending;
    assign wfi_wake_trap = wfi_wake && csr_interrupt_pending;
    assign wfi_wake_resume = wfi_wake && !csr_interrupt_pending;
    // Cancel directly from the registered redirect causes so the full redirect
    // priority tree does not feed every cache-state latch.
    assign icache_cancel = branch_mispredict_raw ||
                           (mem_valid &&
                            (mem_exception || mem_mret || mem_sret ||
                             mem_sfence_vma || mem_wfi ||
                             csr_interrupt_pending || debug_req)) ||
                           dcache_cpu_error || debug_enter ||
                           debug_resume_fire || wfi_wake ||
                           (icache_error && !mem_hold && !stall_haz);
    wire debug_retire_boundary = mem_valid && !mem_hold && !exception_take;
    debug_control u_debug (
        .clk(clk), .rst_n(rst_n), .debug_req(debug_req),
        .resume_req(debug_resume), .retire_boundary(debug_retire_boundary),
        .step(debug_step), .dpc_write(debug_dpc_write),
        .dpc_wdata(debug_dpc_wdata),
        .next_pc(mem_next_pc), .enter_fire(debug_enter),
        .resume_fire(debug_resume_fire), .halted(debug_halted),
        .dpc(debug_dpc)
    );
    wire trap_take = exception_take || interrupt_take || wfi_wake_trap;
    wire [31:0] trap_cause = (interrupt_take || wfi_wake_trap)
                             ? csr_interrupt_cause : exception_cause;
    wire [31:0] trap_tval = (interrupt_take || wfi_wake_trap)
                            ? 0 : exception_tval;
    wire [31:0] trap_pc = wfi_wake_trap ? wfi_resume_pc :
                          interrupt_take ? mem_next_pc : mem_pc;
    wire mret_take = mem_valid && mem_mret && !trap_take && !debug_enter &&
                     !mem_hold;
    wire sret_take = mem_valid && mem_sret && !trap_take && !debug_enter &&
                     !mem_hold;
    wire fence_i_take = mem_valid && mem_fence_i && !trap_take &&
                        !debug_enter && !mem_hold;
    assign sfence_take = mem_valid && mem_sfence_vma && !trap_take &&
                         !debug_enter && !mem_hold;
    wire wfi_enter = mem_valid && mem_wfi && !trap_take && !debug_enter &&
                     !mem_hold && !csr_wfi_wake_pending;
    wire wfi_debug_wake = wfi_sleep && debug_req;
    wire csr_commit_valid = mem_valid && mem_csr_en &&
                            mem_csr_write_intent && !exception_take && !mem_hold;
    wire fp_flags_commit = mem_valid && mem_fp_flags_valid &&
                           !exception_take && !mem_hold;
    wire fp_dirty_commit = mem_valid && (mem_fp_write ||
                                          mem_fp_flags_valid) &&
                           !exception_take && !mem_hold;

    wire [31:0] csr_trap_vector;
    wire [31:0] csr_return_pc;
    wire [31:0] csr_sreturn_pc;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] csr_commit_visible_data;
    /* verilator lint_on UNUSEDSIGNAL */
    wire csr_mstatus_mprv_unused;

    csr_file u_csr (
        .clk               (clk),
        .rst_n             (rst_n),
        .read_addr         (ex_instr[31:20]),
        .read_write_intent (csr_write_intent_ex),
        .read_data         (csr_read_data),
        .read_modify_data  (csr_read_modify_data),
        .read_illegal      (csr_read_illegal),
        .commit_valid      (csr_commit_valid),
        .commit_addr       (mem_csr_addr),
        .commit_data       (mem_csr_wdata),
        .commit_visible_data(csr_commit_visible_data),
        .retire            (retire_event),
        .fp_flags_valid    (fp_flags_commit),
        .fp_flags          (mem_fp_flags),
        .fp_dirty          (fp_dirty_commit),
        .mtime             (mtime),
        .irq_m_software    (irq_m_software_sync[1]),
        .irq_m_timer       (irq_m_timer_sync[1]),
        .irq_m_external    (irq_m_external_sync[1]),
        .irq_s_software    (irq_s_software_sync[1]),
        .irq_s_timer       (irq_s_timer_sync[1]),
        .irq_s_external    (irq_s_external_sync[1]),
        .nmi               (nmi_sync[1]),
        .trap_enter        (trap_take),
        .trap_pc           (trap_pc),
        .trap_cause        (trap_cause),
        .trap_tval         (trap_tval),
        .mret              (mret_take),
        .sret              (sret_take),
        .trap_vector       (csr_trap_vector),
        .return_pc         (csr_return_pc),
        .sreturn_pc        (csr_sreturn_pc),
        .frm_out           (csr_frm),
        .fp_enabled        (csr_fp_enabled),
        .interrupt_pending (csr_interrupt_pending),
        .interrupt_cause   (csr_interrupt_cause),
        .wfi_wake_pending  (csr_wfi_wake_pending),
        .privilege         (csr_privilege),
        .data_privilege    (csr_data_privilege),
        .pmpcfg0_out       (csr_pmpcfg0),
        .pmpaddr0_out      (csr_pmpaddr0),
        .pmpaddr1_out      (csr_pmpaddr1),
        .pmpaddr2_out      (csr_pmpaddr2),
        .pmpaddr3_out      (csr_pmpaddr3),
        .satp_out          (csr_satp),
        .mstatus_sum_out   (csr_mstatus_sum),
        .mstatus_mxr_out   (csr_mstatus_mxr),
        .mstatus_mprv_out  (csr_mstatus_mprv_unused),
        .mret_allowed      (csr_mret_allowed),
        .sret_allowed      (csr_sret_allowed),
        .sfence_allowed    (csr_sfence_allowed),
        .wfi_allowed       (csr_wfi_allowed)
    );

    always @(posedge clk) begin
        if (!rst_n) begin wfi_sleep <= 0; wfi_resume_pc <= 0; end
        else begin
            if (wfi_enter) begin
                wfi_sleep <= 1;
                wfi_resume_pc <= mem_next_pc;
            end
            if (wfi_wake || wfi_debug_wake) wfi_sleep <= 0;
        end
    end

    assign icache_invalidate = fence_i_take;
    assign retirement_redirect_fire = trap_take || debug_enter ||
                           debug_resume_fire || mret_take || sret_take ||
                           fence_i_take || sfence_take || wfi_enter ||
                           wfi_wake_resume || wfi_debug_wake;
    assign redirect_fire = retirement_redirect_fire || branch_mispredict_ex;
    assign redirect_pc = trap_take ? csr_trap_vector :
                         debug_resume_fire ? debug_dpc :
                         mret_take ? csr_return_pc :
                         sret_take ? csr_sreturn_pc :
                         wfi_enter ? mem_next_pc :
                         wfi_wake_resume ? wfi_resume_pc :
                         wfi_debug_wake ? wfi_resume_pc :
                         fence_i_take ? mem_pc + mem_instr_length
                         : sfence_take ? mem_pc + mem_instr_length
                                      : branch_recovery_pc_ex;

    // EX/MEM pipeline state. A branch redirect does not discard the branch.
    always @(posedge clk) begin
        if (!rst_n || trap_take || debug_enter || debug_resume_fire ||
            mret_take || sret_take ||
            fence_i_take || sfence_take || wfi_enter || wfi_wake_resume ||
            wfi_debug_wake) begin
            mem_valid <= 0;
            mem_exception <= 0;
        end else if (mem_hold) begin
            // Hold until the cache completes the current memory instruction.
        end else if (execute_hold) begin
            // Drain MEM while a multicycle execute macro owns EX.
            mem_valid <= 0;
            mem_exception <= 0;
        end else begin
            mem_valid            <= ex_valid;
            mem_exception        <= ex_valid && execute_exception;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_pc <= 0;
`ifdef RISCV_FORMAL
            mem_instr <= 0;
`endif
            mem_instr_length <= 4;
            mem_alu_result <= 0;
            mem_vaddr <= 0;
            mem_rs2_data <= 0;
            mem_rd <= 0;
            mem_funct3 <= 0;
            mem_mem_read <= 0;
            mem_mem_write <= 0;
            mem_reg_write <= 0;
            mem_csr_en <= 0;
            mem_csr_addr <= 0;
            mem_csr_wdata <= 0;
            mem_csr_write_intent <= 0;
            mem_mret <= 0;
            mem_sret <= 0;
            mem_sfence_vma <= 0;
            mem_wfi <= 0;
            mem_fence_i <= 0;
            mem_amo <= 0;
            mem_amo_op <= 0;
            mem_fp_load <= 0;
            mem_fp_store <= 0;
            mem_fp_write <= 0;
            mem_fp_data <= 0;
            mem_fp_flags <= 0;
            mem_fp_flags_valid <= 0;
            mem_exception_cause <= 0;
            mem_exception_tval <= 0;
            mem_next_pc <= 0;
`ifdef RISCV_FORMAL
            mem_trace_rs1_addr <= 0;
            mem_trace_rs2_addr <= 0;
            mem_trace_rs1_rdata <= 0;
            mem_trace_rs2_rdata <= 0;
            mem_trace_next_pc <= 0;
`endif
        end else if (!mem_hold && !execute_hold) begin
            mem_pc               <= ex_pc;
`ifdef RISCV_FORMAL
            mem_instr            <= ex_raw_instr;
`endif
            mem_instr_length     <= ex_instr_length;
            mem_alu_result       <= data_access_ex ? dmmu_paddr
                                                    : execute_result;
            mem_vaddr            <= alu_result;
            mem_rs2_data         <= fwd_rs2;
            mem_rd               <= ex_rd;
            mem_funct3           <= ex_funct3;
            mem_mem_read         <= ex_mem_read;
            mem_mem_write        <= ex_mem_write;
            mem_reg_write        <= ex_reg_write ||
                                    (ex_fp_compute &&
                                     ex_unit_result_to_int);
            mem_csr_en           <= ex_csr_en;
            mem_csr_addr         <= ex_instr[31:20];
            mem_csr_wdata        <= csr_write_data_ex;
            mem_csr_write_intent <= csr_write_intent_ex;
            mem_mret             <= ex_mret;
            mem_sret             <= ex_sret;
            mem_sfence_vma       <= ex_sfence_vma;
            mem_wfi              <= ex_wfi;
            mem_fence_i          <= ex_fence_i;
            mem_amo              <= ex_amo;
            mem_amo_op           <= ex_amo_op;
            mem_fp_load          <= ex_fp_load;
            mem_fp_store         <= ex_fp_store;
            mem_fp_write         <= ex_fp_load ||
                                    (ex_fp_compute && ex_unit_write_fp);
            mem_fp_data          <= ex_fp_store ? fwd_frs2 : ex_unit_result;
            mem_fp_flags         <= ex_unit_flags;
            mem_fp_flags_valid   <= ex_fp_compute;
            mem_exception_cause <= execute_exception_cause;
            mem_exception_tval  <= execute_exception_tval;
            mem_next_pc         <= (ex_branch || ex_jal || ex_jalr)
                                   ? branch_recovery_pc_ex
                                   : ex_pc + ex_instr_length;
`ifdef RISCV_FORMAL
            mem_trace_rs1_addr  <= ex_trace_rs1_addr;
            mem_trace_rs2_addr  <= ex_trace_rs2_addr;
            mem_trace_rs1_rdata <= ex_trace_rs1_addr != 0 ? fwd_rs1 : 0;
            mem_trace_rs2_rdata <= ex_trace_rs2_addr != 0 ? fwd_rs2 : 0;
            mem_trace_next_pc   <= (ex_branch || ex_jal || ex_jalr)
                                   ? branch_recovery_pc_ex
                                   : ex_pc + ex_instr_length;
`endif
        end
    end

    // MEM/WB retirement state. A blocked MEM stage cannot issue twice.
    always @(posedge clk) begin
        if (!rst_n) begin
            wb_valid <= 0;
            wb_rd <= 0;
            wb_data <= 0;
            wb_reg_write <= 0;
            wb_fp_write <= 0;
            wb_fp_rd <= 0;
            wb_fp_data <= 0;
        end else begin
            wb_valid <= mem_valid && !mem_hold && !exception_take;
            if (mem_valid && !mem_hold && !exception_take) begin
                wb_rd <= mem_rd;
                wb_data <= mem_mem_read ? mem_load_rdata :
                           mem_amo ? dcache_cpu_rdata : mem_alu_result;
                wb_reg_write <= mem_reg_write;
                wb_fp_write <= mem_fp_write;
                wb_fp_rd <= mem_rd;
                wb_fp_data <= mem_fp_load
                              ? (mem_funct3 == 3'b011
                                 ? dcache_cpu_rdata64
                                 : {32'hffff_ffff, dcache_cpu_rdata})
                              : mem_fp_data;
            end
        end
    end

`ifdef RISCV_FORMAL
    assign rvfi_ixl  = 2'b01;
    reg [63:0] rvfi_next_order;

    function automatic [3:0] trace_load_mask;
        input [2:0] funct3;
        input [1:0] addr;
        begin
            case (funct3)
                3'b000, 3'b100: trace_load_mask = 4'b0001 << addr;
                3'b001, 3'b101: trace_load_mask = 4'b0011 << {addr[1], 1'b0};
                default:        trace_load_mask = 4'b1111;
            endcase
        end
    endfunction

    function automatic [31:0] trace_amo_result;
        input [4:0] op;
        input [31:0] old_value, operand;
        begin
            case (op)
                5'b00000: trace_amo_result = old_value + operand;
                5'b00100: trace_amo_result = old_value ^ operand;
                5'b01100: trace_amo_result = old_value & operand;
                5'b01000: trace_amo_result = old_value | operand;
                5'b10000: trace_amo_result = $signed(old_value) <
                                                    $signed(operand)
                                             ? old_value : operand;
                5'b10100: trace_amo_result = $signed(old_value) >
                                                    $signed(operand)
                                             ? old_value : operand;
                5'b11000: trace_amo_result = old_value < operand
                                             ? old_value : operand;
                5'b11100: trace_amo_result = old_value > operand
                                             ? old_value : operand;
                default:  trace_amo_result = operand;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            rvfi_valid <= 0;
            rvfi_order <= 0;
            rvfi_next_order <= 0;
            rvfi_insn <= 0;
            rvfi_trap <= 0;
            rvfi_halt <= 0;
            rvfi_intr <= 0;
            rvfi_mode <= 2'b11;
            rvfi_rs1_addr <= 0;
            rvfi_rs2_addr <= 0;
            rvfi_rs1_rdata <= 0;
            rvfi_rs2_rdata <= 0;
            rvfi_rd_addr <= 0;
            rvfi_rd_wdata <= 0;
            rvfi_pc_rdata <= 0;
            rvfi_pc_wdata <= 0;
            rvfi_mem_addr <= 0;
            rvfi_mem_rmask <= 0;
            rvfi_mem_wmask <= 0;
            rvfi_mem_rdata <= 0;
            rvfi_mem_wdata <= 0;
            rvfi_frd_valid <= 0;
            rvfi_frd_addr <= 0;
            rvfi_frd_wdata <= 0;
            rvfi_csr_valid <= 0;
            rvfi_csr_addr <= 0;
            rvfi_csr_wdata <= 0;
        end else begin
            rvfi_valid <= mem_valid && !mem_hold;
            rvfi_halt <= 0;
            rvfi_intr <= 0;
            rvfi_frd_valid <= 0;
            rvfi_csr_valid <= 0;
            if (mem_valid && !mem_hold) begin
                rvfi_order <= rvfi_next_order;
                rvfi_next_order <= rvfi_next_order + 1;
                rvfi_insn <= mem_instr;
                rvfi_trap <= exception_take;
                rvfi_halt <= debug_enter;
                rvfi_intr <= interrupt_take || wfi_wake_trap;
                rvfi_mode <= csr_privilege;
                rvfi_rs1_addr <= mem_trace_rs1_addr;
                rvfi_rs2_addr <= mem_trace_rs2_addr;
                rvfi_rs1_rdata <= mem_trace_rs1_rdata;
                rvfi_rs2_rdata <= mem_trace_rs2_rdata;
                rvfi_rd_addr <= (!exception_take && mem_reg_write) ? mem_rd : 0;
                rvfi_rd_wdata <= (!exception_take && mem_reg_write && mem_rd != 0)
                                  ? (mem_mem_read ? mem_load_rdata :
                                     mem_amo ? dcache_cpu_rdata
                                             : mem_alu_result) : 0;
                rvfi_pc_rdata <= mem_pc;
                rvfi_pc_wdata <= trap_take ? csr_trap_vector
                                  : mret_take ? csr_return_pc
                                  : sret_take ? csr_sreturn_pc
                                              : mem_trace_next_pc;
                rvfi_mem_addr <= (mem_mem_read || mem_mem_write || mem_amo)
                                 ? mem_alu_result : 0;
                rvfi_mem_rmask <= (!exception_take && (mem_mem_read ||
                                  (mem_amo && mem_amo_op != 5'b00011)))
                                  ? trace_load_mask(mem_funct3,
                                                    mem_alu_result[1:0]) : 0;
                rvfi_mem_wmask <= (!exception_take && (mem_mem_write ||
                                  (mem_amo && mem_amo_op != 5'b00010 &&
                                   (mem_amo_op != 5'b00011 ||
                                    dcache_cpu_rdata == 0))))
                                  ? (mem_amo ? 4'b1111 : mem_store_be) : 0;
                rvfi_mem_rdata <= (mem_mem_read || mem_amo)
                                  ? dcache_cpu_rdata : 0;
                rvfi_mem_wdata <= mem_mem_write ? mem_store_wdata :
                                  mem_amo ? trace_amo_result(
                                      mem_amo_op, dcache_cpu_rdata,
                                      mem_rs2_data) : 0;
                rvfi_frd_valid <= !exception_take && mem_fp_write;
                rvfi_frd_addr <= mem_rd;
                rvfi_frd_wdata <= mem_fp_load
                    ? (mem_funct3 == 3'b011 ? dcache_cpu_rdata64
                                            : {32'hffff_ffff, dcache_cpu_rdata})
                    : mem_fp_data;
                // mip is driven by platform interrupt state, not CSR writes.
                rvfi_csr_valid <= csr_commit_valid && mem_csr_addr != 12'h344;
                rvfi_csr_addr <= mem_csr_addr;
                rvfi_csr_wdata <= csr_commit_visible_data;
            end
        end
    end
`ifdef FORMAL_COMMIT
    reg formal_past_valid = 0;
    initial assume(!rst_n);
    always @(posedge clk) begin
        formal_past_valid <= 1;
        if (formal_past_valid) assume(rst_n);
        if (formal_past_valid && $past(rst_n)) begin
            if ($past(mem_valid && !mem_hold)) begin
                assert(rvfi_valid);
                assert(rvfi_trap == $past(exception_take));
            end
            if ($past(mem_valid && !mem_hold && exception_take)) begin
                assert(!wb_valid);
                assert(rvfi_rd_addr == 0 && rvfi_mem_wmask == 0);
                assert(!rvfi_frd_valid && !rvfi_csr_valid);
            end
            if ($past(mem_valid && !mem_hold && mem_reg_write && mem_rd == 0))
                assert(rvfi_rd_wdata == 0);
            if (rvfi_valid && rvfi_mem_wmask != 0)
                assert(!rvfi_trap);
            if (rvfi_valid && $past(rvfi_valid))
                assert(rvfi_order == $past(rvfi_order) + 1);
        end
    end
`endif
`endif
endmodule
