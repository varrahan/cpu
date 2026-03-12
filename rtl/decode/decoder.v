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
    output reg         auipc
);
    wire [6:0] opcode;
    wire [6:0] funct7;

    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];

    // Immediate generation
    always @(*) begin
        case (opcode)
            7'b0010011, // I-type ALU
            7'b0000011, // Load
            7'b1100111: // JALR
                imm = {{20{instr[31]}}, instr[31:20]};
            7'b0100011: // S-type Store
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            7'b1100011: // B-type Branch
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            7'b1101111: // J-type JAL
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            7'b0110111, // LUI
            7'b0010111: // AUIPC
                imm = {instr[31:12], 12'b0};
            default:
                imm = 32'b0;
        endcase
    end

    // Control signals
    always @(*) begin
        alu_op    = 4'b0000;
        alu_src   = 0;
        mem_read  = 0;
        mem_write = 0;
        reg_write = 0;
        branch    = 0;
        jal       = 0;
        jalr      = 0;
        lui       = 0;
        auipc     = 0;

        case (opcode)
            // R-type
            7'b0110011: begin
                reg_write = 1;
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
                    default:         alu_op = 4'b0000;
                endcase
            end
            // I-type ALU
            7'b0010011: begin
                reg_write = 1;
                alu_src   = 1;
                case (funct3)
                    3'b000: alu_op = 4'b0000;
                    3'b001: alu_op = 4'b0010;
                    3'b010: alu_op = 4'b0011;
                    3'b011: alu_op = 4'b0100;
                    3'b100: alu_op = 4'b0101;
                    3'b101: alu_op = (funct7[5]) ? 4'b0111 : 4'b0110; 
                    3'b110: alu_op = 4'b1000;
                    3'b111: alu_op = 4'b1001;
                    default: alu_op = 4'b0000;
                endcase
            end
            // Load
            7'b0000011: begin
                reg_write = 1;
                mem_read  = 1;
                alu_src   = 1;
                alu_op    = 4'b0000;
            end
            7'b0100011: begin // Store
                mem_write = 1;
                alu_src   = 1;
                alu_op    = 4'b0000;
            end
            7'b1100011: begin // Branch
                branch    = 1;
                alu_op    = 4'b0001; 
            end
            7'b1101111: begin // JAL
                reg_write = 1;
                jal       = 1;
            end
            7'b1100111: begin // JALR
                reg_write = 1;
                jalr      = 1;
                alu_src   = 1;
                alu_op    = 4'b0000;
            end
            7'b0110111: begin // LUI
                reg_write = 1;
                lui       = 1;
            end
            7'b0010111: begin // AUIPC
                reg_write = 1;
                auipc     = 1;
            end
            default: ;
        endcase
    end
endmodule