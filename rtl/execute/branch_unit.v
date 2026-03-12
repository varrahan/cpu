module branch_unit (
    input  wire [31:0] rs1,
    input  wire [31:0] rs2,
    input  wire [2:0]  funct3,
    input  wire        branch,
    input  wire        jal,
    input  wire        jalr,
    output reg         taken
);
    always @(*) begin
        taken = 0;
        if (jal || jalr) begin
            taken = 1;
        end else if (branch) begin
            case (funct3)
                3'b000: taken = (rs1 == rs2);
                3'b001: taken = (rs1 != rs2);
                3'b100: taken = ($signed(rs1) < $signed(rs2));
                3'b101: taken = ($signed(rs1) >= $signed(rs2));
                3'b110: taken = (rs1 < rs2);
                3'b111: taken = (rs1 >= rs2);
                default: taken = 0;
            endcase
        end
    end
endmodule