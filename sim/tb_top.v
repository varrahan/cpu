`timescale 1ns/1ps

module tb_top;
    reg clk;
    reg rst_n;

    wire        imem_req_valid;
    wire        imem_req_ready;
    wire [31:0] imem_req_addr;
    reg         imem_rsp_valid;
    wire        imem_rsp_ready;
    reg  [31:0] imem_rsp_rdata;
    reg         imem_rsp_error;

    wire        dmem_req_valid;
    wire        dmem_req_ready;
    wire        dmem_req_write;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [3:0]  dmem_req_be;
    wire        dmem_req_amo;
    wire [4:0]  dmem_req_amo_op;
    reg         dmem_rsp_valid;
    wire        dmem_rsp_ready;
    reg  [31:0] dmem_rsp_rdata;
    reg         dmem_rsp_error;

    reg [31:0] imem [0:8191];
    reg [31:0] dmem [0:8191];
    reg [2:0] bus_phase;
    reg inject_imem_error;
    reg inject_dmem_error;
    reg irq_m_software, irq_m_timer, irq_m_external;
    reg irq_s_software, irq_s_timer, irq_s_external, nmi;
    reg debug_req, debug_resume, debug_reg_valid, debug_reg_write;
    reg [5:0] debug_reg_addr;
    reg [63:0] debug_reg_wdata;
    wire debug_reg_ready, debug_halted;
    wire [63:0] debug_reg_rdata;
    wire [31:0] debug_dpc;

    assign imem_req_ready = !imem_rsp_valid && bus_phase[0];
    assign dmem_req_ready = !dmem_rsp_valid && bus_phase[1];

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bus_phase <= 0;
        else bus_phase <= bus_phase + 1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_rsp_valid <= 0;
            imem_rsp_rdata <= 0;
            imem_rsp_error <= 0;
        end else begin
            if (imem_rsp_valid && imem_rsp_ready)
                imem_rsp_valid <= 0;
            if (imem_req_valid && imem_req_ready) begin
                imem_rsp_valid <= 1;
                imem_rsp_rdata <= imem[imem_req_addr[14:2]];
                imem_rsp_error <= inject_imem_error && imem_req_addr == 64;
                if (inject_imem_error && imem_req_addr == 64)
                    inject_imem_error <= 0;
            end
        end
    end

    integer lane;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dmem_rsp_valid <= 0;
            dmem_rsp_rdata <= 0;
            dmem_rsp_error <= 0;
        end else begin
            if (dmem_rsp_valid && dmem_rsp_ready)
                dmem_rsp_valid <= 0;
            if (dmem_req_valid && dmem_req_ready) begin
                dmem_rsp_valid <= 1;
                dmem_rsp_rdata <= dmem[dmem_req_addr[14:2]];
                dmem_rsp_error <= inject_dmem_error && dmem_req_addr == 64;
                if (inject_dmem_error && dmem_req_addr == 64)
                    inject_dmem_error <= 0;
                if (dmem_req_amo &&
                    !(inject_dmem_error && dmem_req_addr == 64)) begin
                    case (dmem_req_amo_op)
                        5'b00010: ; // LR.W
                        5'b00011, 5'b00001:
                            dmem[dmem_req_addr[14:2]] <= dmem_req_wdata;
                        5'b00000: dmem[dmem_req_addr[14:2]] <=
                                  dmem[dmem_req_addr[14:2]] + dmem_req_wdata;
                        5'b00100: dmem[dmem_req_addr[14:2]] <=
                                  dmem[dmem_req_addr[14:2]] ^ dmem_req_wdata;
                        5'b01100: dmem[dmem_req_addr[14:2]] <=
                                  dmem[dmem_req_addr[14:2]] & dmem_req_wdata;
                        5'b01000: dmem[dmem_req_addr[14:2]] <=
                                  dmem[dmem_req_addr[14:2]] | dmem_req_wdata;
                        5'b10000: dmem[dmem_req_addr[14:2]] <=
                                  $signed(dmem[dmem_req_addr[14:2]]) <
                                  $signed(dmem_req_wdata)
                                  ? dmem[dmem_req_addr[14:2]] : dmem_req_wdata;
                        5'b10100: dmem[dmem_req_addr[14:2]] <=
                                  $signed(dmem[dmem_req_addr[14:2]]) >
                                  $signed(dmem_req_wdata)
                                  ? dmem[dmem_req_addr[14:2]] : dmem_req_wdata;
                        5'b11000: dmem[dmem_req_addr[14:2]] <=
                                  dmem[dmem_req_addr[14:2]] < dmem_req_wdata
                                  ? dmem[dmem_req_addr[14:2]] : dmem_req_wdata;
                        5'b11100: dmem[dmem_req_addr[14:2]] <=
                                  dmem[dmem_req_addr[14:2]] > dmem_req_wdata
                                  ? dmem[dmem_req_addr[14:2]] : dmem_req_wdata;
                        default: ;
                    endcase
                    if (dmem_req_amo_op == 5'b00011)
                        dmem_rsp_rdata <= 0;
                end else if (dmem_req_write &&
                    !(inject_dmem_error && dmem_req_addr == 64))
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (dmem_req_be[lane])
                            dmem[dmem_req_addr[14:2]][lane*8 +: 8]
                                <= dmem_req_wdata[lane*8 +: 8];
            end
        end
    end

    top dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .irq_m_software (irq_m_software),
        .irq_m_timer    (irq_m_timer),
        .irq_m_external (irq_m_external),
        .irq_s_software (irq_s_software),
        .irq_s_timer    (irq_s_timer),
        .irq_s_external (irq_s_external),
        .nmi            (nmi),
        .mtime          (64'b0),
        .debug_req      (debug_req),
        .debug_resume   (debug_resume),
        .debug_reg_valid(debug_reg_valid),
        .debug_reg_write(debug_reg_write),
        .debug_reg_addr (debug_reg_addr),
        .debug_reg_wdata(debug_reg_wdata),
        .debug_reg_ready(debug_reg_ready),
        .debug_reg_rdata(debug_reg_rdata),
        .debug_halted   (debug_halted),
        .debug_dpc      (debug_dpc),
        .debug_dpc_write(1'b0), .debug_dpc_wdata(32'b0),
        .debug_step     (1'b0), .debug_privilege(),
        .imem_req_valid (imem_req_valid),
        .imem_req_ready (imem_req_ready),
        .imem_req_addr  (imem_req_addr),
        .imem_rsp_valid (imem_rsp_valid),
        .imem_rsp_ready (imem_rsp_ready),
        .imem_rsp_rdata (imem_rsp_rdata),
        .imem_rsp_error (imem_rsp_error),
        .dmem_req_valid (dmem_req_valid),
        .dmem_req_ready (dmem_req_ready),
        .dmem_req_write (dmem_req_write),
        .dmem_req_addr  (dmem_req_addr),
        .dmem_req_wdata (dmem_req_wdata),
        .dmem_req_be    (dmem_req_be),
        .dmem_req_amo   (dmem_req_amo),
        .dmem_req_amo_op(dmem_req_amo_op),
        .reservation_invalidate(1'b0),
        .dmem_rsp_valid (dmem_rsp_valid),
        .dmem_rsp_ready (dmem_rsp_ready),
        .dmem_rsp_rdata (dmem_rsp_rdata),
        .dmem_rsp_error (dmem_rsp_error)
    );

    integer i;
    integer cycle_count;
    integer stall_count;
    integer flush_count;
    integer dmem_read_request_count;
    integer read_count_before;
    integer program_timeout;

    function automatic [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin enc_r = {funct7, rs2, rs1, funct3, rd, 7'h33}; end
    endfunction

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function automatic [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23}; end
    endfunction

    function automatic [31:0] enc_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], 7'h63};
        end
    endfunction

    function automatic [31:0] enc_u;
        input [19:0] imm;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_u = {imm, rd, opcode}; end
    endfunction

    function automatic [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin
            enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f};
        end
    endfunction

    function automatic [31:0] enc_amo;
        input [4:0] funct5;
        input [4:0] rs2;
        input [4:0] rs1;
        input [4:0] rd;
        begin enc_amo = {funct5, 2'b00, rs2, rs1, 3'b010, rd, 7'h2f}; end
    endfunction

    function automatic [31:0] enc_fp;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] rm;
        input [4:0] rd;
        begin enc_fp = {funct7, rs2, rs1, rm, rd, 7'h53}; end
    endfunction

    function automatic [31:0] enc_fp_store;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_fp_store = {imm[11:5], rs2, rs1, funct3,
                            imm[4:0], 7'h27};
        end
    endfunction

    task clear_memories;
        begin
            for (i = 0; i < 8192; i = i + 1) begin
                imem[i] = 32'h00000013;
                dmem[i] = 0;
            end
        end
    endtask

    task load_fibonacci;
        begin
            imem[0]  = 32'h00000093;
            imem[1]  = 32'h00100113;
            imem[2]  = 32'h00900213;
            imem[3]  = 32'h002081b3;
            imem[4]  = 32'h00010093;
            imem[5]  = 32'h00018113;
            imem[6]  = 32'hfff20213;
            imem[7]  = 32'hfe0218e3;
            imem[8]  = 32'h00000013;
            imem[9]  = 32'h00202023;
            imem[10] = 32'h0000006f;
        end
    endtask

    task load_memory_hazards;
        begin
            imem[0]  = 32'h02a00093;
            imem[1]  = 32'h00102023;
            imem[2]  = 32'h00002103;
            imem[3]  = 32'h00110193;
            imem[4]  = 32'h00302423;
            imem[5]  = 32'hf8000213;
            imem[6]  = 32'h004002a3;
            imem[7]  = 32'h00500283;
            imem[8]  = 32'h00502623;
            imem[9]  = 32'h00504303;
            imem[10] = 32'h00602823;
            imem[11] = 32'h000083b7;
            imem[12] = 32'h00138393;
            imem[13] = 32'h00701323;
            imem[14] = 32'h00601403;
            imem[15] = 32'h00802a23;
            imem[16] = 32'h00605483;
            imem[17] = 32'h00902c23;
            imem[18] = 32'h0000006f;
        end
    endtask

    task load_machine_trap;
        begin
            imem[0]  = 32'h08000093; // addi  x1, x0, 128
            imem[1]  = 32'h30509073; // csrw  mtvec, x1
            imem[2]  = 32'h00100073; // ebreak
            imem[3]  = 32'h06300293; // addi  x5, x0, 99
            imem[4]  = 32'h00502e23; // sw    x5, 28(x0)
            imem[5]  = 32'h0000006f; // jal   x0, 0

            imem[32] = 32'h34202173; // csrr  x2, mcause
            imem[33] = 32'h02202023; // sw    x2, 32(x0)
            imem[34] = 32'h341021f3; // csrr  x3, mepc
            imem[35] = 32'h00418193; // addi  x3, x3, 4
            imem[36] = 32'h34119073; // csrw  mepc, x3
            imem[37] = 32'h30200073; // mret
        end
    endtask

    task load_integer_and_control;
        begin
            imem[0]  = enc_i(-8, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(3, 0, 3'b000, 2, 7'h13);
            imem[2]  = enc_r(7'h00, 2, 1, 3'b000, 3);
            imem[3]  = enc_r(7'h20, 2, 1, 3'b000, 4);
            imem[4]  = enc_i(2, 0, 3'b000, 6, 7'h13);
            imem[5]  = enc_r(7'h00, 6, 2, 3'b001, 5);
            imem[6]  = enc_r(7'h00, 2, 1, 3'b010, 7);
            imem[7]  = enc_r(7'h00, 2, 1, 3'b011, 8);
            imem[8]  = enc_r(7'h00, 2, 1, 3'b100, 9);
            imem[9]  = enc_r(7'h00, 2, 1, 3'b101, 10);
            imem[10] = enc_r(7'h20, 2, 1, 3'b101, 11);
            imem[11] = enc_r(7'h00, 2, 1, 3'b110, 12);
            imem[12] = enc_r(7'h00, 2, 1, 3'b111, 13);
            imem[13] = enc_i(12'h004, 2, 3'b001, 14, 7'h13);
            imem[14] = enc_i(0, 1, 3'b010, 15, 7'h13);
            imem[15] = enc_i(1, 1, 3'b011, 16, 7'h13);
            imem[16] = enc_i(7, 2, 3'b100, 17, 7'h13);
            imem[17] = enc_i(12'h002, 1, 3'b101, 18, 7'h13);
            imem[18] = enc_i(12'h402, 1, 3'b101, 19, 7'h13);
            imem[19] = enc_i(8, 2, 3'b110, 21, 7'h13);
            imem[20] = enc_i(15, 1, 3'b111, 22, 7'h13);
            imem[21] = enc_u(20'h12345, 23, 7'h37);
            imem[22] = enc_u(0, 24, 7'h17);
            imem[23] = enc_i(0, 0, 3'b000, 20, 7'h13);
            imem[24] = enc_b(13'd8, 2, 2, 3'b000);
            imem[25] = enc_i(1, 20, 3'b000, 20, 7'h13);
            imem[26] = enc_b(13'd8, 2, 1, 3'b001);
            imem[27] = enc_i(2, 20, 3'b000, 20, 7'h13);
            imem[28] = enc_b(13'd8, 2, 1, 3'b100);
            imem[29] = enc_i(4, 20, 3'b000, 20, 7'h13);
            imem[30] = enc_b(13'd8, 1, 2, 3'b101);
            imem[31] = enc_i(8, 20, 3'b000, 20, 7'h13);
            imem[32] = enc_b(13'd8, 1, 2, 3'b110);
            imem[33] = enc_i(16, 20, 3'b000, 20, 7'h13);
            imem[34] = enc_b(13'd8, 2, 1, 3'b111);
            imem[35] = enc_i(32, 20, 3'b000, 20, 7'h13);
            imem[36] = enc_j(21'd8, 25);
            imem[37] = enc_i(64, 20, 3'b000, 20, 7'h13);
            imem[38] = enc_i(164, 0, 3'b000, 26, 7'h13);
            imem[39] = enc_i(0, 26, 3'b000, 27, 7'h67);
            imem[40] = enc_i(128, 20, 3'b000, 20, 7'h13);
            imem[41] = enc_s(40, 3, 0, 3'b010);
            imem[42] = enc_s(44, 4, 0, 3'b010);
            imem[43] = enc_s(48, 5, 0, 3'b010);
            imem[44] = enc_s(52, 9, 0, 3'b010);
            imem[45] = enc_s(56, 10, 0, 3'b010);
            imem[46] = enc_s(60, 11, 0, 3'b010);
            imem[47] = enc_s(64, 14, 0, 3'b010);
            imem[48] = enc_s(68, 18, 0, 3'b010);
            imem[49] = enc_s(72, 19, 0, 3'b010);
            imem[50] = enc_s(76, 23, 0, 3'b010);
            imem[51] = enc_s(80, 24, 0, 3'b010);
            imem[52] = enc_s(84, 20, 0, 3'b010);
            imem[53] = enc_s(88, 25, 0, 3'b010);
            imem[54] = enc_s(92, 27, 0, 3'b010);
            imem[55] = enc_i(123, 0, 3'b000, 0, 7'h13);
            imem[56] = enc_s(216, 0, 0, 3'b010);
            imem[57] = enc_j(0, 0);
        end
    endtask

    task load_csr_operations;
        begin
            imem[0]  = enc_i(12'h055, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h340, 1, 3'b001, 2, 7'h73);
            imem[2]  = enc_i(12'h340, 0, 3'b010, 3, 7'h73);
            imem[3]  = enc_i(12'h00f, 0, 3'b000, 4, 7'h13);
            imem[4]  = enc_i(12'h340, 4, 3'b011, 5, 7'h73);
            imem[5]  = enc_i(12'h340, 3, 3'b101, 6, 7'h73);
            imem[6]  = enc_i(12'h340, 4, 3'b110, 7, 7'h73);
            imem[7]  = enc_i(12'h340, 1, 3'b111, 8, 7'h73);
            imem[8]  = enc_i(12'h340, 0, 3'b010, 9, 7'h73);
            imem[9]  = 32'h0000_000f;
            imem[10] = 32'h0000_0013;
            imem[11] = enc_s(96, 2, 0, 3'b010);
            imem[12] = enc_s(100, 3, 0, 3'b010);
            imem[13] = enc_s(104, 5, 0, 3'b010);
            imem[14] = enc_s(108, 6, 0, 3'b010);
            imem[15] = enc_s(112, 7, 0, 3'b010);
            imem[16] = enc_s(116, 8, 0, 3'b010);
            imem[17] = enc_s(120, 9, 0, 3'b010);
            imem[18] = enc_j(0, 0);
        end
    endtask

    task load_synchronous_traps;
        begin
            imem[0]  = enc_i(128, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h305, 1, 3'b001, 0, 7'h73);
            imem[2]  = enc_i(128, 0, 3'b000, 10, 7'h13);
            imem[3]  = 32'hffff_ffff;
            imem[4]  = 32'h0000_0073;
            imem[5]  = enc_i(1, 0, 3'b010, 3, 7'h03);
            imem[6]  = enc_s(2, 0, 0, 3'b010);
            imem[7]  = enc_i(77, 0, 3'b000, 4, 7'h13);
            imem[8]  = enc_s(192, 4, 0, 3'b010);
            imem[9]  = enc_j(0, 0);

            imem[32] = enc_i(12'h342, 0, 3'b010, 2, 7'h73);
            imem[33] = enc_s(0, 2, 10, 3'b010);
            imem[34] = enc_i(12'h343, 0, 3'b010, 3, 7'h73);
            imem[35] = enc_s(32, 3, 10, 3'b010);
            imem[36] = enc_i(4, 10, 3'b000, 10, 7'h13);
            imem[37] = enc_i(12'h341, 0, 3'b010, 4, 7'h73);
            imem[38] = enc_i(4, 4, 3'b000, 4, 7'h13);
            imem[39] = enc_i(12'h341, 4, 3'b001, 0, 7'h73);
            imem[40] = 32'h3020_0073;
        end
    endtask

    task load_data_access_fault;
        begin
            imem[0]  = enc_i(128, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h305, 1, 3'b001, 0, 7'h73);
            imem[2]  = enc_i(64, 0, 3'b010, 2, 7'h03);
            imem[3]  = enc_i(77, 0, 3'b000, 5, 7'h13);
            imem[4]  = enc_s(200, 5, 0, 3'b010);
            imem[5]  = enc_j(0, 0);
            imem[32] = enc_i(12'h342, 0, 3'b010, 3, 7'h73);
            imem[33] = enc_s(204, 3, 0, 3'b010);
            imem[34] = enc_i(12'h341, 0, 3'b010, 4, 7'h73);
            imem[35] = enc_i(4, 4, 3'b000, 4, 7'h13);
            imem[36] = enc_i(12'h341, 4, 3'b001, 0, 7'h73);
            imem[37] = 32'h3020_0073;
        end
    endtask

    task load_instruction_access_fault;
        begin
            imem[0]  = enc_i(128, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h305, 1, 3'b001, 0, 7'h73);
            imem[2]  = enc_j(21'd56, 0);
            imem[17] = enc_i(77, 0, 3'b000, 5, 7'h13);
            imem[18] = enc_s(208, 5, 0, 3'b010);
            imem[19] = enc_j(0, 0);
            imem[32] = enc_i(12'h342, 0, 3'b010, 3, 7'h73);
            imem[33] = enc_s(212, 3, 0, 3'b010);
            imem[34] = enc_i(12'h341, 0, 3'b010, 4, 7'h73);
            imem[35] = enc_i(4, 4, 3'b000, 4, 7'h13);
            imem[36] = enc_i(12'h341, 4, 3'b001, 0, 7'h73);
            imem[37] = 32'h3020_0073;
        end
    endtask

    task load_store_access_fault;
        begin
            imem[0]  = enc_i(128, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h305, 1, 3'b001, 0, 7'h73);
            imem[2]  = enc_i(55, 0, 3'b000, 2, 7'h13);
            imem[3]  = enc_s(64, 2, 0, 3'b010);
            imem[4]  = enc_i(77, 0, 3'b000, 5, 7'h13);
            imem[5]  = enc_s(216, 5, 0, 3'b010);
            imem[6]  = enc_j(0, 0);
            imem[32] = enc_i(12'h342, 0, 3'b010, 3, 7'h73);
            imem[33] = enc_s(220, 3, 0, 3'b010);
            imem[34] = enc_i(12'h341, 0, 3'b010, 4, 7'h73);
            imem[35] = enc_i(4, 4, 3'b000, 4, 7'h13);
            imem[36] = enc_i(12'h341, 4, 3'b001, 0, 7'h73);
            imem[37] = 32'h3020_0073;
        end
    endtask

    task load_cache_conflicts;
        begin
            imem[0] = enc_i(0, 0, 3'b010, 1, 7'h03);
            imem[1] = enc_i(4, 0, 3'b010, 4, 7'h03);
            imem[2] = enc_i(256, 0, 3'b000, 5, 7'h13);
            imem[3] = enc_i(0, 5, 3'b010, 2, 7'h03);
            imem[4] = enc_i(0, 0, 3'b010, 3, 7'h03);
            imem[5] = enc_s(224, 1, 0, 3'b010);
            imem[6] = enc_s(228, 4, 0, 3'b010);
            imem[7] = enc_s(232, 2, 0, 3'b010);
            imem[8] = enc_s(236, 3, 0, 3'b010);
            imem[9] = enc_j(0, 0);
        end
    endtask

    task load_rv32m;
        begin
            imem[0]  = enc_i(-7, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(3, 0, 3'b000, 2, 7'h13);
            imem[2]  = enc_r(7'h01, 2, 1, 3'b000, 3);
            imem[3]  = enc_r(7'h01, 2, 1, 3'b001, 4);
            imem[4]  = enc_r(7'h01, 2, 1, 3'b010, 5);
            imem[5]  = enc_r(7'h01, 2, 1, 3'b011, 6);
            imem[6]  = enc_r(7'h01, 2, 1, 3'b100, 7);
            imem[7]  = enc_r(7'h01, 2, 1, 3'b101, 8);
            imem[8]  = enc_r(7'h01, 2, 1, 3'b110, 9);
            imem[9]  = enc_r(7'h01, 2, 1, 3'b111, 10);
            imem[10] = enc_s(0, 3, 0, 3'b010);
            imem[11] = enc_s(4, 4, 0, 3'b010);
            imem[12] = enc_s(8, 5, 0, 3'b010);
            imem[13] = enc_s(12, 6, 0, 3'b010);
            imem[14] = enc_s(16, 7, 0, 3'b010);
            imem[15] = enc_s(20, 8, 0, 3'b010);
            imem[16] = enc_s(24, 9, 0, 3'b010);
            imem[17] = enc_s(28, 10, 0, 3'b010);
            imem[18] = enc_j(0, 0);
        end
    endtask

    task load_rv32a;
        begin
            imem[0]  = enc_i(64, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(10, 0, 3'b000, 2, 7'h13);
            imem[2]  = enc_s(0, 2, 1, 3'b010);
            imem[3]  = enc_i(5, 0, 3'b000, 2, 7'h13);
            imem[4]  = enc_amo(5'b00010, 0, 1, 4); // LR.W
            imem[5]  = enc_amo(5'b00011, 2, 1, 5); // SC.W succeeds
            imem[6]  = enc_amo(5'b00011, 2, 1, 6); // SC.W fails
            imem[7]  = enc_amo(5'b00000, 2, 1, 7); // AMOADD.W
            imem[8]  = enc_i(0, 1, 3'b010, 8, 7'h03);
            imem[9]  = enc_s(0, 4, 0, 3'b010);
            imem[10] = enc_s(4, 5, 0, 3'b010);
            imem[11] = enc_s(8, 6, 0, 3'b010);
            imem[12] = enc_s(12, 7, 0, 3'b010);
            imem[13] = enc_s(16, 8, 0, 3'b010);
            imem[14] = enc_j(0, 0);
        end
    endtask

    task load_rv32fd;
        begin
            dmem[16] = 32'h3fc0_0000; // 1.5f
            dmem[17] = 32'h4010_0000; // 2.25f
            dmem[18] = 32'h0000_0000; // 1.5 double, low
            dmem[19] = 32'h3ff8_0000;
            dmem[20] = 32'h0000_0000; // 2.25 double, low
            dmem[21] = 32'h4002_0000;
            imem[0]  = enc_i(64, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(0, 1, 3'b010, 1, 7'h07);   // FLW f1,0(x1)
            imem[2]  = enc_i(4, 1, 3'b010, 2, 7'h07);   // FLW f2,4(x1)
            imem[3]  = enc_fp(7'b0000000, 2, 1, 0, 3); // FADD.S
            imem[4]  = enc_fp_store(0, 3, 0, 3'b010);   // FSW f3,0
            imem[5]  = enc_fp(7'b0001000, 2, 1, 0, 4); // FMUL.S
            imem[6]  = enc_fp_store(4, 4, 0, 3'b010);   // FSW f4,4
            imem[7]  = enc_fp(7'b1100000, 0, 3, 1, 5); // FCVT.W.S RTZ
            imem[8]  = enc_s(8, 5, 0, 3'b010);
            imem[9]  = enc_i(8, 1, 3'b011, 5, 7'h07);   // FLD f5,8(x1)
            imem[10] = enc_i(16, 1, 3'b011, 6, 7'h07);  // FLD f6,16(x1)
            imem[11] = enc_fp(7'b0000001, 6, 5, 0, 7); // FADD.D
            imem[12] = enc_fp_store(16, 7, 0, 3'b011);  // FSD f7,16
            imem[13] = enc_fp(7'b0100000, 1, 7, 0, 8); // FCVT.S.D
            imem[14] = enc_fp_store(24, 8, 0, 3'b010);  // FSW f8,24
            imem[15] = enc_fp(7'b1111000, 0, 0, 0, 9); // FMV.W.X f9,x0
            imem[16] = enc_fp(7'b0001100, 9, 1, 0, 10);// FDIV.S by zero
            imem[17] = enc_i(12'h001, 0, 3'b010, 6, 7'h73);
            imem[18] = enc_s(28, 6, 0, 3'b010);
            imem[19] = enc_j(0, 0);
        end
    endtask

    task load_machine_interrupt;
        begin
            imem[0]  = enc_i(129, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h305, 1, 3'b001, 0, 7'h73); // mtvec vectored
            imem[2]  = enc_i(-2048, 0, 3'b000, 1, 7'h13);
            imem[3]  = enc_i(12'h304, 1, 3'b001, 0, 7'h73); // MEIE
            imem[4]  = enc_i(8, 0, 3'b000, 1, 7'h13);
            imem[5]  = enc_i(12'h300, 1, 3'b010, 0, 7'h73); // MIE
            imem[6]  = enc_i(42, 0, 3'b000, 5, 7'h13);
            imem[7]  = enc_s(0, 5, 0, 3'b010);
            imem[8]  = enc_j(0, 0);
            imem[43] = enc_i(12'h342, 0, 3'b010, 2, 7'h73);
            imem[44] = enc_s(4, 2, 0, 3'b010);
            imem[45] = enc_i(12'h341, 0, 3'b010, 3, 7'h73);
            imem[46] = enc_s(8, 3, 0, 3'b010);
            imem[47] = 32'h3020_0073;
        end
    endtask

    task load_supervisor_user;
        begin
            imem[0]  = enc_i(-1, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h3b0, 1, 3'b001, 0, 7'h73);
            imem[2]  = enc_i(15, 0, 3'b000, 1, 7'h13);
            imem[3]  = enc_i(12'h3a0, 1, 3'b001, 0, 7'h73);
            imem[4]  = enc_i(128, 0, 3'b000, 1, 7'h13);
            imem[5]  = enc_i(12'h105, 1, 3'b001, 0, 7'h73);
            imem[6]  = enc_i(256, 0, 3'b000, 1, 7'h13);
            imem[7]  = enc_i(12'h302, 1, 3'b001, 0, 7'h73);
            imem[8]  = enc_u(20'h00001, 1, 7'h37);
            imem[9]  = enc_i(-2048, 1, 3'b000, 1, 7'h13);
            imem[10] = enc_i(12'h300, 1, 3'b001, 0, 7'h73);
            imem[11] = enc_i(64, 0, 3'b000, 1, 7'h13);
            imem[12] = enc_i(12'h341, 1, 3'b001, 0, 7'h73);
            imem[13] = 32'h3020_0073;
            imem[16] = enc_i(96, 0, 3'b000, 1, 7'h13);
            imem[17] = enc_i(12'h141, 1, 3'b001, 0, 7'h73);
            imem[18] = 32'h1020_0073;
            imem[24] = enc_i(77, 0, 3'b000, 5, 7'h13);
            imem[25] = enc_s(0, 5, 0, 3'b010);
            imem[26] = 32'h0000_0073;
            imem[27] = enc_i(99, 0, 3'b000, 6, 7'h13);
            imem[28] = enc_s(8, 6, 0, 3'b010);
            imem[29] = enc_j(0, 0);
            imem[32] = enc_i(12'h142, 0, 3'b010, 2, 7'h73);
            imem[33] = enc_s(4, 2, 0, 3'b010);
            imem[34] = enc_i(12'h141, 0, 3'b010, 3, 7'h73);
            imem[35] = enc_i(4, 3, 3'b000, 3, 7'h13);
            imem[36] = enc_i(12'h141, 3, 3'b001, 0, 7'h73);
            imem[37] = 32'h1020_0073;
        end
    endtask

    task load_sv32_system;
        begin
            dmem[1025] = 32'h0000_0801; // root VPN1=1 -> table PPN 2
            dmem[1026] = 32'h0000_1401; // root VPN1=2 -> table PPN 5
            dmem[2048] = 32'h0000_0c0b; // VA 0x00400000 -> PA 0x3000 RX
            dmem[5120] = 32'h0000_1007; // VA 0x00800000 -> PA 0x4000 RW
            imem[0]  = enc_i(-1, 0, 3'b000, 1, 7'h13);
            imem[1]  = enc_i(12'h3b0, 1, 3'b001, 0, 7'h73);
            imem[2]  = enc_i(15, 0, 3'b000, 1, 7'h13);
            imem[3]  = enc_i(12'h3a0, 1, 3'b001, 0, 7'h73);
            imem[4]  = enc_u(20'h80000, 1, 7'h37);
            imem[5]  = enc_i(1, 1, 3'b000, 1, 7'h13);
            imem[6]  = enc_i(12'h180, 1, 3'b001, 0, 7'h73);
            imem[7]  = enc_u(20'h00001, 1, 7'h37);
            imem[8]  = enc_i(-2048, 1, 3'b000, 1, 7'h13);
            imem[9]  = enc_i(12'h300, 1, 3'b001, 0, 7'h73);
            imem[10] = enc_u(20'h00400, 1, 7'h37);
            imem[11] = enc_i(12'h341, 1, 3'b001, 0, 7'h73);
            imem[12] = 32'h1200_0073; // SFENCE.VMA
            imem[13] = 32'h3020_0073; // MRET
            imem[3072] = enc_u(20'h00800, 2, 7'h37);
            imem[3073] = enc_i(123, 0, 3'b000, 3, 7'h13);
            imem[3074] = enc_s(0, 3, 2, 3'b010);
            imem[3075] = enc_i(0, 2, 3'b010, 4, 7'h03);
            imem[3076] = enc_s(4, 4, 2, 3'b010);
            imem[3077] = enc_j(0, 0);
        end
    endtask

    task load_compressed_system;
        begin
            imem[0] = 32'h0085_4081; // C.LI x1,0; C.ADDI x1,1
            imem[1] = 32'h0001_0085; // C.ADDI x1,1; C.NOP
            imem[2] = 32'h0010_2023; // SW x1,0(x0)
            imem[3] = 32'h0113_0001; // C.NOP; low half of ADDI x2,5
            imem[4] = 32'h2223_0050; // ADDI high; low half of SW x2,4
            imem[5] = 32'ha001_0020; // SW high; C.J 0
        end
    endtask

    task load_wfi_interrupt;
        begin
            imem[0] = enc_i(128, 0, 3'b000, 1, 7'h13);
            imem[1] = enc_i(12'h305, 1, 3'b001, 0, 7'h73);
            imem[2] = enc_i(-2048, 0, 3'b000, 1, 7'h13);
            imem[3] = enc_i(12'h304, 1, 3'b001, 0, 7'h73);
            imem[4] = enc_i(8, 0, 3'b000, 1, 7'h13);
            imem[5] = enc_i(12'h300, 1, 3'b010, 0, 7'h73);
            imem[6] = 32'h1050_0073;
            imem[7] = enc_i(66, 0, 3'b000, 2, 7'h13);
            imem[8] = enc_s(0, 2, 0, 3'b010);
            imem[9] = enc_j(0, 0);
            imem[32] = enc_i(12'h342, 0, 3'b010, 3, 7'h73);
            imem[33] = enc_s(4, 3, 0, 3'b010);
            imem[34] = 32'h3020_0073;
        end
    endtask

    task load_wfi_masked_interrupt;
        begin
            imem[0] = enc_i(-2048, 0, 3'b000, 1, 7'h13);
            imem[1] = enc_i(12'h304, 1, 3'b001, 0, 7'h73); // MEIE, MIE=0
            imem[2] = 32'h1050_0073;
            imem[3] = enc_i(67, 0, 3'b000, 2, 7'h13);
            imem[4] = enc_s(0, 2, 0, 3'b010);
            imem[5] = enc_j(0, 0);
        end
    endtask

    task load_rv32gc_stress;
        begin
            $readmemh("build/programs/rv32gc_stress.hex", imem);
        end
    endtask

    task reset_cpu;
        begin
            rst_n = 0;
            repeat (3) @(posedge clk);
            rst_n = 1;
        end
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
`ifndef NETLIST_SIM
            if (dut.stall_haz) stall_count = stall_count + 1;
            if (dut.branch_mispredict_ex) flush_count = flush_count + 1;
`endif
        end
    end

    always @(posedge clk)
        if (rst_n && dmem_req_valid && dmem_req_ready && !dmem_req_write)
            dmem_read_request_count = dmem_read_request_count + 1;

    initial begin
        $dumpfile("build/top_wave.vcd");
        $dumpvars(0, tb_top);
        cycle_count = 0;
        stall_count = 0;
        flush_count = 0;
        inject_imem_error = 0;
        inject_dmem_error = 0;
        irq_m_software = 0;
        irq_m_timer = 0;
        irq_m_external = 0;
        irq_s_software = 0;
        irq_s_timer = 0;
        irq_s_external = 0;
        nmi = 0;
        debug_req = 0;
        debug_resume = 0;
        debug_reg_valid = 0;
        debug_reg_write = 0;
        debug_reg_addr = 0;
        debug_reg_wdata = 0;
        dmem_read_request_count = 0;
        rst_n = 0;

        clear_memories();
        load_fibonacci();
        reset_cpu();
        repeat (300) @(posedge clk);

        if (dmem[0] != 32'd55)
            $fatal(1, "Fibonacci: got %0d, expected 55", dmem[0]);
        rst_n = 0;
        clear_memories();
        load_memory_hazards();
        reset_cpu();
        repeat (300) @(posedge clk);

        if (dmem[2] != 32'd43 || dmem[3] != 32'hffff_ff80 ||
            dmem[4] != 32'h0000_0080 || dmem[5] != 32'hffff_8001 ||
            dmem[6] != 32'h0000_8001)
            $fatal(1, "Memory/hazard failure: %h %h %h %h %h",
                   dmem[2], dmem[3], dmem[4], dmem[5], dmem[6]);

        rst_n = 0;
        clear_memories();
        load_machine_trap();
        reset_cpu();
        repeat (300) @(posedge clk);

        if (dmem[8] != 32'd3 || dmem[7] != 32'd99)
            $fatal(1, "Machine trap failure: mcause=%0d marker=%0d",
                   dmem[8], dmem[7]);

        rst_n = 0;
        clear_memories();
        load_integer_and_control();
        reset_cpu();
        repeat (1200) @(posedge clk);

        if (dmem[10] != 32'hffff_fffb || dmem[11] != 32'hffff_fff5 ||
            dmem[12] != 32'd12 || dmem[13] != 32'hffff_fffb ||
            dmem[14] != 32'h1fff_ffff || dmem[15] != 32'hffff_ffff ||
            dmem[16] != 32'd48 || dmem[17] != 32'h3fff_fffe ||
            dmem[18] != 32'hffff_fffe || dmem[19] != 32'h1234_5000 ||
            dmem[20] != 32'd88 || dmem[21] != 0 ||
            dmem[22] != 32'd148 || dmem[23] != 32'd160 || dmem[54] != 0)
            $fatal(1, "Integer/control regression failure");

        rst_n = 0;
        clear_memories();
        load_csr_operations();
        reset_cpu();
        repeat (700) @(posedge clk);

        if (dmem[24] != 0 || dmem[25] != 32'h55 || dmem[26] != 32'h55 ||
            dmem[27] != 32'h50 || dmem[28] != 3 || dmem[29] != 7 ||
            dmem[30] != 6)
            $fatal(1, "Zicsr regression failure: %h %h %h %h %h %h %h",
                   dmem[24], dmem[25], dmem[26], dmem[27], dmem[28],
                   dmem[29], dmem[30]);

        rst_n = 0;
        clear_memories();
        load_synchronous_traps();
        reset_cpu();
        repeat (1200) @(posedge clk);

        if (dmem[32] != 2 || dmem[33] != 11 || dmem[34] != 4 ||
            dmem[35] != 6 || dmem[40] != 32'hffff_ffff ||
            dmem[41] != 0 || dmem[42] != 1 || dmem[43] != 2 ||
            dmem[48] != 77)
            $fatal(1, "Synchronous trap regression failure");

        rst_n = 0;
        clear_memories();
        load_data_access_fault();
        inject_dmem_error = 1;
        reset_cpu();
        repeat (700) @(posedge clk);

        if (dmem[50] != 77 || dmem[51] != 5)
            $fatal(1, "Data access-fault regression failure");

        rst_n = 0;
        clear_memories();
        load_instruction_access_fault();
        inject_imem_error = 1;
        reset_cpu();
        repeat (700) @(posedge clk);

        if (dmem[52] != 77 || dmem[53] != 1)
            $fatal(1, "Instruction access-fault regression failure");

        rst_n = 0;
        clear_memories();
        load_store_access_fault();
        inject_dmem_error = 1;
        reset_cpu();
        repeat (700) @(posedge clk);

        if (dmem[16] != 0 || dmem[54] != 77 || dmem[55] != 7)
            $fatal(1, "Store access-fault regression failure");

        rst_n = 0;
        clear_memories();
        load_cache_conflicts();
        dmem[0] = 11;
        dmem[1] = 12;
        dmem[64] = 22;
        read_count_before = dmem_read_request_count;
        reset_cpu();
        repeat (700) @(posedge clk);

        if (dmem[56] != 11 || dmem[57] != 12 ||
            dmem[58] != 22 || dmem[59] != 11 ||
            dmem_read_request_count - read_count_before != 12)
            $fatal(1, "D-cache hit/conflict regression failure");

        rst_n = 0;
        clear_memories();
        load_rv32m();
        reset_cpu();
        repeat (700) @(posedge clk);

        if (dmem[0] != 32'hffff_ffeb || dmem[1] != 32'hffff_ffff ||
            dmem[2] != 32'hffff_ffff || dmem[3] != 2 ||
            dmem[4] != 32'hffff_fffe || dmem[5] != 32'h5555_5553 ||
            dmem[6] != 32'hffff_ffff || dmem[7] != 0)
            $fatal(1, "RV32M regression failure");

        rst_n = 0;
        clear_memories();
        load_rv32a();
        reset_cpu();
        repeat (700) @(posedge clk);

        if (dmem[0] != 10 || dmem[1] != 0 || dmem[2] != 1 ||
            dmem[3] != 5 || dmem[4] != 10 || dmem[16] != 10)
            $fatal(1, "RV32A regression failure");

        rst_n = 0;
        clear_memories();
        load_rv32fd();
        reset_cpu();
        repeat (1400) @(posedge clk);

        if (dmem[0] != 32'h4070_0000 || dmem[1] != 32'h4058_0000 ||
            dmem[2] != 3 || dmem[4] != 0 || dmem[5] != 32'h400e_0000 ||
            dmem[6] != 32'h4070_0000 || !(dmem[7] & 32'h8))
            $fatal(1, "RV32F/D regression failure: %h %h %h %h %h %h %h",
                   dmem[0], dmem[1], dmem[2], dmem[4], dmem[5], dmem[6],
                   dmem[7]);

        rst_n = 0;
        clear_memories();
        load_machine_interrupt();
        reset_cpu();
        repeat (250) @(posedge clk);
        irq_m_external = 1;
        repeat (250) @(posedge clk);
        irq_m_external = 0;
        repeat (350) @(posedge clk);

        if (dmem[0] != 42 || dmem[1] != 32'h8000_000b ||
            dmem[2][0] != 0)
            $fatal(1, "Machine interrupt regression failure: %h %h %h",
                   dmem[0], dmem[1], dmem[2]);

        rst_n = 0;
        clear_memories();
        load_supervisor_user();
        reset_cpu();
        repeat (1400) @(posedge clk);

        if (dmem[0] != 77 || dmem[1] != 8 || dmem[2] != 99)
            $fatal(1, "Supervisor/user regression failure: %h %h %h",
                   dmem[0], dmem[1], dmem[2]);

        rst_n = 0;
        clear_memories();
        load_sv32_system();
        reset_cpu();
        repeat (2400) @(posedge clk);

        if (dmem[4096] != 123 || dmem[4097] != 123 ||
            !dmem[2048][6] || dmem[5120][7:6] != 2'b11)
            $fatal(1, "Sv32 system regression failure: %h %h %h %h",
                   dmem[4096], dmem[4097], dmem[2048], dmem[5120]);

        rst_n = 0;
        clear_memories();
        imem[0] = enc_i(1, 0, 3'b000, 1, 7'h13);
        imem[1] = enc_i(1, 1, 3'b000, 1, 7'h13);
        imem[2] = enc_j(0, 0);
        reset_cpu();
        repeat (200) @(posedge clk);
        debug_req = 1;
        repeat (20) @(posedge clk);
        debug_req = 0;
        if (!debug_halted || debug_dpc[0])
            $fatal(1, "Debug halt regression failure");
        debug_reg_addr = 10;
        debug_reg_wdata = 64'h55;
        debug_reg_write = 1;
        debug_reg_valid = 1;
        @(posedge clk); #1;
        debug_reg_write = 0;
        if (!debug_reg_ready || debug_reg_rdata[31:0] != 32'h55)
            $fatal(1, "Debug abstract register regression failure");
        debug_reg_valid = 0;
        debug_resume = 1;
        @(posedge clk); #1;
        debug_resume = 0;
        if (debug_halted) $fatal(1, "Debug resume regression failure");

        rst_n = 0;
        clear_memories();
        load_compressed_system();
        reset_cpu();
        repeat (700) @(posedge clk);
        if (dmem[0] != 2 || dmem[1] != 5)
            $fatal(1, "Compressed/cross-word regression failure: %h %h",
                   dmem[0], dmem[1]);

        rst_n = 0;
        clear_memories();
        load_wfi_interrupt();
        reset_cpu();
        repeat (300) @(posedge clk);
        irq_m_external = 1;
        repeat (200) @(posedge clk);
        irq_m_external = 0;
        repeat (400) @(posedge clk);
        if (dmem[0] != 66 || dmem[1] != 32'h8000_000b)
            $fatal(1, "WFI wake regression failure: %h %h",
                   dmem[0], dmem[1]);

        rst_n = 0;
        clear_memories();
        load_wfi_masked_interrupt();
        reset_cpu();
        repeat (300) @(posedge clk);
        if (dmem[0] != 0)
            $fatal(1, "WFI did not sleep before masked interrupt");
        irq_m_external = 1;
        repeat (200) @(posedge clk);
        irq_m_external = 0;
        repeat (200) @(posedge clk);
        if (dmem[0] != 67)
            $fatal(1, "WFI ignored masked pending interrupt");

        rst_n = 0;
        clear_memories();
        load_rv32gc_stress();
        reset_cpu();
        program_timeout = 0;
        while (dmem[256] != 32'h600d_600d && program_timeout < 12000) begin
            @(posedge clk);
            program_timeout = program_timeout + 1;
        end
        if (dmem[256] != 32'h600d_600d)
            $fatal(1, "RV32GC stress program timed out");
        $display("PASS: RV32GC stress program completed in %0d cycles",
                 program_timeout);
        if (dmem[257] != 32'h8d94_4133 || dmem[258] != 32'h7f20_9540 ||
            dmem[259] != 32'h25fc_f0ad || dmem[260] != 21 ||
            dmem[261] != 8 || dmem[262] != 32'h4a ||
            dmem[263] != 32'h126 || dmem[264] != 32'hc03d_3ad1 ||
            dmem[265] != 32'h4170_0000 || dmem[266] != 32'h4080_0000 ||
            dmem[268] != 0 || dmem[269] != 32'h402e_0000 ||
            dmem[270] != 32'h5555_5555 || dmem[271] != 32'h3ff5_5555 ||
            dmem[276] != 32'h4000_0000 || dmem[278] != 0 ||
            dmem[279] != 32'h401c_0000 || dmem[280] != 32'h40 ||
            dmem[281] != 32'haaaa_aabb || dmem[282] != 32'h0005_105e)
            $fatal(1, "RV32GC stress signature failure");

        $display("PASS: cached handshaked RV32GC privileged regression complete");
        $finish;
    end
endmodule
