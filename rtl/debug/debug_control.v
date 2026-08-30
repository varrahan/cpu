module debug_control (
    input wire clk, input wire rst_n,
    input wire debug_req, input wire resume_req,
    input wire step, input wire dpc_write, input wire [31:0] dpc_wdata,
    input wire retire_boundary, input wire [31:0] next_pc,
    output wire enter_fire, output wire resume_fire,
    output reg halted, output reg [31:0] dpc
);
    reg step_armed;
    assign enter_fire = (debug_req || step_armed) && !halted && retire_boundary;
    assign resume_fire = resume_req && halted;
    always @(posedge clk) begin
        if (!rst_n) begin halted <= 0; dpc <= 0; step_armed <= 0; end
        else if (resume_fire) begin halted <= 0; step_armed <= step; end
        else if (enter_fire) begin
            halted <= 1; dpc <= {next_pc[31:1], 1'b0}; step_armed <= 0;
        end else if (halted && dpc_write) dpc <= {dpc_wdata[31:1], 1'b0};
    end
endmodule
