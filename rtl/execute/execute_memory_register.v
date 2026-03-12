module execute_memory_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] rs2_data_in,
    input  wire [4:0]  rd_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        reg_write_in,
    input  wire [2:0]  funct3_in,
    input  wire        branch_taken_in,
    input  wire [31:0] branch_target_in,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] rs2_data_out,
    output reg  [4:0]  rd_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         reg_write_out,
    output reg  [2:0]  funct3_out,
    output reg         branch_taken_out,
    output reg  [31:0] branch_target_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            alu_result_out  <= 0;
            rs2_data_out    <= 0; rd_out          <= 0;
            mem_read_out    <= 0; mem_write_out   <= 0; reg_write_out   <= 0;
            funct3_out      <= 0; branch_taken_out <= 0; branch_target_out <= 0;
        end else begin
            alu_result_out  <= alu_result_in;
            rs2_data_out    <= rs2_data_in;    rd_out          <= rd_in;
            mem_read_out    <= mem_read_in;    mem_write_out   <= mem_write_in;   
            reg_write_out   <= reg_write_in;
            funct3_out      <= funct3_in;      branch_taken_out <= branch_taken_in;
            branch_target_out <= branch_target_in;
        end
    end
endmodule