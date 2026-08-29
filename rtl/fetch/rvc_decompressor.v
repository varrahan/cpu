module rvc_decompressor (
    input  wire [15:0] compressed,
    output reg  [31:0] instruction,
    output reg         illegal
);
    localparam [6:0] OP_LOAD    = 7'h03;
    localparam [6:0] OP_LOAD_FP = 7'h07;
    localparam [6:0] OP_IMM     = 7'h13;
    localparam [6:0] OP_STORE   = 7'h23;
    localparam [6:0] OP_STORE_FP= 7'h27;
    localparam [6:0] OP_REG     = 7'h33;
    localparam [6:0] OP_LUI     = 7'h37;
    localparam [6:0] OP_BRANCH  = 7'h63;
    localparam [6:0] OP_JALR    = 7'h67;
    localparam [6:0] OP_JAL     = 7'h6f;

    always @(*) begin
        instruction = 32'h0000_0013;
        illegal = 0;
        case (compressed[1:0])
            2'b00: case (compressed[15:13])
                3'b000: begin // C.ADDI4SPN
                    instruction = {2'b0, compressed[10:7], compressed[12:11],
                                   compressed[5], compressed[6], 2'b00,
                                   5'd2, 3'b000, 2'b01, compressed[4:2], OP_IMM};
                    if (compressed[12:5] == 0) illegal = 1;
                end
                3'b001: instruction = {4'b0, compressed[6:5], compressed[12:10],
                                       3'b000, 2'b01, compressed[9:7], 3'b011,
                                       2'b01, compressed[4:2], OP_LOAD_FP}; // C.FLD
                3'b010: instruction = {5'b0, compressed[5], compressed[12:10],
                                       compressed[6], 2'b00, 2'b01,
                                       compressed[9:7], 3'b010, 2'b01,
                                       compressed[4:2], OP_LOAD}; // C.LW
                3'b011: instruction = {5'b0, compressed[5], compressed[12:10],
                                       compressed[6], 2'b00, 2'b01,
                                       compressed[9:7], 3'b010, 2'b01,
                                       compressed[4:2], OP_LOAD_FP}; // C.FLW
                3'b101: instruction = {4'b0, compressed[6:5], compressed[12],
                                       2'b01, compressed[4:2], 2'b01,
                                       compressed[9:7], 3'b011,
                                       compressed[11:10], 3'b000, OP_STORE_FP}; // C.FSD
                3'b110: instruction = {5'b0, compressed[5], compressed[12],
                                       2'b01, compressed[4:2], 2'b01,
                                       compressed[9:7], 3'b010,
                                       compressed[11:10], compressed[6],
                                       2'b00, OP_STORE}; // C.SW
                3'b111: instruction = {5'b0, compressed[5], compressed[12],
                                       2'b01, compressed[4:2], 2'b01,
                                       compressed[9:7], 3'b010,
                                       compressed[11:10], compressed[6],
                                       2'b00, OP_STORE_FP}; // C.FSW
                default: illegal = 1;
            endcase
            2'b01: case (compressed[15:13])
                3'b000: instruction = {{6{compressed[12]}}, compressed[12],
                                       compressed[6:2], compressed[11:7], 3'b000,
                                       compressed[11:7], OP_IMM}; // C.ADDI/NOP
                3'b001, 3'b101: instruction = {compressed[12], compressed[8],
                                       compressed[10:9], compressed[6], compressed[7],
                                       compressed[2], compressed[11], compressed[5:3],
                                       {9{compressed[12]}}, 4'b0,
                                       ~compressed[15], OP_JAL}; // C.JAL/C.J
                3'b010: instruction = {{6{compressed[12]}}, compressed[12],
                                       compressed[6:2], 5'b0, 3'b000,
                                       compressed[11:7], OP_IMM}; // C.LI
                3'b011: begin
                    if (compressed[11:7] == 5'd2) begin
                        instruction = {{3{compressed[12]}}, compressed[4:3],
                                       compressed[5], compressed[2], compressed[6],
                                       4'b0, 5'd2, 3'b000, 5'd2, OP_IMM};
                        if ({compressed[12], compressed[6:2]} == 0) illegal = 1;
                    end else begin
                        instruction = {{15{compressed[12]}}, compressed[6:2],
                                       compressed[11:7], OP_LUI};
                        if ({compressed[12], compressed[6:2]} == 0) illegal = 1;
                    end
                end
                3'b100: case (compressed[11:10])
                    2'b00, 2'b01: begin
                        instruction = {1'b0, compressed[10], 5'b0,
                                       compressed[6:2], 2'b01, compressed[9:7],
                                       3'b101, 2'b01, compressed[9:7], OP_IMM};
                        if (compressed[12]) illegal = 1;
                    end
                    2'b10: instruction = {{6{compressed[12]}}, compressed[12],
                                       compressed[6:2], 2'b01, compressed[9:7],
                                       3'b111, 2'b01, compressed[9:7], OP_IMM};
                    default: case ({compressed[12], compressed[6:5]})
                        3'b000: instruction = {7'b0100000, 2'b01,
                                              compressed[4:2], 2'b01,
                                              compressed[9:7], 3'b000, 2'b01,
                                              compressed[9:7], OP_REG};
                        3'b001: instruction = {7'b0, 2'b01, compressed[4:2],
                                              2'b01, compressed[9:7], 3'b100,
                                              2'b01, compressed[9:7], OP_REG};
                        3'b010: instruction = {7'b0, 2'b01, compressed[4:2],
                                              2'b01, compressed[9:7], 3'b110,
                                              2'b01, compressed[9:7], OP_REG};
                        3'b011: instruction = {7'b0, 2'b01, compressed[4:2],
                                              2'b01, compressed[9:7], 3'b111,
                                              2'b01, compressed[9:7], OP_REG};
                        default: illegal = 1;
                    endcase
                endcase
                3'b110, 3'b111: instruction = {{4{compressed[12]}},
                                       compressed[6:5], compressed[2], 5'b0,
                                       2'b01, compressed[9:7], 2'b00,
                                       compressed[13], compressed[11:10],
                                       compressed[4:3], compressed[12], OP_BRANCH};
                default: illegal = 1;
            endcase
            2'b10: case (compressed[15:13])
                3'b000: begin
                    instruction = {7'b0, compressed[6:2], compressed[11:7],
                                   3'b001, compressed[11:7], OP_IMM}; // C.SLLI
                    if (compressed[12]) illegal = 1;
                end
                3'b001: instruction = {3'b0, compressed[4:2], compressed[12],
                                       compressed[6:5], 3'b000, 5'd2, 3'b011,
                                       compressed[11:7], OP_LOAD_FP}; // C.FLDSP
                3'b010: begin
                    instruction = {4'b0, compressed[3:2], compressed[12],
                                   compressed[6:4], 2'b00, 5'd2, 3'b010,
                                   compressed[11:7], OP_LOAD};
                    if (compressed[11:7] == 0) illegal = 1;
                end
                3'b011: instruction = {4'b0, compressed[3:2], compressed[12],
                                       compressed[6:4], 2'b00, 5'd2, 3'b010,
                                       compressed[11:7], OP_LOAD_FP}; // C.FLWSP
                3'b100: begin
                    if (!compressed[12] && compressed[6:2] != 0)
                        instruction = {7'b0, compressed[6:2], 5'b0, 3'b000,
                                       compressed[11:7], OP_REG}; // C.MV
                    else if (!compressed[12]) begin
                        instruction = {12'b0, compressed[11:7], 3'b000,
                                       5'b0, OP_JALR}; // C.JR
                        if (compressed[11:7] == 0) illegal = 1;
                    end else if (compressed[6:2] != 0)
                        instruction = {7'b0, compressed[6:2], compressed[11:7],
                                       3'b000, compressed[11:7], OP_REG}; // C.ADD
                    else if (compressed[11:7] == 0)
                        instruction = 32'h0010_0073; // C.EBREAK
                    else
                        instruction = {12'b0, compressed[11:7], 3'b000,
                                       5'd1, OP_JALR}; // C.JALR
                end
                3'b101: instruction = {3'b0, compressed[9:7], compressed[12],
                                       compressed[6:2], 5'd2, 3'b011,
                                       compressed[11:10], 3'b000, OP_STORE_FP}; // C.FSDSP
                3'b110: instruction = {4'b0, compressed[8:7], compressed[12],
                                       compressed[6:2], 5'd2, 3'b010,
                                       compressed[11:9], 2'b00, OP_STORE}; // C.SWSP
                3'b111: instruction = {4'b0, compressed[8:7], compressed[12],
                                       compressed[6:2], 5'd2, 3'b010,
                                       compressed[11:9], 2'b00, OP_STORE_FP}; // C.FSWSP
                default: illegal = 1;
            endcase
            default: illegal = 1;
        endcase
    end
endmodule
