module top_jtag (
    input wire clk, input wire rst_n,
    input wire irq_m_software, input wire irq_m_timer,
    input wire irq_m_external, input wire irq_s_software,
    input wire irq_s_timer, input wire irq_s_external, input wire nmi,
    input wire [63:0] mtime,
    input wire tck, input wire trst_n, input wire tms, input wire tdi,
    output wire tdo, output wire debug_halted,
    output wire imem_req_valid, input wire imem_req_ready,
    output wire [31:0] imem_req_addr, input wire imem_rsp_valid,
    output wire imem_rsp_ready, input wire [31:0] imem_rsp_rdata,
    input wire imem_rsp_error,
    output wire dmem_req_valid, input wire dmem_req_ready,
    output wire dmem_req_write, output wire [31:0] dmem_req_addr,
    output wire [31:0] dmem_req_wdata, output wire [3:0] dmem_req_be,
    output wire dmem_req_amo, output wire [4:0] dmem_req_amo_op,
    input wire reservation_invalidate, input wire dmem_rsp_valid,
    output wire dmem_rsp_ready, input wire [31:0] dmem_rsp_rdata,
    input wire dmem_rsp_error
);
    wire debug_req, debug_resume, debug_reg_valid, debug_reg_write;
    wire [5:0] debug_reg_addr;
    wire [63:0] debug_reg_wdata, debug_reg_rdata;
    wire debug_reg_ready, debug_dpc_write, debug_step;
    wire [31:0] debug_dpc, debug_dpc_wdata;
    wire [1:0] debug_privilege;
    riscv_debug_transport u_dtm (
        .core_clk(clk), .core_rst_n(rst_n), .tck(tck), .trst_n(trst_n),
        .tms(tms), .tdi(tdi), .tdo(tdo), .debug_req(debug_req),
        .debug_resume(debug_resume), .debug_reg_valid(debug_reg_valid),
        .debug_reg_write(debug_reg_write), .debug_reg_addr(debug_reg_addr),
        .debug_reg_wdata(debug_reg_wdata), .debug_reg_ready(debug_reg_ready),
        .debug_reg_rdata(debug_reg_rdata), .debug_halted(debug_halted),
        .debug_dpc(debug_dpc), .debug_privilege(debug_privilege),
        .debug_dpc_write(debug_dpc_write), .debug_dpc_wdata(debug_dpc_wdata),
        .debug_step(debug_step)
    );
    hybrid_top u_core (
        .clk(clk), .rst_n(rst_n), .irq_m_software(irq_m_software),
        .irq_m_timer(irq_m_timer), .irq_m_external(irq_m_external),
        .irq_s_software(irq_s_software), .irq_s_timer(irq_s_timer),
        .irq_s_external(irq_s_external), .nmi(nmi), .mtime(mtime),
        .debug_req(debug_req),
        .debug_resume(debug_resume), .debug_reg_valid(debug_reg_valid),
        .debug_reg_write(debug_reg_write), .debug_reg_addr(debug_reg_addr),
        .debug_reg_wdata(debug_reg_wdata), .debug_reg_ready(debug_reg_ready),
        .debug_reg_rdata(debug_reg_rdata), .debug_halted(debug_halted),
        .debug_dpc(debug_dpc), .debug_dpc_write(debug_dpc_write),
        .debug_dpc_wdata(debug_dpc_wdata), .debug_step(debug_step),
        .debug_privilege(debug_privilege), .imem_req_valid(imem_req_valid),
        .imem_req_ready(imem_req_ready), .imem_req_addr(imem_req_addr),
        .imem_rsp_valid(imem_rsp_valid), .imem_rsp_ready(imem_rsp_ready),
        .imem_rsp_rdata(imem_rsp_rdata), .imem_rsp_error(imem_rsp_error),
        .dmem_req_valid(dmem_req_valid), .dmem_req_ready(dmem_req_ready),
        .dmem_req_write(dmem_req_write), .dmem_req_addr(dmem_req_addr),
        .dmem_req_wdata(dmem_req_wdata), .dmem_req_be(dmem_req_be),
        .dmem_req_amo(dmem_req_amo), .dmem_req_amo_op(dmem_req_amo_op),
        .reservation_invalidate(reservation_invalidate),
        .dmem_rsp_valid(dmem_rsp_valid), .dmem_rsp_ready(dmem_rsp_ready),
        .dmem_rsp_rdata(dmem_rsp_rdata), .dmem_rsp_error(dmem_rsp_error)
    );
endmodule
