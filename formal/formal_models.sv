module async_memory #(
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
