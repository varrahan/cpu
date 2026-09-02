module icache (
    input wire clk, rst_n, cancel, invalidate, cpu_valid,
    input wire [31:2] cpu_addr, cpu_next_addr, input wire cpu_need_next,
    output wire [31:0] cpu_rdata, output wire [15:0] cpu_rdata_next,
    output wire cpu_current_ready, cpu_ready, cpu_error, mem_req_valid,
    input wire mem_req_allow, mem_req_ready, output wire [31:0] mem_req_addr,
    input wire mem_rsp_valid, output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata, input wire mem_rsp_error
);
    (* anyseq *) wire [31:0] any_rdata, any_addr;
    (* anyseq *) wire [15:0] any_rdata_next;
    (* anyseq *) wire [4:0] any_control;
    assign cpu_rdata = any_rdata;
    assign cpu_rdata_next = any_rdata_next;
    assign {cpu_current_ready, cpu_ready, cpu_error, mem_req_valid,
            mem_rsp_ready} = any_control;
    assign mem_req_addr = any_addr;
endmodule

module dcache (
    input wire clk, rst_n, cpu_valid, cpu_write, cpu_double, cpu_amo,
    input wire [4:0] cpu_amo_op, input wire [31:0] cpu_addr, cpu_wdata,
    input wire [63:0] cpu_wdata64, input wire [3:0] cpu_be,
    output wire [31:0] cpu_rdata, output wire [63:0] cpu_rdata64,
    output wire cpu_ready, cpu_error, input wire reservation_invalidate,
    output wire mem_req_valid, input wire mem_req_allow, mem_req_ready,
    output wire mem_req_write, output wire [31:0] mem_req_addr,
    output wire [31:0] mem_req_wdata, output wire [3:0] mem_req_be,
    output wire mem_req_amo, output wire [4:0] mem_req_amo_op,
    input wire mem_rsp_valid, output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata, input wire mem_rsp_error
);
    (* anyseq *) wire [63:0] any_rdata64;
    (* anyseq *) wire [31:0] any_addr, any_wdata;
    (* anyseq *) wire [4:0] any_amo_op;
    (* anyseq *) wire [3:0] any_be;
    (* anyseq *) wire [5:0] any_control;
    assign cpu_rdata = any_rdata64[31:0];
    assign cpu_rdata64 = any_rdata64;
    assign {cpu_ready, cpu_error, mem_req_valid, mem_req_write, mem_req_amo,
            mem_rsp_ready} = any_control;
    assign mem_req_addr = any_addr;
    assign mem_req_wdata = any_wdata;
    assign mem_req_be = any_be;
    assign mem_req_amo_op = any_amo_op;
endmodule

module sv32_mmu (
    input wire clk, rst_n, flush, req_valid, input wire [31:0] vaddr,
    input wire [1:0] privilege, input wire access_read, access_write,
    access_execute, mstatus_sum, mstatus_mxr, input wire [31:0] satp,
    output wire resp_ready, output wire [31:0] paddr,
    output wire page_fault, access_fault, mem_req_valid,
    input wire mem_req_ready, mem_req_allow, output wire mem_req_write,
    output wire [31:0] mem_req_addr, mem_req_wdata,
    output wire [3:0] mem_req_be, output wire mem_req_amo,
    output wire [4:0] mem_req_amo_op, input wire mem_rsp_valid,
    output wire mem_rsp_ready, input wire [31:0] mem_rsp_rdata,
    input wire mem_rsp_error
);
    (* anyseq *) wire [31:0] any_paddr, any_addr, any_wdata;
    (* anyseq *) wire [4:0] any_amo_op;
    (* anyseq *) wire [3:0] any_be;
    (* anyseq *) wire [6:0] any_control;
    assign {resp_ready, page_fault, access_fault, mem_req_valid, mem_req_write,
            mem_req_amo, mem_rsp_ready} = any_control;
    assign paddr = any_paddr;
    assign mem_req_addr = any_addr;
    assign mem_req_wdata = any_wdata;
    assign mem_req_be = any_be;
    assign mem_req_amo_op = any_amo_op;
endmodule
