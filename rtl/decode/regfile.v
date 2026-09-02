module regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        wr_en,
    input  wire [4:0]  debug_addr,
    input  wire [31:0] debug_wdata,
    input  wire        debug_re,
    input  wire        debug_we,
    output wire [31:0] debug_rdata,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    wire [4:0] shared_rs1_addr = debug_re ? debug_addr : rs1_addr;
    wire memory_we = (debug_we && debug_addr != 0) ||
                     (wr_en && rd_addr != 0);
    wire debug_memory_we = debug_we && debug_addr != 0;
    wire [4:0] memory_waddr = debug_memory_we ? debug_addr : rd_addr;
    wire [31:0] memory_wdata = debug_memory_we ? debug_wdata : rd_data;
    wire [63:0] memory_rdata;

    P_MEM_ASYNC #(.DATA_WIDTH(32), .ADDR_WIDTH(5), .READ_PORTS(2)) u_regs (
        .clk(clk), .rst_n(rst_n), .we(memory_we), .waddr(memory_waddr),
        .wdata(memory_wdata), .wbe(1'b1),
        .raddr({rs2_addr, shared_rs1_addr}), .rdata(memory_rdata)
    );

    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 :
                      (wr_en && rd_addr == rs1_addr) ? rd_data : memory_rdata[31:0];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 :
                      (wr_en && rd_addr == rs2_addr) ? rd_data : memory_rdata[63:32];
    assign debug_rdata = debug_addr == 0 ? 0 : memory_rdata[31:0];
`ifdef FORMAL
    always @(*) begin
        if (rs1_addr == 0) assert(rs1_data == 0);
        if (rs2_addr == 0) assert(rs2_data == 0);
        if (debug_addr == 0) assert(debug_rdata == 0);
        if (memory_we) assert(memory_waddr != 0);
    end
`endif
endmodule
