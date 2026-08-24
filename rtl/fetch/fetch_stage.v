module fetch_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] redirect_pc,
    output wire [31:0] pc_out,
    output wire [31:0] instr_out,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,
    output wire        pred_taken
);
    reg  [31:0] pc;
    wire [6:0]  opcode;
    wire [31:0] branch_imm;
    wire [31:0] jal_imm;
    wire [31:0] predicted_target;

    assign opcode     = imem_data[6:0];
    assign branch_imm = {{19{imem_data[31]}}, imem_data[31], imem_data[7],
                         imem_data[30:25], imem_data[11:8], 1'b0};
    assign jal_imm    = {{11{imem_data[31]}}, imem_data[31], imem_data[19:12],
                         imem_data[20], imem_data[30:21], 1'b0};

    // ponytail: Static BTFNT; add a BHT/BTB if branch misses become measurable.
    assign pred_taken       = (opcode == 7'b1101111) ||
                              ((opcode == 7'b1100011) && imem_data[31]);
    assign predicted_target = pc + ((opcode == 7'b1101111) ? jal_imm : branch_imm);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'h0000_0000;
        else if (flush)
            pc <= redirect_pc;
        else if (!stall)
            pc <= pred_taken ? predicted_target : pc + 4;
    end

    assign imem_addr = pc;
    assign pc_out    = pc;
    assign instr_out = flush ? 32'h0000_0013 : imem_data;
endmodule
