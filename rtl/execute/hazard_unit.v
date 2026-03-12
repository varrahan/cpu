module hazard_unit (
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire [4:0]  ex_rd,
    input  wire        ex_mem_read,
    output reg         stall,
    output reg         flush_id_ex
);
    always @(*) begin
        stall       = 0;
        flush_id_ex = 0;
        if (ex_mem_read && ((ex_rd == id_rs1) || (ex_rd == id_rs2))) begin
            stall       = 1;
            flush_id_ex = 1;
        end
    end
endmodule