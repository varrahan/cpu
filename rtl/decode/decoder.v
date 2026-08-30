module decoder (
    input  wire [31:0] instr,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output reg  [31:0] imm,
    output reg  [3:0]  alu_op,
    output reg         alu_src,
    output reg         mem_read,
    output reg         mem_write,
    output reg         reg_write,
    output reg         branch,
    output reg         jal,
    output reg         jalr,
    output wire [2:0]  funct3,
    output reg         lui,
    output reg         auipc,
    output reg         uses_rs1,
    output reg         uses_rs2,
    output reg         illegal,
    output reg         fence,
    output reg         fence_i,
    output reg         muldiv,
    output reg  [2:0]  muldiv_op,
    output reg         amo,
    output reg  [4:0]  amo_op,
    output reg         fp_compute,
    output reg         fp_load,
    output reg         fp_store,
    output reg         fp_uses_rs1,
    output reg         fp_uses_rs2,
    output reg         fp_uses_rs3,
    output reg         csr_en,
    output reg  [1:0]  csr_cmd,
    output reg         csr_imm,
    output reg         ecall,
    output reg         ebreak,
    output reg         mret,
    output reg         sret,
    output reg         sfence_vma,
    output reg         wfi
);
    wire [6:0] opcode = instr[6:0];
    wire [6:0] funct7 = instr[31:25];

    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];

    always @(*) begin
        imm       = 0;
        alu_op    = 0;
        alu_src   = 0;
        mem_read  = 0;
        mem_write = 0;
        reg_write = 0;
        branch    = 0;
        jal       = 0;
        jalr      = 0;
        lui       = 0;
        auipc     = 0;
        uses_rs1  = 0;
        uses_rs2  = 0;
        illegal   = 0;
        fence     = 0;
        fence_i   = 0;
        muldiv    = 0;
        muldiv_op = 0;
        amo       = 0;
        amo_op    = 0;
        fp_compute = 0;
        fp_load   = 0;
        fp_store  = 0;
        fp_uses_rs1 = 0;
        fp_uses_rs2 = 0;
        fp_uses_rs3 = 0;
        csr_en    = 0;
        csr_cmd   = 0;
        csr_imm   = 0;
        ecall     = 0;
        ebreak    = 0;
        mret      = 0;
        sret      = 0;
        sfence_vma = 0;
        wfi       = 0;

        case (opcode)
            7'b0110011: begin
                uses_rs1 = 1;
                uses_rs2 = 1;
                reg_write = 1;
                if (funct7 == 7'b0000001) begin
                    muldiv = 1;
                    muldiv_op = funct3;
                end else begin
                    case ({funct7, funct3})
                        10'b0000000_000: alu_op = 4'b0000;
                        10'b0100000_000: alu_op = 4'b0001;
                        10'b0000000_001: alu_op = 4'b0010;
                        10'b0000000_010: alu_op = 4'b0011;
                        10'b0000000_011: alu_op = 4'b0100;
                        10'b0000000_100: alu_op = 4'b0101;
                        10'b0000000_101: alu_op = 4'b0110;
                        10'b0100000_101: alu_op = 4'b0111;
                        10'b0000000_110: alu_op = 4'b1000;
                        10'b0000000_111: alu_op = 4'b1001;
                        default: begin illegal = 1; reg_write = 0; end
                    endcase
                end
            end
            7'b0010011: begin
                imm       = {{20{instr[31]}}, instr[31:20]};
                uses_rs1  = 1;
                alu_src   = 1;
                reg_write = 1;
                case (funct3)
                    3'b000: alu_op = 4'b0000;
                    3'b010: alu_op = 4'b0011;
                    3'b011: alu_op = 4'b0100;
                    3'b100: alu_op = 4'b0101;
                    3'b110: alu_op = 4'b1000;
                    3'b111: alu_op = 4'b1001;
                    3'b001: begin
                        alu_op = 4'b0010;
                        if (funct7 != 7'b0000000) illegal = 1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) alu_op = 4'b0110;
                        else if (funct7 == 7'b0100000) alu_op = 4'b0111;
                        else illegal = 1;
                    end
                    default: illegal = 1;
                endcase
                if (illegal) reg_write = 0;
            end
            7'b0000011: begin
                imm       = {{20{instr[31]}}, instr[31:20]};
                uses_rs1  = 1;
                alu_src   = 1;
                mem_read  = 1;
                reg_write = 1;
                if (!(funct3 == 3'b000 || funct3 == 3'b001 ||
                      funct3 == 3'b010 || funct3 == 3'b100 ||
                      funct3 == 3'b101)) begin
                    illegal = 1;
                    mem_read = 0;
                    reg_write = 0;
                end
            end
            7'b0100011: begin
                imm       = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                uses_rs1  = 1;
                uses_rs2  = 1;
                alu_src   = 1;
                mem_write = 1;
                if (!(funct3 == 3'b000 || funct3 == 3'b001 ||
                      funct3 == 3'b010)) begin
                    illegal = 1;
                    mem_write = 0;
                end
            end
            7'b1100011: begin
                imm      = {{19{instr[31]}}, instr[31], instr[7],
                            instr[30:25], instr[11:8], 1'b0};
                uses_rs1 = 1;
                uses_rs2 = 1;
                branch   = 1;
                if (!(funct3 == 3'b000 || funct3 == 3'b001 ||
                      funct3 == 3'b100 || funct3 == 3'b101 ||
                      funct3 == 3'b110 || funct3 == 3'b111)) begin
                    illegal = 1;
                    branch = 0;
                end
            end
            7'b1101111: begin
                imm       = {{11{instr[31]}}, instr[31], instr[19:12],
                             instr[20], instr[30:21], 1'b0};
                jal       = 1;
                reg_write = 1;
            end
            7'b1100111: begin
                imm       = {{20{instr[31]}}, instr[31:20]};
                uses_rs1  = 1;
                alu_src   = 1;
                jalr      = 1;
                reg_write = 1;
                if (funct3 != 3'b000) begin
                    illegal = 1;
                    jalr = 0;
                    reg_write = 0;
                end
            end
            7'b0110111: begin
                imm       = {instr[31:12], 12'b0};
                lui       = 1;
                alu_src   = 1;
                reg_write = 1;
            end
            7'b0010111: begin
                imm       = {instr[31:12], 12'b0};
                auipc     = 1;
                alu_src   = 1;
                reg_write = 1;
            end
            7'b0001111: begin
                if (funct3 == 3'b000) fence = 1;
                else if (funct3 == 3'b001) fence_i = 1;
                else illegal = 1;
            end
            7'b0000111: begin
                imm       = {{20{instr[31]}}, instr[31:20]};
                uses_rs1  = 1;
                alu_src   = 1;
                fp_load   = 1;
                if (!(funct3 == 3'b010 || funct3 == 3'b011)) begin
                    illegal = 1;
                    fp_load = 0;
                end
            end
            7'b0100111: begin
                imm       = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                uses_rs1  = 1;
                alu_src   = 1;
                fp_store  = 1;
                fp_uses_rs2 = 1;
                if (!(funct3 == 3'b010 || funct3 == 3'b011)) begin
                    illegal = 1;
                    fp_store = 0;
                end
            end
            7'b1000011, 7'b1000111, 7'b1001011, 7'b1001111: begin
                fp_compute = 1;
                fp_uses_rs1 = 1;
                fp_uses_rs2 = 1;
                fp_uses_rs3 = 1;
                if (instr[26:25] > 2'b01) begin
                    illegal = 1;
                    fp_compute = 0;
                end
            end
            7'b1010011: begin
                fp_compute = 1;
                fp_uses_rs1 = 1;
                fp_uses_rs2 = 1;
                uses_rs1 = funct7 == 7'b1101000 || funct7 == 7'b1101001 ||
                           funct7 == 7'b1111000;
            end
            7'b0101111: begin
                uses_rs1 = 1;
                uses_rs2 = instr[31:27] != 5'b00010;
                alu_src = 1;
                reg_write = 1;
                amo = funct3 == 3'b010;
                amo_op = instr[31:27];
                if (!amo || !((amo_op == 5'b00010 && rs2 == 0) ||
                              amo_op == 5'b00011 || amo_op == 5'b00001 ||
                              amo_op == 5'b00000 || amo_op == 5'b00100 ||
                              amo_op == 5'b01100 || amo_op == 5'b01000 ||
                              amo_op == 5'b10000 || amo_op == 5'b10100 ||
                              amo_op == 5'b11000 || amo_op == 5'b11100)) begin
                    illegal = 1;
                    amo = 0;
                    reg_write = 0;
                end
            end
            7'b1110011: begin
                case (funct3)
                    3'b000: begin
                        if (instr[31:25] == 7'b0001001 && rd == 0) begin
                            sfence_vma = 1;
                            uses_rs1 = 1;
                            uses_rs2 = 1;
                        end else begin
                            case (instr[31:20])
                                12'h000: ecall  = (rs1 == 0 && rd == 0);
                                12'h001: ebreak = (rs1 == 0 && rd == 0);
                                12'h102: sret   = (rs1 == 0 && rd == 0);
                                12'h105: wfi    = (rs1 == 0 && rd == 0);
                                12'h302: mret   = (rs1 == 0 && rd == 0);
                                default: illegal = 1;
                            endcase
                            if (!(ecall || ebreak || sret || wfi || mret))
                                illegal = 1;
                        end
                    end
                    3'b001, 3'b010, 3'b011: begin
                        csr_en    = 1;
                        csr_cmd   = funct3[1:0];
                        uses_rs1  = 1;
                        reg_write = 1;
                    end
                    3'b101, 3'b110, 3'b111: begin
                        csr_en    = 1;
                        csr_cmd   = funct3[1:0];
                        csr_imm   = 1;
                        reg_write = 1;
                    end
                    default: illegal = 1;
                endcase
            end
            default: illegal = 1;
        endcase
    end
endmodule
