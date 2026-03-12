module top (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire        dmem_we,
    output wire [3:0]  dmem_be,
    input  wire [31:0] dmem_rdata,
    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_instr_if,
    output wire [31:0] dbg_instr_id,
    output wire [4:0]  dbg_rd_ex,
    output wire [4:0]  dbg_rd_mem,
    output wire [4:0]  dbg_rd_wb,
    output wire        dbg_stall,
    output wire        dbg_flush
);

    wire [31:0] if_pc, if_instr;
    wire        stall_if, flush_if;
    wire        branch_taken_ex;
    wire [31:0] branch_target_ex;

    reg  [31:0] id_pc, id_instr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_if) begin
            id_pc    <= 0;
            id_instr <= 32'h0000_0013;
        end else if (!stall_if) begin
            id_pc    <= if_pc;
            id_instr <= if_instr;
        end
    end

    wire [4:0]  id_rs1_addr, id_rs2_addr, id_rd;
    wire [31:0] id_rs1_data, id_rs2_data, id_imm;
    wire [3:0]  id_alu_op;
    wire        id_alu_src, id_mem_read, id_mem_write, id_reg_write;
    wire        id_branch, id_jal, id_jalr, id_lui, id_auipc;
    wire [2:0]  id_funct3;
    
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;
    wire        wb_reg_write;

    wire [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    wire [4:0]  ex_rs1_addr, ex_rs2_addr, ex_rd;
    wire [3:0]  ex_alu_op;
    wire        ex_alu_src, ex_mem_read, ex_mem_write, ex_reg_write;
    wire        ex_branch, ex_jal, ex_jalr, ex_lui, ex_auipc;
    wire [2:0]  ex_funct3;
    
    wire [4:0]  mem_rd;
    wire        mem_reg_write;
    wire [1:0]  fwd_a, fwd_b;
    wire [31:0] mem_alu_result; 
    wire [31:0] fwd_rs1, fwd_rs2;
    wire        stall_haz, flush_id_ex_haz;

    assign stall_if  = stall_haz;
    assign flush_if  = branch_taken_ex;
    
    assign fwd_rs1 = (fwd_a == 2'b10) ? mem_alu_result :
                     (fwd_a == 2'b01) ? wb_data : ex_rs1_data;
    assign fwd_rs2 = (fwd_b == 2'b10) ? mem_alu_result :
                     (fwd_b == 2'b01) ? wb_data : ex_rs2_data;

    wire [31:0] alu_a, alu_b, alu_result;
    wire        alu_zero;
    
    assign alu_a = ex_lui  ? 32'b0 :
                   ex_auipc ? ex_pc : fwd_rs1;
    assign alu_b = (ex_alu_src || ex_lui || ex_auipc) ? ex_imm : fwd_rs2;
    
    assign branch_target_ex = ex_jalr ? (fwd_rs1 + ex_imm) & ~32'b1 :
                                          ex_pc + ex_imm;

    wire [31:0] mem_rs2_data, mem_branch_target;
    wire        mem_mem_read, mem_mem_write, mem_branch_taken;
    wire [2:0]  mem_funct3;
    wire [31:0] mem_rdata;
    
    wire [31:0] wb_alu_result, wb_mem_rdata;
    wire        wb_mem_read;

    // Instantiations
    if_stage u_if (.clk(clk), .rst_n(rst_n), .stall(stall_if), .flush(flush_if), .branch_target(branch_target_ex), .branch_taken(branch_taken_ex), .pc_out(if_pc), .instr_out(if_instr), .imem_addr(imem_addr), .imem_data(imem_data));
    
    decoder u_dec (.instr(id_instr), .rs1(id_rs1_addr), .rs2(id_rs2_addr), .rd(id_rd), .imm(id_imm), .alu_op(id_alu_op), .alu_src(id_alu_src), .mem_read(id_mem_read), .mem_write(id_mem_write), .reg_write(id_reg_write), .branch(id_branch), .jal(id_jal), .jalr(id_jalr), .funct3(id_funct3), .lui(id_lui), .auipc(id_auipc));
    
    regfile u_rf (.clk(clk), .rst_n(rst_n), .rs1_addr(id_rs1_addr), .rs2_addr(id_rs2_addr), .rd_addr(wb_rd), .rd_data(wb_data), .wr_en(wb_reg_write), .rs1_data(id_rs1_data), .rs2_data(id_rs2_data));
    
    hazard_unit u_haz (.id_rs1(id_rs1_addr), .id_rs2(id_rs2_addr), .ex_rd(ex_rd), .ex_mem_read(ex_mem_read), .stall(stall_haz), .flush_id_ex(flush_id_ex_haz));
    
    id_ex_reg u_id_ex (.clk(clk), .rst_n(rst_n), .flush(flush_id_ex_haz || branch_taken_ex), .stall(1'b0), .pc_in(id_pc), .rs1_data_in(id_rs1_data), .rs2_data_in(id_rs2_data), .imm_in(id_imm), .rs1_addr_in(id_rs1_addr), .rs2_addr_in(id_rs2_addr), .rd_in(id_rd), .alu_op_in(id_alu_op), .alu_src_in(id_alu_src), .mem_read_in(id_mem_read), .mem_write_in(id_mem_write), .reg_write_in(id_reg_write), .branch_in(id_branch), .jal_in(id_jal), .jalr_in(id_jalr), .funct3_in(id_funct3), .lui_in(id_lui), .auipc_in(id_auipc), .pc_out(ex_pc), .rs1_data_out(ex_rs1_data), .rs2_data_out(ex_rs2_data), .imm_out(ex_imm), .rs1_addr_out(ex_rs1_addr), .rs2_addr_out(ex_rs2_addr), .rd_out(ex_rd), .alu_op_out(ex_alu_op), .alu_src_out(ex_alu_src), .mem_read_out(ex_mem_read), .mem_write_out(ex_mem_write), .reg_write_out(ex_reg_write), .branch_out(ex_branch), .jal_out(ex_jal), .jalr_out(ex_jalr), .funct3_out(ex_funct3), .lui_out(ex_lui), .auipc_out(ex_auipc));
    
    forwarding_unit u_fwd (.ex_rs1(ex_rs1_addr), .ex_rs2(ex_rs2_addr), .mem_rd(mem_rd), .mem_reg_write(mem_reg_write), .wb_rd(wb_rd), .wb_reg_write(wb_reg_write), .fwd_a(fwd_a), .fwd_b(fwd_b));
    
    alu u_alu (.a(alu_a), .b(alu_b), .alu_op(ex_alu_op), .result(alu_result), .zero(alu_zero));
    
    branch_unit u_br (.rs1(fwd_rs1), .rs2(fwd_rs2), .funct3(ex_funct3), .branch(ex_branch), .jal(ex_jal), .jalr(ex_jalr), .taken(branch_taken_ex));
    
    wire [31:0] ex_alu_result_final;
    assign ex_alu_result_final = (ex_jal || ex_jalr) ? (ex_pc + 4) : alu_result;

    ex_mem_reg u_ex_mem (.clk(clk), .rst_n(rst_n), .flush(1'b0), .alu_result_in(ex_alu_result_final), .rs2_data_in(fwd_rs2), .rd_in(ex_rd), .mem_read_in(ex_mem_read), .mem_write_in(ex_mem_write), .reg_write_in(ex_reg_write), .funct3_in(ex_funct3), .branch_taken_in(branch_taken_ex), .branch_target_in(branch_target_ex), .alu_result_out(mem_alu_result), .rs2_data_out(mem_rs2_data), .rd_out(mem_rd), .mem_read_out(mem_mem_read), .mem_write_out(mem_mem_write), .reg_write_out(mem_reg_write), .funct3_out(mem_funct3), .branch_taken_out(mem_branch_taken), .branch_target_out(mem_branch_target));
    
    mem_stage u_mem (.addr(mem_alu_result), .wdata(mem_rs2_data), .mem_read(mem_mem_read), .mem_write(mem_mem_write), .funct3(mem_funct3), .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_rdata(dmem_rdata), .rdata(mem_rdata));
    
    mem_wb_reg u_mem_wb (.clk(clk), .rst_n(rst_n), .alu_result_in(mem_alu_result), .mem_rdata_in(mem_rdata), .rd_in(mem_rd), .mem_read_in(mem_mem_read), .reg_write_in(mem_reg_write), .alu_result_out(wb_alu_result), .mem_rdata_out(wb_mem_rdata), .rd_out(wb_rd), .mem_read_out(wb_mem_read), .reg_write_out(wb_reg_write));
    
    wb_stage u_wb (.alu_result(wb_alu_result), .mem_rdata(wb_mem_rdata), .mem_read(wb_mem_read), .wb_data(wb_data));
    
    assign dbg_pc       = if_pc;
    assign dbg_instr_if = if_instr;
    assign dbg_instr_id = id_instr;
    assign dbg_rd_ex    = ex_rd;
    assign dbg_rd_mem   = mem_rd;
    assign dbg_rd_wb    = wb_rd;
    assign dbg_stall    = stall_haz;
    assign dbg_flush    = branch_taken_ex;

endmodule