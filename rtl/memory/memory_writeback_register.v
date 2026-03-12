module memory_writeback_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] mem_rdata_in,
    input  wire [4:0]  rd_in,
    input  wire        mem_read_in,
    input  wire        reg_write_in,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mem_rdata_out,
    output reg  [4:0]  rd_out,
    output reg         mem_read_out,
    output reg         reg_write_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alu_result_out <= 0;
            mem_rdata_out  <= 0; rd_out         <= 0;
            mem_read_out   <= 0; reg_write_out  <= 0;
        end else begin
            alu_result_out <= alu_result_in;
            mem_rdata_out  <= mem_rdata_in;  rd_out         <= rd_in;         
            mem_read_out   <= mem_read_in;   reg_write_out  <= reg_write_in;
        end
    end
endmodule