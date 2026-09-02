module P_MEM_ASYNC #(
    parameter DATA_WIDTH = 32, ADDR_WIDTH = 5, READ_PORTS = 2,
    parameter BYTE_LANES = 1
) (
    input wire clk, rst_n, we,
    input wire [ADDR_WIDTH-1:0] waddr,
    input wire [DATA_WIDTH-1:0] wdata,
    input wire [BYTE_LANES-1:0] wbe,
    input wire [READ_PORTS*ADDR_WIDTH-1:0] raddr,
    output wire [READ_PORTS*DATA_WIDTH-1:0] rdata
);
    (* anyseq *) wire [READ_PORTS*DATA_WIDTH-1:0] unconstrained_rdata;
    assign rdata = unconstrained_rdata;
endmodule

module P_MULDIV32 (
    input wire clk, rst_n, start, flush, input wire [2:0] op,
    input wire [31:0] a, b,
    output wire ready, busy, done, output wire [31:0] result
);
    (* anyseq *) wire [31:0] unconstrained_result;
    assign ready = 1; assign busy = 0; assign done = start && !flush;
    assign result = unconstrained_result;
endmodule

module P_FPU64 (
    input wire clk, rst_n, start, flush, input wire [31:0] instr, rs1_int,
    input wire [63:0] frs1, frs2, frs3, input wire [2:0] frm,
    output wire ready, busy, done, illegal, output wire [63:0] result,
    output wire [4:0] flags, output wire result_to_int, write_fp
);
    (* anyseq *) wire [70:0] unconstrained_result;
    assign ready = 1; assign busy = 0; assign done = start && !flush;
    assign illegal = 0;
    assign {result, flags, result_to_int, write_fp} = unconstrained_result;
endmodule
