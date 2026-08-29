`ifdef SYNTHESIS
(* blackbox *)
`endif
module P_PC32 (
    input wire clk, input wire rst_n, input wire stall, input wire flush,
    input wire [31:0] redirect_pc, input wire [2:0] instr_length,
    output wire [31:0] pc, output wire issue_window
);
`ifndef SYNTHESIS
    reg [31:0] pc_state;
    reg advance_pending;
    reg [2:0] accepted_length;
    always @(posedge clk) begin
        if (!rst_n) begin
            pc_state <= 0;
            advance_pending <= 0;
            accepted_length <= 4;
        end else if (flush) begin
            pc_state <= redirect_pc;
            advance_pending <= 0;
        end else if (advance_pending) begin
            pc_state <= pc_state + accepted_length;
            advance_pending <= 0;
        end else if (!stall) begin
            accepted_length <= instr_length;
            advance_pending <= 1;
        end
    end
    assign pc = pc_state;
    assign issue_window = !advance_pending;
`endif
endmodule

module fetch_stage (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        stall,
    input  wire        flush,
    input  wire [31:0] redirect_pc,
    output wire [31:0] pc_out,
    output wire [31:0] raw_instr_out,
    output wire [2:0]  instr_length,
    output wire        issue_window,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,
    input  wire [15:0] imem_data_next,
    output wire        pred_taken
);
    wire [31:0] pc;
    wire [15:0] instruction16 = pc[1] ? imem_data[31:16]
                                           : imem_data[15:0];
    wire        compressed = instruction16[1:0] != 2'b11;
    wire [31:0] instruction32 = pc[1]
                                ? {imem_data_next[15:0], imem_data[31:16]}
                                : imem_data;
    // Execute resolves control flow. Keeping prediction off removes the
    // decoder/target-adder feedback path from the 100 GHz fetch clock loop.
    assign pred_taken = 1'b0;

    P_PC32 u_pc (
        .clk(clk), .rst_n(rst_n), .stall(stall), .flush(flush),
        .redirect_pc(redirect_pc), .instr_length(instr_length),
        .pc(pc), .issue_window(issue_window)
    );

    assign imem_addr = pc;
    assign pc_out    = pc;
    assign raw_instr_out = compressed ? {16'b0, instruction16} : instruction32;
    assign instr_length = compressed ? 3'd2 : 3'd4;
endmodule
