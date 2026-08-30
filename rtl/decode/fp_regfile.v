module fp_regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rs3_addr,
    input  wire [4:0]  rd_addr,
    input  wire [63:0] rd_data,
    input  wire        wr_en,
    input  wire [4:0]  debug_addr,
    input  wire [63:0] debug_wdata,
    input  wire        debug_re,
    input  wire        debug_we,
    output wire [63:0] debug_rdata,
    output wire [63:0] rs1_data,
    output wire [63:0] rs2_data,
    output wire [63:0] rs3_data
);
    wire [4:0] shared_rs3_addr = debug_re ? debug_addr : rs3_addr;
    wire memory_we = debug_we || wr_en;
    wire [4:0] memory_waddr = debug_we ? debug_addr : rd_addr;
    wire [63:0] memory_wdata = debug_we ? debug_wdata : rd_data;
    wire [191:0] memory_rdata;

    P_MEM_ASYNC #(.DATA_WIDTH(64), .ADDR_WIDTH(5), .READ_PORTS(3)) u_regs (
        .clk(clk), .rst_n(rst_n), .we(memory_we), .waddr(memory_waddr),
        .wdata(memory_wdata), .wbe(1'b1),
        .raddr({shared_rs3_addr, rs2_addr, rs1_addr}), .rdata(memory_rdata)
    );

    assign rs1_data = (wr_en && rd_addr == rs1_addr) ? rd_data : memory_rdata[63:0];
    assign rs2_data = (wr_en && rd_addr == rs2_addr) ? rd_data : memory_rdata[127:64];
    assign rs3_data = (wr_en && rd_addr == rs3_addr) ? rd_data : memory_rdata[191:128];
    assign debug_rdata = memory_rdata[191:128];
endmodule
