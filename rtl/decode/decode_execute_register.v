module decode_execute_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    input  wire        stall,
    input  wire [31:0] pc_in,
    input  wire [31:0] rs1_data_in,
    input  wire [31:0] rs2_data_in,
    input  wire [31:0] imm_in,
    input  wire [4:0]  rs1_addr_in,
    input  wire [4:0]  rs2_addr_in,
    input  wire [4:0]  rd_in,
    input  wire [3:0]  alu_op_in,
    input  wire        alu_src_in,
    input  wire        mem_read_in,
    input  wire        mem_write_in,
    input  wire        reg_write_in,
    input  wire        branch_in,
    input  wire        jal_in,
    input  wire        jalr_in,
    input  wire [2:0]  funct3_in,
    input  wire        lui_in,
    input  wire        auipc_in,
    output reg  [31:0] pc_out,
    output reg  [31:0] rs1_data_out,
    output reg  [31:0] rs2_data_out,
    output reg  [31:0] imm_out,
    output reg  [4:0]  rs1_addr_out,
    output reg  [4:0]  rs2_addr_out,
    output reg  [4:0]  rd_out,
    output reg  [3:0]  alu_op_out,
    output reg         alu_src_out,
    output reg         mem_read_out,
    output reg         mem_write_out,
    output reg         reg_write_out,
    output reg         branch_out,
    output reg         jal_out,
    output reg         jalr_out,
    output reg  [2:0]  funct3_out,
    output reg         lui_out,
    output reg         auipc_out
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            pc_out        <= 0;
            rs1_data_out  <= 0; rs2_data_out  <= 0;
            imm_out       <= 0;
            rs1_addr_out  <= 0; rs2_addr_out  <= 0;
            rd_out        <= 0;
            alu_op_out    <= 0; alu_src_out   <= 0;
            mem_read_out  <= 0; mem_write_out <= 0;
            reg_write_out <= 0;
            branch_out    <= 0; jal_out       <= 0;
            jalr_out      <= 0;
            funct3_out    <= 0;
            lui_out       <= 0; auipc_out     <= 0;
        end else if (!stall) begin
            pc_out        <= pc_in;
            rs1_data_out  <= rs1_data_in;  rs2_data_out  <= rs2_data_in;
            imm_out       <= imm_in;
            rs1_addr_out  <= rs1_addr_in;  rs2_addr_out  <= rs2_addr_in;
            rd_out        <= rd_in;
            alu_op_out    <= alu_op_in;
            alu_src_out   <= alu_src_in;   mem_read_out  <= mem_read_in;
            mem_write_out <= mem_write_in; reg_write_out <= reg_write_in;
            branch_out    <= branch_in;    jal_out       <= jal_in;
            jalr_out      <= jalr_in;      funct3_out    <= funct3_in;
            lui_out       <= lui_in;       auipc_out     <= auipc_in;
        end
    end
endmodule