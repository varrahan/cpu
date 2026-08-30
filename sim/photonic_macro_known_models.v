`timescale 1ps/1ps

module P_PC32 (
    input wire clk, input wire rst_n, input wire stall, input wire flush,
    input wire [31:0] redirect_pc, input wire [2:0] instr_length,
    output reg [31:0] pc, output reg issue_window
);
    reg [2:0] accepted_length;
    always @(posedge clk) begin
        if (!rst_n) begin
            pc <= 0;
            issue_window <= 1;
            accepted_length <= 4;
        end else if (flush) begin
            pc <= redirect_pc;
            issue_window <= 1;
        end else if (!issue_window) begin
            pc <= pc + accepted_length;
            issue_window <= 1;
        end else if (!stall) begin
            accepted_length <= instr_length;
            issue_window <= 0;
        end
    end
endmodule

module P_PMP32 (
    input wire [31:0] addr, input wire [3:0] size,
    input wire [1:0] privilege,
    input wire access_read, input wire access_write, input wire access_execute,
    input wire [31:0] pmpcfg0,
    input wire [31:0] pmpaddr0, input wire [31:0] pmpaddr1,
    input wire [31:0] pmpaddr2, input wire [31:0] pmpaddr3,
    output wire allow
);
    wire inputs_known = !$isunknown({addr, size, privilege, access_read,
        access_write, access_execute, pmpcfg0, pmpaddr0, pmpaddr1,
        pmpaddr2, pmpaddr3});
    assign allow = inputs_known ? (privilege == 2'b11 || pmpcfg0 == 0) : 1'bx;
endmodule

module P_MULDIV32 (
    input wire clk, input wire rst_n, input wire start, input wire flush,
    input wire [2:0] op, input wire [31:0] a, input wire [31:0] b,
    output wire ready, output reg busy, output reg done,
    output reg [31:0] result
);
    function automatic [31:0] calculate;
        input [2:0] operation;
        input [31:0] lhs, rhs;
        reg signed [31:0] signed_lhs, signed_rhs;
        reg signed [63:0] signed_product;
        reg signed [64:0] signed_unsigned_product;
        begin
            signed_lhs = lhs;
            signed_rhs = rhs;
            signed_product = signed_lhs * signed_rhs;
            signed_unsigned_product = signed_lhs * $signed({1'b0, rhs});
            case (operation)
                3'b000: calculate = lhs * rhs;
                3'b001: calculate = signed_product[63:32];
                3'b010: calculate = signed_unsigned_product[63:32];
                3'b011: calculate = ({32'b0, lhs} * {32'b0, rhs}) >> 32;
                3'b100: calculate = rhs == 0 ? 32'hffff_ffff :
                    (lhs == 32'h8000_0000 && rhs == 32'hffff_ffff) ?
                    32'h8000_0000 : signed_lhs / signed_rhs;
                3'b101: calculate = rhs == 0 ? 32'hffff_ffff : lhs / rhs;
                3'b110: calculate = rhs == 0 ? lhs :
                    (lhs == 32'h8000_0000 && rhs == 32'hffff_ffff) ? 0 :
                    signed_lhs % signed_rhs;
                default: calculate = rhs == 0 ? lhs : lhs % rhs;
            endcase
        end
    endfunction

    assign ready = !busy;
    always @(posedge clk) begin
        if (!rst_n || flush) begin
            busy <= 0;
            done <= 0;
            result <= 0;
        end else begin
            done <= 0;
            if (start) begin
                busy <= 0;
                done <= 1;
                result <= calculate(op, a, b);
            end
        end
    end
endmodule

module P_FPU64 (
    input wire clk, input wire rst_n, input wire start, input wire flush,
    input wire [31:0] instr, input wire [31:0] rs1_int,
    input wire [63:0] frs1, input wire [63:0] frs2,
    input wire [63:0] frs3, input wire [2:0] frm,
    output wire ready, output reg busy, output reg done, output wire illegal,
    output reg [63:0] result, output reg [4:0] flags,
    output reg result_to_int, output reg write_fp
);
    assign ready = !busy;
    assign illegal = $isunknown(instr) ? 1'bx : 1'b0;
    always @(posedge clk) begin
        if (!rst_n || flush) begin
            busy <= 0;
            done <= 0;
            result <= 0;
            flags <= 0;
            result_to_int <= 0;
            write_fp <= 0;
        end else begin
            done <= 0;
            if (start) begin
                busy <= 0;
                done <= 1;
                result <= frs1 ^ frs2 ^ frs3 ^ {32'b0, rs1_int};
                flags <= {2'b0, frm};
                result_to_int <= instr[0];
                write_fp <= !instr[0];
            end
        end
    end
endmodule
