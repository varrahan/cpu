module memory_stage (
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        mem_read,
    input  wire        mem_write,
    input  wire [2:0]  funct3,
    output wire [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output wire        dmem_we,
    output reg  [3:0]  dmem_be,    
    input  wire [31:0] dmem_rdata,
    output reg  [31:0] rdata
);
    assign dmem_addr  = addr;
    assign dmem_we    = mem_write;

    always @(*) begin
        dmem_wdata = wdata;
        dmem_be    = 4'b0000;
        if (mem_write) begin
            case (funct3)
                3'b000: begin 
                    dmem_be    = 4'b0001 << addr[1:0];
                    dmem_wdata = {4{wdata[7:0]}};
                end
                3'b001: begin 
                    dmem_be    = 4'b0011 << {addr[1], 1'b0};
                    dmem_wdata = {2{wdata[15:0]}};
                end
                3'b010: begin 
                    dmem_be    = 4'b1111;
                    dmem_wdata = wdata;
                end
                default: dmem_be = 4'b1111;
            endcase
        end
    end

    always @(*) begin
        rdata = 32'b0;
        if (mem_read) begin
            case (funct3)
                3'b000: rdata = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
                3'b001: rdata = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
                3'b010: rdata = dmem_rdata;
                3'b100: rdata = {24'b0, dmem_rdata[7:0]};
                3'b101: rdata = {16'b0, dmem_rdata[15:0]};
                default: rdata = dmem_rdata;
            endcase
        end
    end
endmodule

module mem_wb_reg (
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