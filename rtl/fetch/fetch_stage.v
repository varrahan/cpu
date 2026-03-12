module if_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] branch_target,
    input  wire        branch_taken,
    output wire [31:0] pc_out,
    output wire [31:0] instr_out,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data
);
    reg  [31:0] pc;
    reg  [31:0] pc_next;

    // PC register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'h0000_0000;
        else if (!stall)
            pc <= pc_next;
    end

    // Next PC logic
    always @(*) begin
        if (branch_taken)
            pc_next = branch_target;
        else
            pc_next = pc + 4;
    end

    // Instruction memory read
    assign imem_addr = pc;
    assign pc_out    = pc;
    assign instr_out = flush ? 32'h0000_0013 : imem_data; // NOP on flush
endmodule