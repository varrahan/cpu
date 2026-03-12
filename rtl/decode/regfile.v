module regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        wr_en,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data
);
    reg [31:0] regs [31:0];

    always @(posedge clk) begin
        if (wr_en && rd_addr != 5'b0)
            regs[rd_addr] <= rd_data;
    end

    assign rs1_data = (rs1_addr == 5'b0) ? 32'b0 :
                      (wr_en && rd_addr == rs1_addr) ? rd_data : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'b0 :
                      (wr_en && rd_addr == rs2_addr) ? rd_data : regs[rs2_addr];
endmodule