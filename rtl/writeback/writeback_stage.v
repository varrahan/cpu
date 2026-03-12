module writeback_stage (
    input  wire [31:0] alu_result,
    input  wire [31:0] mem_rdata,
    input  wire        mem_read,
    output wire [31:0] wb_data
);
    assign wb_data = mem_read ? mem_rdata : alu_result;
endmodule