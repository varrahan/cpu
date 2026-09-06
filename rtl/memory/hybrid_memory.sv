module hybrid_memory (
    input logic clk, rst_n, sfence_take, fence_i_take,
    input logic [1:0] csr_privilege, csr_data_privilege,
    input logic [31:0] csr_satp, csr_pmpcfg0,
    input logic [31:0] csr_pmpaddr0, csr_pmpaddr1, csr_pmpaddr2, csr_pmpaddr3,
    input logic csr_mstatus_sum, csr_mstatus_mxr,
    input logic fetch_valid,
    input logic [31:0] fetch_address,
    output logic fetch_ready, fetch_fault,
    output logic [31:0] fetch_cause,
    output logic [127:0] fetch_data,
    output logic [7:0] fetch_permissions,
    input logic [hybrid_pkg::LSUS-1:0] valid, ordered, cancel,
    input hybrid_pkg::entry_t op[hybrid_pkg::LSUS],
    output logic [hybrid_pkg::LSUS-1:0] done, fault,
    output logic [hybrid_pkg::LSUS-1:0][31:0] cause, tval, physical_address,
    output logic [hybrid_pkg::LSUS-1:0][63:0] result,
    output logic [hybrid_pkg::LSUS-1:0][31:0] trace_rdata, trace_wdata,
    output logic [hybrid_pkg::LSUS-1:0][3:0] trace_rmask, trace_wmask,
    output wire imem_req_valid, input wire imem_req_ready,
    output wire [31:0] imem_req_addr, input wire imem_rsp_valid,
    output wire imem_rsp_ready, input wire [31:0] imem_rsp_rdata,
    input wire imem_rsp_error,
    output wire dmem_req_valid, input wire dmem_req_ready,
    output wire dmem_req_write, output wire [31:0] dmem_req_addr, dmem_req_wdata,
    output wire [3:0] dmem_req_be, output wire dmem_req_amo,
    output wire [4:0] dmem_req_amo_op, input wire reservation_invalidate,
    input wire dmem_rsp_valid, output wire dmem_rsp_ready,
    input wire [31:0] dmem_rsp_rdata, input wire dmem_rsp_error
);
    wire [31:0] if_pc = fetch_address;
    wire immu_ready, immu_page_fault, immu_access_fault;
    wire [31:0] immu_paddr;
    wire imem_fill_allow, cache_ready, cache_error;
    wire im0_req_valid, im0_req_ready, im0_req_write, im0_req_amo;
    wire [31:0] im0_req_addr, im0_req_wdata, im0_rsp_rdata;
    wire [3:0] im0_req_be; wire [4:0] im0_req_amo_op;
    wire im0_rsp_valid, im0_rsp_ready, im0_rsp_error, im0_req_allow;
    sv32_mmu u_immu (
        .clk(clk), .rst_n(rst_n), .flush(sfence_take),
        .req_valid(fetch_valid), .vaddr(if_pc), .privilege(csr_privilege),
        .access_read(1'b0), .access_write(1'b0), .access_execute(1'b1),
        .mstatus_sum(csr_mstatus_sum), .mstatus_mxr(csr_mstatus_mxr),
        .satp(csr_satp), .resp_ready(immu_ready), .paddr(immu_paddr),
        .page_fault(immu_page_fault), .access_fault(immu_access_fault),
        .mem_req_valid(im0_req_valid), .mem_req_ready(im0_req_ready),
        .mem_req_allow(im0_req_allow), .mem_req_write(im0_req_write),
        .mem_req_addr(im0_req_addr), .mem_req_wdata(im0_req_wdata),
        .mem_req_be(im0_req_be), .mem_req_amo(im0_req_amo),
        .mem_req_amo_op(im0_req_amo_op), .mem_rsp_valid(im0_rsp_valid),
        .mem_rsp_ready(im0_rsp_ready), .mem_rsp_rdata(im0_rsp_rdata),
        .mem_rsp_error(im0_rsp_error)
    );

    pmp_checker u_if_fill_pmp (
        .addr(imem_req_addr), .size(4'd4), .privilege(csr_privilege),
        .access_read(1'b0), .access_write(1'b0), .access_execute(1'b1),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(imem_fill_allow)
    );

    hybrid_icache u_icache (
        .clk(clk), .rst_n(rst_n), .invalidate(fence_i_take),
        .valid(fetch_valid && immu_ready && !immu_page_fault && !immu_access_fault),
        .address(immu_paddr), .ready(cache_ready), .error(cache_error), .data(fetch_data),
        .mem_req_valid(imem_req_valid), .mem_req_ready(imem_req_ready),
        .mem_req_allow(imem_fill_allow), .mem_req_addr(imem_req_addr),
        .mem_rsp_valid(imem_rsp_valid), .mem_rsp_ready(imem_rsp_ready),
        .mem_rsp_error(imem_rsp_error), .mem_rsp_rdata(imem_rsp_rdata)
    );
    for (genvar i=0; i<8; i++) begin: fetch_pmp
        pmp_checker check_halfword (
            .addr(immu_paddr + 32'(i*2)), .size(4'd2), .privilege(csr_privilege),
            .access_read(1'b0), .access_write(1'b0), .access_execute(1'b1),
            .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0), .pmpaddr1(csr_pmpaddr1),
            .pmpaddr2(csr_pmpaddr2), .pmpaddr3(csr_pmpaddr3), .allow(fetch_permissions[i])
        );
    end
    assign fetch_ready = fetch_valid && immu_ready &&
                         (immu_page_fault || immu_access_fault || cache_ready);
    assign fetch_fault = immu_page_fault || immu_access_fault || cache_error;
    assign fetch_cause = immu_page_fault ? 12 : 1;
    wire [1:0] dm_req_valid, dm_req_ready, dm_req_write, dm_req_amo;
    wire [1:0][31:0] dm_req_addr, dm_req_wdata, dm_rsp_rdata;
    wire [1:0][3:0] dm_req_be;
    wire [1:0][4:0] dm_req_amo_op;
    wire [1:0] dm_rsp_valid, dm_rsp_ready, dm_rsp_error, dm_req_allow;
    wire [1:0] cache_valid, cache_write, cache_double, cache_cacheable, cache_amo;
    wire [1:0][4:0] cache_amo_op;
    wire [1:0][31:0] cache_addr, cache_wdata, cache_rdata;
    wire [1:0][63:0] cache_wdata64, cache_rdata64;
    wire [1:0][3:0] cache_be;
    wire [1:0] cache_ready_data, cache_error_data, cache_owned;
    logic cache_busy, cache_owner;
    wire owner = cache_busy ? cache_owner : !cache_valid[0];
    wire primary_valid = cache_busy || (|cache_valid);
    wire primary_ready, primary_error, parallel_hit;
    wire [31:0] primary_rdata;
    wire [63:0] primary_rdata64, parallel_rdata;
    // ponytail: one shared miss path; add MSHRs and external transaction tags
    // when sustained dual-miss throughput is required.
    // Hold a miss/store/atomic's owner until completion. The other LSU may
    // complete a read hit through the cache's separate physical read ports.
    always_ff @(posedge clk) begin
        if(!rst_n) begin cache_busy<=0;cache_owner<=0;end
        else if(primary_valid) begin
            cache_busy<=!primary_ready;cache_owner<=owner;
        end
    end
    for(genvar i=0;i<hybrid_pkg::LSUS;i++) begin: lsus
        hybrid_pkg::entry_t operation;
        assign operation=op[i];
        wire lane_valid=valid[i];
        assign cache_owned[i]=cache_busy && cache_owner==i;
        assign cache_ready_data[i]=owner==i ? primary_ready :
            cache_valid[i] && !cache_write[i] && !cache_amo[i] && cache_cacheable[i] && parallel_hit;
        assign cache_error_data[i]=owner==i && primary_error;
        assign cache_rdata[i]=owner==i ? primary_rdata : parallel_rdata[31:0];
        assign cache_rdata64[i]=owner==i ? primary_rdata64 : parallel_rdata;
        wire [31:0] alu_result = operation.operands[0][31:0] + operation.d.imm;
        wire ex_mem_read = operation.d.mem_read, ex_mem_write = operation.d.mem_write;
        wire ex_fp_load = operation.d.fp_load, ex_fp_store = operation.d.fp_store;
        wire ex_amo = operation.d.amo;
        wire [4:0] ex_amo_op = operation.d.amo_op;
        wire data_store_ex = ex_mem_write || ex_fp_store || (ex_amo && ex_amo_op != 2);
        wire [3:0] data_access_size = operation.d.funct3 == 3 ? 8 :
            operation.d.funct3 == 2 || ex_amo ? 4 : operation.d.funct3[1:0] == 1 ? 2 : 1;
        wire data_misaligned = (alu_result & (32'(data_access_size)-1)) != 0;
        wire dmmu_request = lane_valid && !data_misaligned;
        wire dmmu_ready, dmmu_page_fault, dmmu_access_fault;
        wire [31:0] dmmu_paddr;
        sv32_mmu u_dmmu (
            .clk(clk), .rst_n(rst_n), .flush(sfence_take),
            .req_valid(dmmu_request), .vaddr(alu_result),
            .privilege(csr_data_privilege),
            .access_read(ex_mem_read || ex_fp_load ||
                         (ex_amo && ex_amo_op != 5'b00011)),
            .access_write(data_store_ex), .access_execute(1'b0),
            .mstatus_sum(csr_mstatus_sum), .mstatus_mxr(csr_mstatus_mxr),
            .satp(csr_satp), .resp_ready(dmmu_ready), .paddr(dmmu_paddr),
            .page_fault(dmmu_page_fault), .access_fault(dmmu_access_fault),
            .mem_req_valid(dm_req_valid[i]), .mem_req_ready(dm_req_ready[i]),
            .mem_req_allow(dm_req_allow[i]), .mem_req_write(dm_req_write[i]),
            .mem_req_addr(dm_req_addr[i]), .mem_req_wdata(dm_req_wdata[i]),
            .mem_req_be(dm_req_be[i]), .mem_req_amo(dm_req_amo[i]),
            .mem_req_amo_op(dm_req_amo_op[i]), .mem_rsp_valid(dm_rsp_valid[i]),
            .mem_rsp_ready(dm_rsp_ready[i]), .mem_rsp_rdata(dm_rsp_rdata[i]),
            .mem_rsp_error(dm_rsp_error[i])
        );
        wire data_pmp_allow;
        pmp_checker u_data_pmp (
            .addr(dmmu_paddr), .size(data_access_size),
            .privilege(csr_data_privilege),
            .access_read(ex_mem_read || ex_fp_load ||
                         (ex_amo && ex_amo_op != 5'b00011)),
            .access_write(data_store_ex), .access_execute(1'b0),
            .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
            .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
            .pmpaddr3(csr_pmpaddr3), .allow(data_pmp_allow)
        );
        wire [31:0] mem_alu_result = dmmu_paddr;
        wire [31:0] mem_rs2_data = operation.operands[1][31:0];
        wire [2:0] mem_funct3 = operation.d.funct3;
        wire [63:0] mem_fp_data = operation.operands[1];
        wire mem_fp_load = ex_fp_load, mem_fp_store = ex_fp_store;
        wire mem_mem_read = ex_mem_read, mem_mem_write = ex_mem_write, mem_amo = ex_amo;
        wire [4:0] mem_amo_op = ex_amo_op;
        wire mem_valid = lane_valid && dmmu_ready && !data_misaligned;
        wire mem_exception = dmmu_page_fault || dmmu_access_fault || !data_pmp_allow;
        wire [31:0] dcache_cpu_rdata;
        wire [63:0] dcache_cpu_rdata64;
        wire        dcache_cpu_ready, dcache_cpu_error;
        wire [31:0] mem_store_wdata, mem_load_rdata;
        wire [3:0]  mem_store_be;
        wire        mem_misaligned_unused;

        memory_stage u_memory_format (
            .addr        (mem_alu_result[1:0]),
            .wdata       (mem_rs2_data),
            .funct3      (mem_funct3),
            .word_rdata  (dcache_cpu_rdata),
            .store_wdata (mem_store_wdata),
            .store_be    (mem_store_be),
            .load_rdata  (mem_load_rdata),
            .misaligned  (mem_misaligned_unused)
        );

        wire cacheable = mem_alu_result < 32'h0200_0000 || mem_alu_result >= 32'h2000_0000;
        wire dcache_cpu_valid = !cancel[i] && (ordered[i] || (cacheable && !data_store_ex && !ex_amo)) && mem_valid && !mem_exception &&
                                (mem_mem_read || mem_mem_write || mem_amo ||
                                 mem_fp_load || mem_fp_store);
        wire dcache_cpu_write = mem_mem_write || mem_fp_store;
        wire dcache_cpu_double = (mem_fp_load || mem_fp_store) &&
                                  mem_funct3 == 3'b011;
        wire [31:0] dcache_store_wdata = mem_fp_store
                                         ? mem_fp_data[31:0] : mem_store_wdata;
        wire [3:0] dcache_store_be = mem_fp_store ? 4'b1111 : mem_store_be;
        pmp_checker u_dm_ptw_pmp (
            .addr(dm_req_addr[i]), .size(4'd4), .privilege(2'b01),
            .access_read(1'b1), .access_write(dm_req_amo[i]), .access_execute(1'b0),
            .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
            .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
            .pmpaddr3(csr_pmpaddr3), .allow(dm_req_allow[i])
        );


        assign cache_valid[i]=dcache_cpu_valid;
        assign cache_write[i]=dcache_cpu_write;
        assign cache_double[i]=dcache_cpu_double;
        assign cache_cacheable[i]=cacheable;
        assign cache_amo[i]=mem_amo;
        assign cache_amo_op[i]=mem_amo_op;
        assign cache_addr[i]=mem_alu_result;
        assign cache_wdata[i]=dcache_store_wdata;
        assign cache_wdata64[i]=mem_fp_data;
        assign cache_be[i]=dcache_store_be;
        assign dcache_cpu_rdata=cache_rdata[i];
        assign dcache_cpu_rdata64=cache_rdata64[i];
        assign dcache_cpu_ready=cache_ready_data[i];
        assign dcache_cpu_error=cache_error_data[i];
        assign done[i] = lane_valid && (data_misaligned || (dmmu_ready &&
            (mem_exception || dcache_cpu_ready || (cancel[i] && !cache_owned[i]))));
        assign fault[i] = data_misaligned || mem_exception || dcache_cpu_error;
        assign cause[i] = data_misaligned ? (data_store_ex ? 6 : 4) :
            dmmu_page_fault ? (data_store_ex ? 15 : 13) : (data_store_ex ? 7 : 5);
        assign tval[i] = alu_result;
        assign physical_address[i] = dmmu_paddr;
        assign result[i] = ex_fp_load ? (operation.d.funct3 == 3 ? dcache_cpu_rdata64 :
            {32'hffffffff, dcache_cpu_rdata}) : {32'b0, ex_amo ? dcache_cpu_rdata : mem_load_rdata};
        assign trace_rdata[i] = dcache_cpu_rdata;
        function automatic [31:0] trace_amo_result;
            input [4:0] op;
            input [31:0] old_value, operand;
            begin
                case (op)
                    5'b00000: trace_amo_result = old_value + operand;
                    5'b00100: trace_amo_result = old_value ^ operand;
                    5'b01100: trace_amo_result = old_value & operand;
                    5'b01000: trace_amo_result = old_value | operand;
                    5'b10000: trace_amo_result = $signed(old_value) <
                                                        $signed(operand)
                                                 ? old_value : operand;
                    5'b10100: trace_amo_result = $signed(old_value) >
                                                        $signed(operand)
                                                 ? old_value : operand;
                    5'b11000: trace_amo_result = old_value < operand
                                                 ? old_value : operand;
                    5'b11100: trace_amo_result = old_value > operand
                                                 ? old_value : operand;
                    default:  trace_amo_result = operand;
                endcase
            end
        endfunction
        assign trace_wdata[i] = ex_amo ? trace_amo_result(ex_amo_op, dcache_cpu_rdata, mem_rs2_data) : dcache_store_wdata;
        assign trace_rmask[i] = !fault[i] && (ex_mem_read || (ex_amo && ex_amo_op != 3)) ?
            (operation.d.funct3[1:0] == 0 ? (4'b1 << alu_result[1:0]) :
             operation.d.funct3[1:0] == 1 ? (4'b11 << {alu_result[1],1'b0}) : 4'b1111) : 0;
        assign trace_wmask[i] = !fault[i] && (ex_mem_write || (ex_amo && ex_amo_op != 2 &&
            (ex_amo_op != 3 || dcache_cpu_rdata == 0))) ? dcache_store_be : 0;
    end
    wire dc_req_valid, dc_req_ready, dc_req_write, dc_req_amo;
    wire [31:0] dc_req_addr, dc_req_wdata, dc_rsp_rdata;
    wire [3:0] dc_req_be; wire [4:0] dc_req_amo_op;
    wire dc_rsp_valid, dc_rsp_ready, dc_rsp_error, dc_req_allow;
    pmp_checker u_dmem_fill_pmp (
        .addr(dc_req_addr), .size(4'd4), .privilege(csr_data_privilege),
        .access_read(!dc_req_write ||
                     (dc_req_amo && dc_req_amo_op != 5'b00011)),
        .access_write(dc_req_write ||
                      (dc_req_amo && dc_req_amo_op != 5'b00010)),
        .access_execute(1'b0), .pmpcfg0(csr_pmpcfg0),
        .pmpaddr0(csr_pmpaddr0), .pmpaddr1(csr_pmpaddr1),
        .pmpaddr2(csr_pmpaddr2), .pmpaddr3(csr_pmpaddr3),
        .allow(dc_req_allow)
    );

    dcache u_dcache (
        .parallel_addr(cache_addr[!owner]),.parallel_rdata,.parallel_hit,
        .clk           (clk),
        .rst_n         (rst_n),
        .cpu_valid     (primary_valid),
        .cpu_write     (cache_write[owner]),
        .cpu_double    (cache_double[owner]),
        .cpu_cacheable (cache_cacheable[owner]),
        .cpu_amo       (cache_amo[owner]),
        .cpu_amo_op    (cache_amo_op[owner]),
        .cpu_addr      (cache_addr[owner]),
        .cpu_wdata     (cache_wdata[owner]),
        .cpu_wdata64   (cache_wdata64[owner]),
        .cpu_be        (cache_be[owner]),
        .cpu_rdata     (primary_rdata),
        .cpu_rdata64   (primary_rdata64),
        .cpu_ready     (primary_ready),
        .cpu_error     (primary_error),
        .reservation_invalidate(reservation_invalidate ||
            (dmem_req_valid && dmem_req_ready && dmem_req_amo)),
        .mem_req_valid (dc_req_valid),
        .mem_req_allow (dc_req_allow),
        .mem_req_ready (dc_req_ready),
        .mem_req_write (dc_req_write),
        .mem_req_addr  (dc_req_addr),
        .mem_req_wdata (dc_req_wdata),
        .mem_req_be    (dc_req_be),
        .mem_req_amo   (dc_req_amo),
        .mem_req_amo_op(dc_req_amo_op),
        .mem_rsp_valid (dc_rsp_valid),
        .mem_rsp_ready (dc_rsp_ready),
        .mem_rsp_rdata (dc_rsp_rdata),
        .mem_rsp_error (dc_rsp_error)
    );

    pmp_checker u_im0_ptw_pmp (
        .addr(im0_req_addr), .size(4'd4), .privilege(2'b01),
        .access_read(1'b1), .access_write(im0_req_amo), .access_execute(1'b0),
        .pmpcfg0(csr_pmpcfg0), .pmpaddr0(csr_pmpaddr0),
        .pmpaddr1(csr_pmpaddr1), .pmpaddr2(csr_pmpaddr2),
        .pmpaddr3(csr_pmpaddr3), .allow(im0_req_allow)
    );
    memory_arbiter4 u_dmem_arbiter (
        .clk(clk), .rst_n(rst_n),
        .m0_req_valid(dm_req_valid[0]), .m0_req_ready(dm_req_ready[0]),
        .m0_req_write(dm_req_write[0]), .m0_req_addr(dm_req_addr[0]),
        .m0_req_wdata(dm_req_wdata[0]), .m0_req_be(dm_req_be[0]),
        .m0_req_amo(dm_req_amo[0]), .m0_req_amo_op(dm_req_amo_op[0]),
        .m0_rsp_valid(dm_rsp_valid[0]), .m0_rsp_ready(dm_rsp_ready[0]),
        .m0_rsp_rdata(dm_rsp_rdata[0]), .m0_rsp_error(dm_rsp_error[0]),
        .m1_req_valid(dm_req_valid[1]), .m1_req_ready(dm_req_ready[1]),
        .m1_req_write(dm_req_write[1]), .m1_req_addr(dm_req_addr[1]),
        .m1_req_wdata(dm_req_wdata[1]), .m1_req_be(dm_req_be[1]),
        .m1_req_amo(dm_req_amo[1]), .m1_req_amo_op(dm_req_amo_op[1]),
        .m1_rsp_valid(dm_rsp_valid[1]), .m1_rsp_ready(dm_rsp_ready[1]),
        .m1_rsp_rdata(dm_rsp_rdata[1]), .m1_rsp_error(dm_rsp_error[1]),
        .m2_req_valid(im0_req_valid), .m2_req_ready(im0_req_ready),
        .m2_req_write(im0_req_write), .m2_req_addr(im0_req_addr),
        .m2_req_wdata(im0_req_wdata), .m2_req_be(im0_req_be),
        .m2_req_amo(im0_req_amo), .m2_req_amo_op(im0_req_amo_op),
        .m2_rsp_valid(im0_rsp_valid), .m2_rsp_ready(im0_rsp_ready),
        .m2_rsp_rdata(im0_rsp_rdata), .m2_rsp_error(im0_rsp_error),
        .m3_req_valid(dc_req_valid), .m3_req_ready(dc_req_ready),
        .m3_req_write(dc_req_write), .m3_req_addr(dc_req_addr),
        .m3_req_wdata(dc_req_wdata), .m3_req_be(dc_req_be),
        .m3_req_amo(dc_req_amo), .m3_req_amo_op(dc_req_amo_op),
        .m3_rsp_valid(dc_rsp_valid), .m3_rsp_ready(dc_rsp_ready),
        .m3_rsp_rdata(dc_rsp_rdata), .m3_rsp_error(dc_rsp_error),
        .ext_req_valid(dmem_req_valid), .ext_req_ready(dmem_req_ready),
        .ext_req_write(dmem_req_write), .ext_req_addr(dmem_req_addr),
        .ext_req_wdata(dmem_req_wdata), .ext_req_be(dmem_req_be),
        .ext_req_amo(dmem_req_amo), .ext_req_amo_op(dmem_req_amo_op),
        .ext_rsp_valid(dmem_rsp_valid), .ext_rsp_ready(dmem_rsp_ready),
        .ext_rsp_rdata(dmem_rsp_rdata), .ext_rsp_error(dmem_rsp_error)
    );

    // synthesis translate_off
    always @(posedge clk) if(rst_n) begin
        for(integer i=0;i<hybrid_pkg::LSUS;i++) begin
            if(cache_valid[i] && (!cache_cacheable[i] || cache_write[i] || cache_amo[i]))
                assert(ordered[i]);
            if(cache_owned[i]) assert(valid[i]);
        end
        if(primary_valid && cache_busy) assert(owner==cache_owner);
    end
    // synthesis translate_on
endmodule
