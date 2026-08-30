module control_harness;
    (* anyconst *) reg [4:0] id_rs1, id_rs2, ex_rd;
    (* anyconst *) reg id_uses_rs1, id_uses_rs2, ex_mem_read;
    wire stall, flush_id_ex;

    hazard_unit hazard (.*);

    (* anyconst *) reg [31:0] branch_rs1, branch_rs2;
    (* anyconst *) reg [2:0] funct3;
    (* anyconst *) reg branch, jal, jalr;
    wire taken;

    branch_unit branch_logic (
        .rs1(branch_rs1), .rs2(branch_rs2), .funct3(funct3),
        .branch(branch), .jal(jal), .jalr(jalr), .taken(taken)
    );

    always @(*) begin
        assert(stall == (ex_mem_read && ex_rd != 0 &&
               ((id_uses_rs1 && ex_rd == id_rs1) ||
                (id_uses_rs2 && ex_rd == id_rs2))));
        assert(flush_id_ex == stall);
        if (jal || jalr) assert(taken);
        else if (!branch) assert(!taken);
        else case (funct3)
            3'b000: assert(taken == (branch_rs1 == branch_rs2));
            3'b001: assert(taken == (branch_rs1 != branch_rs2));
            3'b100: assert(taken == ($signed(branch_rs1) < $signed(branch_rs2)));
            3'b101: assert(taken == ($signed(branch_rs1) >= $signed(branch_rs2)));
            3'b110: assert(taken == (branch_rs1 < branch_rs2));
            3'b111: assert(taken == (branch_rs1 >= branch_rs2));
            default: assert(!taken);
        endcase
    end
endmodule
