module debug_control (
    input logic clk, input logic rst_n,
    input logic debug_req, input logic resume_req,
    input logic step, input logic dpc_write, input logic [31:0] dpc_wdata,
    input logic retire_boundary, input logic [31:0] next_pc,
    output logic enter_fire, output logic resume_fire,
    output logic halted, output logic [31:0] dpc
);
    logic step_armed;
    assign enter_fire = (debug_req || step_armed) && !halted && retire_boundary;
    assign resume_fire = resume_req && halted;
    always_ff @(posedge clk) begin
        if (!rst_n) begin halted <= 0; dpc <= 0; step_armed <= 0; end
        else if (resume_fire) begin halted <= 0; step_armed <= step; end
        else if (enter_fire) begin
            halted <= 1; dpc <= {next_pc[31:1], 1'b0}; step_armed <= 0;
        end else if (halted && dpc_write) dpc <= {dpc_wdata[31:1], 1'b0};
    end
endmodule
