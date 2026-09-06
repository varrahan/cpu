module decoder (
    input logic [31:0] instr,
    output hybrid_pkg::decode_t decoded
);
    wire [6:0] opcode = instr[6:0];
    wire [6:0] funct7 = instr[31:25];

    always_comb begin
        decoded = '0;
        decoded.funct3 = instr[14:12];
        decoded.rs1 = instr[19:15];
        decoded.rs2 = instr[24:20];
        decoded.rd = instr[11:7];

        case (opcode)
            7'b0110011: begin
                decoded.uses_rs1 = 1;
                decoded.uses_rs2 = 1;
                decoded.reg_write = 1;
                if (funct7 == 7'b0000001) begin
                    decoded.muldiv = 1;
                    decoded.muldiv_op = decoded.funct3;
                end else begin
                    case ({funct7, decoded.funct3})
                        10'b0000000_000: decoded.alu_op = 4'b0000;
                        10'b0100000_000: decoded.alu_op = 4'b0001;
                        10'b0000000_001: decoded.alu_op = 4'b0010;
                        10'b0000000_010: decoded.alu_op = 4'b0011;
                        10'b0000000_011: decoded.alu_op = 4'b0100;
                        10'b0000000_100: decoded.alu_op = 4'b0101;
                        10'b0000000_101: decoded.alu_op = 4'b0110;
                        10'b0100000_101: decoded.alu_op = 4'b0111;
                        10'b0000000_110: decoded.alu_op = 4'b1000;
                        10'b0000000_111: decoded.alu_op = 4'b1001;
                        default: begin decoded.illegal = 1; decoded.reg_write = 0; end
                    endcase
                end
            end
            7'b0010011: begin
                decoded.imm       = {{20{instr[31]}}, instr[31:20]};
                decoded.uses_rs1  = 1;
                decoded.alu_src   = 1;
                decoded.reg_write = 1;
                case (decoded.funct3)
                    3'b000: decoded.alu_op = 4'b0000;
                    3'b010: decoded.alu_op = 4'b0011;
                    3'b011: decoded.alu_op = 4'b0100;
                    3'b100: decoded.alu_op = 4'b0101;
                    3'b110: decoded.alu_op = 4'b1000;
                    3'b111: decoded.alu_op = 4'b1001;
                    3'b001: begin
                        decoded.alu_op = 4'b0010;
                        if (funct7 != 7'b0000000) decoded.illegal = 1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) decoded.alu_op = 4'b0110;
                        else if (funct7 == 7'b0100000) decoded.alu_op = 4'b0111;
                        else decoded.illegal = 1;
                    end
                    default: decoded.illegal = 1;
                endcase
                if (decoded.illegal) decoded.reg_write = 0;
            end
            7'b0000011: begin
                decoded.imm       = {{20{instr[31]}}, instr[31:20]};
                decoded.uses_rs1  = 1;
                decoded.alu_src   = 1;
                decoded.mem_read  = 1;
                decoded.reg_write = 1;
                if (!(decoded.funct3 == 3'b000 || decoded.funct3 == 3'b001 ||
                      decoded.funct3 == 3'b010 || decoded.funct3 == 3'b100 ||
                      decoded.funct3 == 3'b101)) begin
                    decoded.illegal = 1;
                    decoded.mem_read = 0;
                    decoded.reg_write = 0;
                end
            end
            7'b0100011: begin
                decoded.imm       = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                decoded.uses_rs1  = 1;
                decoded.uses_rs2  = 1;
                decoded.alu_src   = 1;
                decoded.mem_write = 1;
                if (!(decoded.funct3 == 3'b000 || decoded.funct3 == 3'b001 ||
                      decoded.funct3 == 3'b010)) begin
                    decoded.illegal = 1;
                    decoded.mem_write = 0;
                end
            end
            7'b1100011: begin
                decoded.imm      = {{19{instr[31]}}, instr[31], instr[7],
                            instr[30:25], instr[11:8], 1'b0};
                decoded.uses_rs1 = 1;
                decoded.uses_rs2 = 1;
                decoded.branch   = 1;
                if (!(decoded.funct3 == 3'b000 || decoded.funct3 == 3'b001 ||
                      decoded.funct3 == 3'b100 || decoded.funct3 == 3'b101 ||
                      decoded.funct3 == 3'b110 || decoded.funct3 == 3'b111)) begin
                    decoded.illegal = 1;
                    decoded.branch = 0;
                end
            end
            7'b1101111: begin
                decoded.imm       = {{11{instr[31]}}, instr[31], instr[19:12],
                             instr[20], instr[30:21], 1'b0};
                decoded.jal       = 1;
                decoded.reg_write = 1;
            end
            7'b1100111: begin
                decoded.imm       = {{20{instr[31]}}, instr[31:20]};
                decoded.uses_rs1  = 1;
                decoded.alu_src   = 1;
                decoded.jalr      = 1;
                decoded.reg_write = 1;
                if (decoded.funct3 != 3'b000) begin
                    decoded.illegal = 1;
                    decoded.jalr = 0;
                    decoded.reg_write = 0;
                end
            end
            7'b0110111: begin
                decoded.imm       = {instr[31:12], 12'b0};
                decoded.lui       = 1;
                decoded.alu_src   = 1;
                decoded.reg_write = 1;
            end
            7'b0010111: begin
                decoded.imm       = {instr[31:12], 12'b0};
                decoded.auipc     = 1;
                decoded.alu_src   = 1;
                decoded.reg_write = 1;
            end
            7'b0001111: begin
                if (decoded.funct3 == 3'b000) decoded.fence = 1;
                else if (decoded.funct3 == 3'b001) decoded.fence_i = 1;
                else decoded.illegal = 1;
            end
            7'b0000111: begin
                decoded.imm       = {{20{instr[31]}}, instr[31:20]};
                decoded.uses_rs1  = 1;
                decoded.alu_src   = 1;
                decoded.fp_load   = 1;
                if (!(decoded.funct3 == 3'b010 || decoded.funct3 == 3'b011)) begin
                    decoded.illegal = 1;
                    decoded.fp_load = 0;
                end
            end
            7'b0100111: begin
                decoded.imm       = {{20{instr[31]}}, instr[31:25], instr[11:7]};
                decoded.uses_rs1  = 1;
                decoded.alu_src   = 1;
                decoded.fp_store  = 1;
                decoded.fp_uses_rs2 = 1;
                if (!(decoded.funct3 == 3'b010 || decoded.funct3 == 3'b011)) begin
                    decoded.illegal = 1;
                    decoded.fp_store = 0;
                end
            end
            7'b1000011, 7'b1000111, 7'b1001011, 7'b1001111: begin
                decoded.fp_compute = 1;
                decoded.fp_uses_rs1 = 1;
                decoded.fp_uses_rs2 = 1;
                decoded.fp_uses_rs3 = 1;
                if (instr[26:25] > 2'b01) begin
                    decoded.illegal = 1;
                    decoded.fp_compute = 0;
                end
            end
            7'b1010011: begin
                decoded.fp_compute = 1;
                decoded.fp_uses_rs1 = 1;
                decoded.fp_uses_rs2 = 1;
                decoded.uses_rs1 = funct7 == 7'b1101000 || funct7 == 7'b1101001 ||
                           funct7 == 7'b1111000;
            end
            7'b0101111: begin
                decoded.uses_rs1 = 1;
                decoded.uses_rs2 = instr[31:27] != 5'b00010;
                decoded.alu_src = 1;
                decoded.reg_write = 1;
                decoded.amo = decoded.funct3 == 3'b010;
                decoded.amo_op = instr[31:27];
                if (!decoded.amo || !((decoded.amo_op == 5'b00010 && decoded.rs2 == 0) ||
                              decoded.amo_op == 5'b00011 || decoded.amo_op == 5'b00001 ||
                              decoded.amo_op == 5'b00000 || decoded.amo_op == 5'b00100 ||
                              decoded.amo_op == 5'b01100 || decoded.amo_op == 5'b01000 ||
                              decoded.amo_op == 5'b10000 || decoded.amo_op == 5'b10100 ||
                              decoded.amo_op == 5'b11000 || decoded.amo_op == 5'b11100)) begin
                    decoded.illegal = 1;
                    decoded.amo = 0;
                    decoded.reg_write = 0;
                end
            end
            7'b1110011: begin
                case (decoded.funct3)
                    3'b000: begin
                        if (instr[31:25] == 7'b0001001 && decoded.rd == 0) begin
                            decoded.sfence_vma = 1;
                            decoded.uses_rs1 = 1;
                            decoded.uses_rs2 = 1;
                        end else begin
                            case (instr[31:20])
                                12'h000: decoded.ecall  = (decoded.rs1 == 0 && decoded.rd == 0);
                                12'h001: decoded.ebreak = (decoded.rs1 == 0 && decoded.rd == 0);
                                12'h102: decoded.sret   = (decoded.rs1 == 0 && decoded.rd == 0);
                                12'h105: decoded.wfi    = (decoded.rs1 == 0 && decoded.rd == 0);
                                12'h302: decoded.mret   = (decoded.rs1 == 0 && decoded.rd == 0);
                                default: decoded.illegal = 1;
                            endcase
                            if (!(decoded.ecall || decoded.ebreak || decoded.sret || decoded.wfi || decoded.mret))
                                decoded.illegal = 1;
                        end
                    end
                    3'b001, 3'b010, 3'b011: begin
                        decoded.csr_en    = 1;
                        decoded.csr_cmd   = decoded.funct3[1:0];
                        decoded.uses_rs1  = 1;
                        decoded.reg_write = 1;
                    end
                    3'b101, 3'b110, 3'b111: begin
                        decoded.csr_en    = 1;
                        decoded.csr_cmd   = decoded.funct3[1:0];
                        decoded.csr_imm   = 1;
                        decoded.reg_write = 1;
                    end
                    default: decoded.illegal = 1;
                endcase
            end
            default: decoded.illegal = 1;
        endcase
    end
endmodule
