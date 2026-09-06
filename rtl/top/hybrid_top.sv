module hybrid_top #(
    parameter int FABRIC_BITS_PER_CYCLE = hybrid_pkg::MESSAGE_BITS,
    parameter int FABRIC_FLIGHT_CYCLES = 1,
    parameter int FABRIC_CREDIT_CYCLES = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        irq_m_software,
    input  wire        irq_m_timer,
    input  wire        irq_m_external,
    input  wire        irq_s_software,
    input  wire        irq_s_timer,
    input  wire        irq_s_external,
    input  wire        nmi,
    input  wire [63:0] mtime,
    input  wire        debug_req,
    input  wire        debug_resume,
    input  wire        debug_reg_valid,
    input  wire        debug_reg_write,
    input  wire [5:0]  debug_reg_addr,
    input  wire [63:0] debug_reg_wdata,
    output wire        debug_reg_ready,
    output wire [63:0] debug_reg_rdata,
    output wire        debug_halted,
    output wire [31:0] debug_dpc,
    input  wire        debug_dpc_write,
    input  wire [31:0] debug_dpc_wdata,
    input  wire        debug_step,
    output wire [1:0]  debug_privilege,

    output wire        imem_req_valid,
    input  wire        imem_req_ready,
    output wire [31:0] imem_req_addr,
    input  wire        imem_rsp_valid,
    output wire        imem_rsp_ready,
    input  wire [31:0] imem_rsp_rdata,
    input  wire        imem_rsp_error,

    output wire        dmem_req_valid,
    input  wire        dmem_req_ready,
    output wire        dmem_req_write,
    output wire [31:0] dmem_req_addr,
    output wire [31:0] dmem_req_wdata,
    output wire [3:0]  dmem_req_be,
    output wire        dmem_req_amo,
    output wire [4:0]  dmem_req_amo_op,
    input  wire        reservation_invalidate,
    input  wire        dmem_rsp_valid,
    output wire        dmem_rsp_ready,
    input  wire [31:0] dmem_rsp_rdata,
    input  wire        dmem_rsp_error
`ifdef RISCV_FORMAL
    ,
    output reg [3:0] rvfi_valid,
    output reg [3:0] [63:0] rvfi_order,
    output reg [3:0] [31:0] rvfi_insn,
    output reg [3:0] rvfi_trap,
    output reg [3:0] rvfi_halt,
    output reg [3:0] rvfi_intr,
    output reg [3:0] [1:0] rvfi_mode,
    output wire [3:0] [1:0] rvfi_ixl,
    output reg [3:0] [4:0] rvfi_rs1_addr,
    output reg [3:0] [4:0] rvfi_rs2_addr,
    output reg [3:0] [31:0] rvfi_rs1_rdata,
    output reg [3:0] [31:0] rvfi_rs2_rdata,
    output reg [3:0] [4:0] rvfi_rd_addr,
    output reg [3:0] [31:0] rvfi_rd_wdata,
    output reg [3:0] [31:0] rvfi_pc_rdata,
    output reg [3:0] [31:0] rvfi_pc_wdata,
    output reg [3:0] [31:0] rvfi_mem_addr,
    output reg [3:0] [3:0] rvfi_mem_rmask,
    output reg [3:0] [3:0] rvfi_mem_wmask,
    output reg [3:0] [31:0] rvfi_mem_rdata,
    output reg [3:0] [31:0] rvfi_mem_wdata,
    output reg [3:0] rvfi_frd_valid,
    output reg [3:0] [4:0] rvfi_frd_addr,
    output reg [3:0] [63:0] rvfi_frd_wdata,
    output reg [3:0] rvfi_csr_valid,
    output reg [3:0] [11:0] rvfi_csr_addr,
    output reg [3:0] [31:0] rvfi_csr_wdata
`endif
);
    import hybrid_pkg::*;
    localparam int RESULT=36, FETCH_REQ=RESULT+UNITS, FETCH_RSP=FETCH_REQ+1;
    entry_t entries[ROB], memory_op[LSUS], memory_completion[LSUS];
    wire [ROB*$bits(entry_t)-1:0] rob_data;
    for(genvar row=0;row<ROB;row++)
        assign entries[row]=rob_data[row*$bits(entry_t)+:$bits(entry_t)];
    logic [4:0] prf_raddr[16][2], prf_waddr[16];
    logic [63:0] prf_rdata[16][2], prf_wdata[16];
    logic [15:0] prf_we;
    logic [7:0] speculative[2][32], committed[2][32];
    wire [7:0] debug_physical=committed[debug_reg_addr[5]][debug_reg_addr[4:0]];
    wire [3:0] debug_bank={debug_reg_addr[5],debug_physical[2:0]};
    // Physically separate 32-row banks: two reads and one write per bank.
    for(genvar b=0;b<16;b++) begin: prf_banks
        localparam BITS=b<8?32:64;
        wire [2*BITS-1:0] data;
        async_memory #(.DATA_WIDTH(BITS),.ADDR_WIDTH(5),.READ_PORTS(2)) storage (
            .clk,.rst_n,.we(prf_we[b]),.waddr(prf_waddr[b]),.wdata(prf_wdata[b][BITS-1:0]),.wbe(1'b1),
            .raddr({prf_raddr[b][1],prf_raddr[b][0]}),.rdata(data));
        assign prf_rdata[b][0]=64'(data[0+:BITS]);
        assign prf_rdata[b][1]=64'(data[BITS+:BITS]);
    end
`ifndef SYNTHESIS
    // Verification view only; it does not add physical read ports.
    wire [63:0] registers[2][PHYS];
    for(genvar b=0;b<16;b++) for(genvar r=0;r<32;r++)
        assign registers[b/8][r*8+b%8]=prf_banks[b].storage.mem[r];
`endif
    logic [PHYS-1:0] free_regs[2], reg_ready[2];
    logic [PHYS-1:0] acknowledged[2];
    logic [6:0] head, tail;
    integer occupancy, allocation_bank, queue_count, memory_count;
    logic [31:0] pc, epoch;
    logic frontend_blocked;
    logic [31:0] line_address[8], line_cause[8];
    logic [127:0] line_data[8];
    logic [7:0] line_permissions[8];
    logic [7:0] line_valid, line_fault;
    logic [31:0] fetch_cursor;
    logic fetch_active, fetch_finished, fetch_quiet;
    logic [CHANNELS-1:0] channel_idle;
    message_t fetch_request, fetch_response, tx[CHANNELS], rx[CHANNELS];
    // Keep indexed writes word-sized before connecting the packed fabric ports.
    message_t routed[CHANNELS], bank_packets[32];
    // Indexed bank writes cannot target execution or fetch producer channels.
    for(genvar c=0;c<CHANNELS;c++) begin: transmitters
        if(c>=4 && c<RESULT) assign tx[c]=bank_packets[c-4];
        else assign tx[c]=routed[c];
    end
    logic [CHANNELS-1:0] tx_valid, tx_ready, rx_valid, rx_ready;
    logic [2:0] served[4];
    integer read_owner[32], read_operand[32];
    logic [1:0] bank_reads[16];
    logic bank_writes[16];
    integer selected[4], executing[UNITS];
    logic [31:0] alu_a[ALUS], alu_b[ALUS], alu_result[ALUS];
    logic [3:0] alu_op[ALUS];
    logic [31:0] dec_pc[4], dec_raw[4], dec_instruction[4], dec_cause[4], dec_tval[4];
    logic [2:0] dec_length[4];
    logic [3:0] dec_valid, dec_fault, dec_bad;
    decode_t decoded[4];
    logic [2:0] commit_count;
    logic [31:0] commit_next_pc, redirect_pc, trap_pc, trap_cause, trap_tval;
    logic fault_take, interrupt_take, flush, control_take, wfi_sleep, trap_take;
    logic debug_enter, debug_resume_fire, step_active;
    logic [1:0] csr_privilege, csr_data_privilege;
    logic [31:0] csr_satp, csr_pmpcfg0, csr_pmpaddr0, csr_pmpaddr1, csr_pmpaddr2, csr_pmpaddr3;
    logic csr_mstatus_sum, csr_mstatus_mxr;
    logic [31:0] csr_read_data, csr_read_modify_data, csr_commit_visible_data;
    logic csr_read_illegal, csr_interrupt_pending, csr_wfi_wake_pending;
    logic [31:0] csr_interrupt_cause, csr_trap_vector, csr_return_pc, csr_sreturn_pc;
    logic [2:0] csr_frm;
    logic csr_fp_enabled, csr_mret_allowed, csr_sret_allowed, csr_sfence_allowed, csr_wfi_allowed;
    logic csr_write_intent, csr_commit_valid, fp_flags_commit, fp_dirty_commit;
    logic [31:0] csr_source, csr_write_data;
    logic [4:0] commit_flags;
    logic mret_take, sret_take, sfence_take, fence_i_take;
    logic [1:0] irq_sync[7];
    wire [6:0] irq_inputs={nmi,irq_s_external,irq_s_timer,irq_s_software,
                          irq_m_external,irq_m_timer,irq_m_software};
    logic [MULDIVS-1:0] mul_active, mul_complete, mul_start, mul_ready, mul_done;
    logic [FPUS-1:0] fp_active, fp_complete, fp_start, fp_ready, fp_done, fp_illegal;
    logic [LSUS-1:0] mem_active, mem_complete, mem_killed, memory_start;
    logic [LSUS-1:0] memory_valid, memory_ordered, memory_cancel, memory_done, memory_fault;
    logic [MULDIVS-1:0][6:0] mul_slot;
    logic [FPUS-1:0][6:0] fp_slot;
    logic [LSUS-1:0][6:0] mem_slot;
    logic [MULDIVS-1:0][31:0] mul_result, mul_saved, mul_a, mul_b;
    logic [MULDIVS-1:0][2:0] mul_op;
    logic [FPUS-1:0][31:0] fp_instruction, fp_int;
    logic [FPUS-1:0][63:0] fp_result, fp_saved, fp_a, fp_b, fp_c;
    logic [FPUS-1:0][4:0] fp_flags, fp_saved_flags;
    logic fetch_ready, fetch_fault;
    logic [31:0] fetch_cause;
    logic [LSUS-1:0][31:0] memory_cause, memory_tval, memory_paddr, memory_rdata, memory_wdata;
    logic [LSUS-1:0][63:0] memory_result;
    logic [LSUS-1:0][3:0] memory_rmask, memory_wmask;
    wire memory_quiet = !(|mem_active);
    wire memory_drain = debug_req || step_active || csr_interrupt_pending ||
                       (occupancy!=0 && entries[head].done && entries[head].fault);
    logic [127:0] fetched_data;
    logic [7:0] fetched_permissions;
    always_ff @(posedge clk)
        for (int i=0;i<7;i++)
            if (!rst_n) irq_sync[i]<=0; else irq_sync[i]<={irq_sync[i][0],irq_inputs[i]};
    wdm_fabric #(.BITS_PER_CYCLE(FABRIC_BITS_PER_CYCLE),
        .FLIGHT_CYCLES(FABRIC_FLIGHT_CYCLES), .CREDIT_CYCLES(FABRIC_CREDIT_CYCLES)) fabric (
        .clk, .rst_n, .flush, .tx_valid, .tx_ready, .tx_data(tx),
        .rx_valid, .rx_ready, .rx_data(rx), .idle(), .channel_idle);
    assign fetch_quiet = !fetch_active && (&channel_idle[FETCH_RSP:FETCH_REQ]);
    for (genvar i=0;i<4;i++) begin: lanes
        wire [31:0] decompressed;
        wire compressed_bad;
        rvc_decompressor decompress (.compressed(dec_raw[i][15:0]), .instruction(decompressed), .illegal(compressed_bad));
        assign dec_instruction[i]=dec_length[i]==2?decompressed:dec_raw[i];
        assign dec_bad[i]=dec_length[i]==2 && compressed_bad;
        decoder decode (.instr(dec_instruction[i]), .decoded(decoded[i]));
    end
    for(genvar i=0;i<ALUS;i++) begin: alus
        alu integer_alu (.a(alu_a[i]), .b(alu_b[i]), .alu_op(alu_op[i]), .result(alu_result[i]), .zero());
    end
    function automatic logic is_memory(input decode_t d);
        return d.mem_read || d.mem_write || d.fp_load || d.fp_store || d.amo;
    endfunction
    function automatic logic older(input integer candidate, input integer current);
        return current<0 || 7'(candidate-int'(head))<7'(current-int'(head));
    endfunction
    function automatic logic is_control(input decode_t d);
        return d.branch || d.jal || d.jalr || d.csr_en || d.fence || d.fence_i ||
               d.mret || d.sret || d.sfence_vma || d.wfi || d.ecall || d.ebreak;
    endfunction
    function automatic logic fp_destination(input logic [31:0] insn,input decode_t d);
        return d.fp_load || (d.fp_compute && (insn[6:0]!=7'h53 ||
            !(insn[31:27]==5'b10100 || insn[31:27]==5'b11000 || insn[31:27]==5'b11100)));
    endfunction
    function automatic logic branch_taken(input entry_t e);
        if (e.d.jal || e.d.jalr) return 1;
        if (!e.d.branch) return 0;
        case (e.d.funct3)
            0:return e.operands[0][31:0]==e.operands[1][31:0];
            1:return e.operands[0][31:0]!=e.operands[1][31:0];
            4:return $signed(e.operands[0][31:0])<$signed(e.operands[1][31:0]);
            5:return $signed(e.operands[0][31:0])>=$signed(e.operands[1][31:0]);
            6:return e.operands[0][31:0]<e.operands[1][31:0];
            7:return e.operands[0][31:0]>=e.operands[1][31:0];
            default:return 0;
        endcase
    endfunction
    // Each aligned line is independently translated; faults in the following
    // page are consumed only by instructions that actually cross into it.
    always_comb begin: align_fetch
        logic stop, available;
        logic [31:0] cursor;
        integer b,h,n;
        logic [15:0] first_half,second_half;
        stop=frontend_blocked || debug_halted || wfi_sleep || debug_req || csr_interrupt_pending; cursor=pc;
        for(int i=0;i<4;i++) begin
            dec_pc[i]=cursor; dec_raw[i]=0; dec_length[i]=2; dec_valid[i]=0;
            dec_fault[i]=0; dec_cause[i]=0; dec_tval[i]=cursor;
            b=int'(cursor[6:4]); h=int'(cursor[3:1]); n=b;
            first_half=line_data[b][h*16+:16]; second_half=0;
            available=line_valid[b] && line_address[b]=={cursor[31:4],4'b0};
            if(!stop && available) begin
                dec_fault[i]=line_fault[b] || !line_permissions[b][h] || cursor[0];
                dec_cause[i]=cursor[0]?0:line_fault[b]?line_cause[b]:1;
                dec_raw[i]={16'b0,first_half};
                if(!dec_fault[i] && first_half[1:0]==3) begin
                    dec_length[i]=4;
                    if(h==7) begin
                        n=(b+1)%8;
                        available=line_valid[n] && line_address[n]==({cursor[31:4],4'b0}+16);
                        second_half=line_data[n][15:0];
                        dec_fault[i]=line_fault[n] || !line_permissions[n][0];
                        dec_cause[i]=line_fault[n]?line_cause[n]:1; dec_tval[i]=cursor+2;
                    end else begin
                        second_half=line_data[b][(h+1)*16+:16];
                        dec_fault[i]=!line_permissions[b][h+1]; dec_cause[i]=1; dec_tval[i]=cursor+2;
                    end
                    dec_raw[i]={second_half,first_half};
                end
                dec_valid[i]=available;
                if(available) cursor=cursor+dec_length[i];
                if(!available || dec_fault[i] || is_control(decoded[i]) || decoded[i].illegal || dec_bad[i]) stop=1;
            end else stop=1;
        end
    end
    for(genvar i=0;i<MULDIVS;i++) begin: muldivs
        muldiv_unit u_muldiv (.clk,.rst_n,.flush,.start(mul_start[i]),.op(mul_op[i]),
            .a(mul_a[i]),.b(mul_b[i]),.ready(mul_ready[i]),.busy(),.done(mul_done[i]),.result(mul_result[i]));
    end
    for(genvar i=0;i<FPUS;i++) begin: fpus
        fpu_unit u_fpu (.clk,.rst_n,.flush,.start(fp_start[i]),.instr(fp_instruction[i]),
            .rs1_int(fp_int[i]),.frs1(fp_a[i]),.frs2(fp_b[i]),.frs3(fp_c[i]),.frm(csr_frm),
            .ready(fp_ready[i]),.busy(),.done(fp_done[i]),.illegal(fp_illegal[i]),.result(fp_result[i]),
            .flags(fp_flags[i]),.result_to_int(),.write_fp());
    end
    for(genvar i=0;i<LSUS;i++) begin: lsus
        assign memory_start[i]=executing[LSU_BASE+i]>=0 && !mem_active[i] && !flush &&
            (!memory_drain || executing[LSU_BASE+i]==int'(head));
        assign memory_valid[i]=mem_active[i] && !mem_complete[i];
        assign memory_ordered[i]=mem_slot[i]==head && !mem_killed[i];
        assign memory_cancel[i]=mem_killed[i] || (occupancy!=0 && entries[head].done && entries[head].fault && !memory_ordered[i]);
    end
    hybrid_memory memory (
        .clk,.rst_n,.sfence_take,.fence_i_take,.csr_privilege,.csr_data_privilege,.csr_satp,
        .csr_pmpcfg0,.csr_pmpaddr0,.csr_pmpaddr1,.csr_pmpaddr2,.csr_pmpaddr3,
        .csr_mstatus_sum,.csr_mstatus_mxr,
        .fetch_valid(fetch_active && !fetch_finished),.fetch_address(fetch_request.pc),
        .fetch_ready,.fetch_fault,.fetch_cause,.fetch_data(fetched_data),.fetch_permissions(fetched_permissions),
        .valid(memory_valid),.ordered(memory_ordered),.cancel(memory_cancel),.op(memory_op),.done(memory_done),.fault(memory_fault),
        .cause(memory_cause),.tval(memory_tval),.physical_address(memory_paddr),.result(memory_result),
        .trace_rdata(memory_rdata),.trace_wdata(memory_wdata),.trace_rmask(memory_rmask),.trace_wmask(memory_wmask),
        .imem_req_valid,.imem_req_ready,.imem_req_addr,.imem_rsp_valid,.imem_rsp_ready,.imem_rsp_rdata,.imem_rsp_error,
        .dmem_req_valid,.dmem_req_ready,.dmem_req_write,.dmem_req_addr,.dmem_req_wdata,.dmem_req_be,
        .dmem_req_amo,.dmem_req_amo_op,.reservation_invalidate,
        .dmem_rsp_valid,.dmem_rsp_ready,.dmem_rsp_rdata,.dmem_rsp_error);
    // Oldest-ready issue. The ROB carries IQ payloads; at most IQ entries may
    // wait for issue. Four selectors reserve distinct instructions.
    always_comb begin: select_work
        logic [ROB-1:0] operands_ready, memory_eligible, execute_ready;
        logic already, available;
        integer s, first_memory, second_memory, category;
        s=0;category=0;queue_count=0;memory_count=0;
        first_memory=-1;second_memory=-1;memory_eligible='0;
        for(int j=0;j<ROB;j++) begin
            if(entries[j].valid && !entries[j].issued && !entries[j].done) queue_count++;
            if(entries[j].valid && is_memory(entries[j].d)) memory_count++;
            if(entries[j].valid && is_memory(entries[j].d) && !entries[j].done && older(j,first_memory))
                first_memory=j;
            execute_ready[j]=entries[j].valid && entries[j].command && !entries[j].executed &&
                (entries[j].received | ~entries[j].src_used)==3'b111;
            operands_ready[j]=1;
            for(int p=0;p<3;p++)
                if(entries[j].src_used[p] && !reg_ready[entries[j].src_fp[p]][entries[j].src[p]])
                    operands_ready[j]=0;
        end
        for(int j=0;j<ROB;j++)
            if(entries[j].valid && is_memory(entries[j].d) && !entries[j].done && j!=first_memory && older(j,second_memory))
                second_memory=j;
        // Two oldest plain loads may translate and read concurrently. Stores
        // and atomics wait at head; the memory stage gates MMIO after translation.
        if(first_memory>=0) begin
            memory_eligible[first_memory]=first_memory==int'(head) ||
                !(entries[first_memory].d.mem_write || entries[first_memory].d.fp_store || entries[first_memory].d.amo);
            if(second_memory>=0 && !(entries[first_memory].d.mem_write || entries[first_memory].d.fp_store || entries[first_memory].d.amo) &&
                !(entries[second_memory].d.mem_write || entries[second_memory].d.fp_store || entries[second_memory].d.amo))
                memory_eligible[second_memory]=1;
        end
        for(int l=0;l<4;l++) begin
            selected[l]=-1;
            for(int slot=0;slot<ROB;slot++) begin
                already=0;
                for(int prev=0;prev<l;prev++) if(selected[prev]==slot) already=1;
                if(older(slot,selected[l]) && entries[slot].valid && !entries[slot].issued && !entries[slot].done &&
                    operands_ready[slot] && !already && (!is_control(entries[slot].d) || slot==int'(head)))
                    selected[l]=slot;
            end
        end
        // Commands reserve a unit class. Each available physical unit takes a
        // distinct oldest ready reservation, avoiding affinity to an issue lane.
        for(int e=0;e<UNITS;e++) begin
            executing[e]=-1;
            category=e<ALUS?0:e<FP_BASE?MUL_BASE:e<LSU_BASE?FP_BASE:LSU_BASE;
            available=e<ALUS?1:e<FP_BASE?!mul_active[e-MUL_BASE]:
                      e<LSU_BASE?!fp_active[e-FP_BASE]:!mem_active[e-LSU_BASE];
            for(int slot=0;slot<ROB;slot++) begin
                if(available && execute_ready[slot] && older(slot,executing[e]) &&
                   entries[slot].unit_id==category && (e<LSU_BASE || memory_eligible[slot]))
                    executing[e]=slot;
            end
            if(executing[e]>=0) execute_ready &= ~(ROB'(1)<<executing[e]);
        end
        for(int e=0;e<ALUS;e++) begin
            alu_a[e]=0;alu_b[e]=0;alu_op[e]=0;
            if(executing[e]>=0) begin
                s=executing[e];
                alu_a[e]=entries[s].d.lui?0:entries[s].d.auipc?entries[s].pc:entries[s].operands[0][31:0];
                alu_b[e]=entries[s].d.alu_src?entries[s].d.imm:entries[s].operands[1][31:0];
                alu_op[e]=entries[s].d.alu_op;
            end
        end
        mul_a='0;mul_b='0;mul_op='0;mul_start='0;
        for(int i=0;i<MULDIVS;i++) if(executing[MUL_BASE+i]>=0) begin
            s=executing[MUL_BASE+i];mul_a[i]=entries[s].operands[0][31:0];
            mul_b[i]=entries[s].operands[1][31:0];mul_op[i]=entries[s].d.muldiv_op;
            mul_start[i]=mul_ready[i] && !flush;
        end
        fp_instruction='0;fp_int='0;fp_a='0;fp_b='0;fp_c='0;fp_start='0;
        for(int i=0;i<FPUS;i++) if(executing[FP_BASE+i]>=0) begin
            s=executing[FP_BASE+i];fp_instruction[i]=entries[s].instruction;
            fp_int[i]=entries[s].operands[0][31:0];fp_a[i]=entries[s].operands[0];
            fp_b[i]=entries[s].operands[1];fp_c[i]=entries[s].operands[2];
            fp_start[i]=fp_ready[i] && !fp_illegal[i] && !flush;
        end
    end
    always_comb begin: route_messages
        logic signed [7:0] s;
        logic [3:0] u;
        logic [3:0] b;
        logic [5:0] p;
        message_t packet;
        logic [2:0] completed[4];
        logic [31:0] wanted;
        entry_t e;
        integer o;
        tx_valid=0;rx_ready=0;
        prf_we=0;
        for(int k=0;k<CHANNELS;k++) routed[k]='0;
        for(int k=0;k<32;k++) bank_packets[k]='0;
        for(int k=0;k<32;k++) begin read_owner[k]=-1;read_operand[k]=-1;end
        for(int k=0;k<16;k++) begin
            bank_reads[k]=0;bank_writes[k]=0;prf_waddr[k]=0;prf_wdata[k]=0;
            prf_raddr[k][0]=0;prf_raddr[k][1]=0;
        end
        for(int k=0;k<4;k++) completed[k]=served[k];
        s=0;u=0;b=0;p=0;packet='0;wanted=0;e='0;o=0;
        // Results have a dedicated producer wavelength, even when several
        // units finish together. Bank conflicts are local, never global.
        for(int k=RESULT;k<RESULT+UNITS;k++) if(rx_valid[k]) begin
            s=int'(rx[k].slot); e=entries[s];
            if(rx[k].epoch!=epoch || !e.valid) rx_ready[k]=1;
            else if(!e.dest_valid || rx[k].kind==9) rx_ready[k]=1;
            else begin
                b=int'(e.dest_fp)*8+int'(e.pdst[2:0]);p=4+2*b;
                if(bank_writes[b]==0 && tx_ready[p]) begin
                    rx_ready[k]=1;bank_writes[b]=1;bank_reads[b]=1;
                    packet=rx[k];packet.destination=255;
                    tx_valid[p]=1;bank_packets[p-4]=packet;
                    prf_we[b]=1;prf_waddr[b]=e.pdst[7:3];
                    prf_wdata[b]=e.dest_fp?rx[k].data[0]:{32'b0,rx[k].data[0][31:0]};
                end
            end
        end
        // Commands carry physical register addresses. Each read response
        // traverses the fabric back to the tagged execution reservation.
        for(int k=0;k<4;k++) if(rx_valid[k]) begin
            s=int'(rx[k].slot);
            if(rx[k].epoch!=epoch || !entries[s].valid) rx_ready[k]=1;
            else begin
                for(o=0;o<3;o++) begin
                    if(!rx[k].data[o][9]) completed[k][o]=1;
                    else if(!served[k][o]) begin
                        b=int'(rx[k].data[o][8])*8+int'(rx[k].data[o][2:0]);
                        p=4+2*b+bank_reads[b];
                        if(bank_reads[b]<2 && tx_ready[p]) begin
                            packet=rx[k];packet.kind=4'(o);packet.data='0;
                            prf_raddr[b][bank_reads[b]]=rx[k].data[o][7:3];
                            packet.data[0]=prf_rdata[b][bank_reads[b]];
                            tx_valid[p]=1;bank_packets[p-4]=packet;
                            read_owner[p-4]=k;read_operand[p-4]=o;
                            bank_reads[b]++;completed[k][o]=1;
                        end
                    end
                end
                rx_ready[k]=&completed[k];
            end
        end
        for(int k=4;k<RESULT;k++) rx_ready[k]=1;
        for(int l=0;l<4;l++) if(selected[l]>=0 && !flush && !debug_halted) begin
            s=selected[l];e=entries[s];
            u=is_memory(e.d)?4'(LSU_BASE):e.d.fp_compute?4'(FP_BASE):e.d.muldiv?4'(MUL_BASE):0;
            tx_valid[l]=1;routed[l].epoch=epoch;routed[l].slot=7'(s);routed[l].destination=8'(u);
            routed[l].instruction=e.instruction;routed[l].pc=e.pc;
            for(o=0;o<3;o++) routed[l].data[o]={54'b0,e.src_used[o],e.src_fp[o],e.src[o]};
        end
        for(int unit=0;unit<UNITS;unit++) begin
            s=executing[unit];
            if(unit>=MUL_BASE && unit<FP_BASE && mul_complete[unit-MUL_BASE]) s=int'(mul_slot[unit-MUL_BASE]);
            if(unit>=FP_BASE && unit<LSU_BASE && fp_complete[unit-FP_BASE]) s=int'(fp_slot[unit-FP_BASE]);
            if(unit>=LSU_BASE && mem_complete[unit-LSU_BASE]) s=int'(mem_slot[unit-LSU_BASE]);
            if(s>=0) begin
                e=entries[s];
                routed[RESULT+unit].epoch=epoch;routed[RESULT+unit].slot=7'(s);routed[RESULT+unit].destination=e.dest_valid?{4'b0,e.dest_fp,e.pdst[2:0]}:8'hff;
                routed[RESULT+unit].kind=8;routed[RESULT+unit].pc=e.pc+e.length;
                if(unit<ALUS) begin
                    tx_valid[RESULT+unit]=1;routed[RESULT+unit].data[0]={32'b0,alu_result[unit]};
                    if(e.d.jal || e.d.jalr) routed[RESULT+unit].data[0]={32'b0,e.pc+32'(e.length)};
                    if(branch_taken(e)) routed[RESULT+unit].pc=e.d.jalr?(e.operands[0][31:0]+e.d.imm)&32'hfffffffe:e.pc+e.d.imm;
                    if(e.d.csr_en) routed[RESULT+unit].data[0]={32'b0,csr_read_data};
                    if(e.d.ecall || e.d.ebreak || (e.d.csr_en && csr_read_illegal) ||
                       (e.d.mret && !csr_mret_allowed) || (e.d.sret && !csr_sret_allowed) ||
                       (e.d.sfence_vma && !csr_sfence_allowed) || (e.d.wfi && !csr_wfi_allowed)) begin
                        routed[RESULT+unit].kind=9;
                        routed[RESULT+unit].data[1]=e.d.ecall?(csr_privilege==3?11:csr_privilege==1?9:8):e.d.ebreak?3:2;
                        routed[RESULT+unit].data[2]=(e.d.ecall || e.d.ebreak)?0:e.raw;
                    end
                end else if(unit<FP_BASE) begin
                    tx_valid[RESULT+unit]=mul_complete[unit-MUL_BASE];
                    routed[RESULT+unit].data[0]={32'b0,mul_saved[unit-MUL_BASE]};
                end else if(unit<LSU_BASE) begin
                    tx_valid[RESULT+unit]=fp_complete[unit-FP_BASE] || (!fp_active[unit-FP_BASE] && fp_illegal[unit-FP_BASE]);
                    routed[RESULT+unit].data[0]=fp_saved[unit-FP_BASE];
                    routed[RESULT+unit].instruction={27'b0,fp_saved_flags[unit-FP_BASE]};
                    if(!fp_active[unit-FP_BASE] && fp_illegal[unit-FP_BASE]) begin
                        routed[RESULT+unit].kind=9;routed[RESULT+unit].data[1]=2;routed[RESULT+unit].data[2]=e.raw;
                    end
                end else begin
                    tx_valid[RESULT+unit]=mem_complete[unit-LSU_BASE] && !memory_cancel[unit-LSU_BASE];
                    routed[RESULT+unit].data[0]=memory_completion[unit-LSU_BASE].result;
                    routed[RESULT+unit].kind=memory_completion[unit-LSU_BASE].fault?9:8;
                    routed[RESULT+unit].data[1]={32'b0,memory_completion[unit-LSU_BASE].cause};
                    routed[RESULT+unit].data[2]={32'b0,memory_completion[unit-LSU_BASE].tval};
                end
            end
        end
        wanted=fetch_cursor;
        if(!frontend_blocked && !debug_halted && !wfi_sleep && !debug_req && !csr_interrupt_pending &&
           (fetch_cursor-{pc[31:4],4'b0})<128) begin
            tx_valid[FETCH_REQ]=1;routed[FETCH_REQ].epoch=epoch;routed[FETCH_REQ].pc=wanted;
        end
        routed[FETCH_RSP]=fetch_response;
        if(fetch_active && !fetch_finished && fetch_ready) begin
            routed[FETCH_RSP]=fetch_request;routed[FETCH_RSP].data[1:0]=fetched_data;
            routed[FETCH_RSP].data[2]={32'b0,fetch_cause};
            routed[FETCH_RSP].kind=fetch_fault?9:8;
            routed[FETCH_RSP].instruction={24'b0,fetched_permissions};
        end
        tx_valid[FETCH_RSP]=fetch_finished || (fetch_active && fetch_ready);
        rx_ready[FETCH_REQ]=!fetch_active || (tx_valid[FETCH_RSP] && tx_ready[FETCH_RSP]);
        rx_ready[FETCH_RSP]=1;
        // Credit-based injection: select a packet only when its producer lane
        // can accept it; no stalled valid packet can change under the receiver.
        tx_valid &= tx_ready;
        if(debug_halted) begin
            prf_raddr[debug_bank][0]=debug_physical[7:3];
            if(debug_reg_ready && debug_reg_write && (debug_reg_addr[5] || debug_reg_addr[4:0]!=0)) begin
                prf_we[debug_bank]=1;prf_waddr[debug_bank]=debug_physical[7:3];
                prf_wdata[debug_bank]=debug_reg_addr[5]?debug_reg_wdata:{32'b0,debug_reg_wdata[31:0]};
            end
        end
        if(flush || !rst_n) begin tx_valid=0;rx_ready=0;prf_we=0;end
    end
    always_comb begin: retirement
        logic stop;
        integer s;
        // A step must retire exactly once at the boundary accepted by debug.
        stop=debug_halted || wfi_sleep || (step_active && !fetch_quiet);
        commit_count=0;commit_next_pc=pc;
        commit_flags=0;fp_flags_commit=0;fp_dirty_commit=0;
        for(int l=0;l<4;l++) begin
            s=(int'(head)+l)%ROB;
            if(l>=occupancy || !entries[s].valid || !entries[s].done || entries[s].fault ||
               (l!=0 && (is_control(entries[s].d) || debug_req || step_active || csr_interrupt_pending))) stop=1;
            // A page walker may own an accepted external transaction. Drain
            // fetch and both LSUs before changing permissions or flushing TLBs.
            if(is_control(entries[s].d) && !entries[s].d.branch &&
               !entries[s].d.jal && !entries[s].d.jalr && (!fetch_quiet || !memory_quiet)) stop=1;
            if(!stop) begin
                commit_count++;
                commit_next_pc=entries[s].d.mret?csr_return_pc:
                               entries[s].d.sret?csr_sreturn_pc:entries[s].next_pc;
                commit_flags|=entries[s].flags;
                fp_flags_commit|=entries[s].d.fp_compute;
                fp_dirty_commit|=entries[s].d.fp_compute || (entries[s].dest_valid && entries[s].dest_fp);
                if(is_control(entries[s].d)) stop=1;
            end
        end
        fault_take=occupancy!=0 && entries[head].valid && entries[head].done &&
                   entries[head].fault && !debug_halted && fetch_quiet && memory_quiet;
        control_take=commit_count!=0 && is_control(entries[head].d);
        interrupt_take=!debug_halted && !debug_req && csr_interrupt_pending && fetch_quiet && memory_quiet &&
                       ((commit_count!=0 && !(entries[head].d.csr_en || entries[head].d.mret ||
                         entries[head].d.sret || entries[head].d.fence_i || entries[head].d.sfence_vma)) || wfi_sleep || occupancy==0);
        trap_take=fault_take || interrupt_take;
        trap_pc=fault_take?entries[head].pc:(wfi_sleep || occupancy==0)?pc:commit_next_pc;
        trap_cause=fault_take?entries[head].cause:csr_interrupt_cause;
        trap_tval=fault_take?entries[head].tval:0;
        mret_take=control_take && entries[head].d.mret && !trap_take;
        sret_take=control_take && entries[head].d.sret && !trap_take;
        sfence_take=control_take && entries[head].d.sfence_vma;
        fence_i_take=control_take && entries[head].d.fence_i;
        csr_commit_valid=control_take && entries[head].d.csr_en && csr_write_intent;
        flush=trap_take || control_take || debug_enter || debug_resume_fire ||
              (wfi_sleep && csr_wfi_wake_pending);
        redirect_pc=trap_take?csr_trap_vector:debug_resume_fire?debug_dpc:
                    mret_take?csr_return_pc:sret_take?csr_sreturn_pc:
                    wfi_sleep?pc:commit_next_pc;
    end
    assign csr_source=entries[head].d.csr_imm?{27'b0,entries[head].instruction[19:15]}:
                                                            entries[head].operands[0][31:0];
    assign csr_write_intent=entries[head].d.csr_en && (entries[head].d.csr_cmd==1 || csr_source!=0);
    assign csr_write_data=entries[head].d.csr_cmd==1?csr_source:
                          entries[head].d.csr_cmd==2?csr_read_modify_data|csr_source:
                                                   csr_read_modify_data&~csr_source;
    debug_control debug_controller (.clk,.rst_n,.debug_req,.resume_req(debug_resume),
        .step(debug_step),.dpc_write(debug_dpc_write),.dpc_wdata(debug_dpc_wdata),
        .retire_boundary(fetch_quiet && memory_quiet &&
            (commit_count!=0 || (!step_active && (wfi_sleep || occupancy==0)))),
        .next_pc((wfi_sleep || occupancy==0)?pc:commit_next_pc),
        .enter_fire(debug_enter),.resume_fire(debug_resume_fire),.halted(debug_halted),.dpc(debug_dpc));
    assign debug_privilege=csr_privilege;
    assign debug_reg_ready=debug_halted && debug_reg_valid;
    assign debug_reg_rdata=prf_rdata[debug_bank][0];
    csr_file #(.RETIRE_WIDTH(3)) u_csr (
        .clk,.rst_n,.read_addr(entries[head].instruction[31:20]),.read_write_intent(csr_write_intent),
        .read_data(csr_read_data),.read_modify_data(csr_read_modify_data),.read_illegal(csr_read_illegal),
        .commit_valid(csr_commit_valid),.commit_addr(entries[head].instruction[31:20]),
        .commit_data(entries[head].csr_wdata),.commit_visible_data(csr_commit_visible_data),
        .retire(commit_count),.fp_flags_valid(fp_flags_commit),.fp_flags(commit_flags),.fp_dirty(fp_dirty_commit),
        .mtime,.irq_m_software(irq_sync[0][1]),.irq_m_timer(irq_sync[1][1]),.irq_m_external(irq_sync[2][1]),
        .irq_s_software(irq_sync[3][1]),.irq_s_timer(irq_sync[4][1]),.irq_s_external(irq_sync[5][1]),.nmi(irq_sync[6][1]),
        .trap_enter(trap_take),.trap_pc,.trap_cause,.trap_tval,.mret(mret_take),.sret(sret_take),
        .trap_vector(csr_trap_vector),.return_pc(csr_return_pc),.sreturn_pc(csr_sreturn_pc),.frm_out(csr_frm),
        .fp_enabled(csr_fp_enabled),.interrupt_pending(csr_interrupt_pending),.interrupt_cause(csr_interrupt_cause),
        .wfi_wake_pending(csr_wfi_wake_pending),.privilege(csr_privilege),.data_privilege(csr_data_privilege),
        .pmpcfg0_out(csr_pmpcfg0),.pmpaddr0_out(csr_pmpaddr0),.pmpaddr1_out(csr_pmpaddr1),
        .pmpaddr2_out(csr_pmpaddr2),.pmpaddr3_out(csr_pmpaddr3),.satp_out(csr_satp),
        .mstatus_sum_out(csr_mstatus_sum),.mstatus_mxr_out(csr_mstatus_mxr),.mstatus_mprv_out(),
        .mret_allowed(csr_mret_allowed),.sret_allowed(csr_sret_allowed),
        .sfence_allowed(csr_sfence_allowed),.wfi_allowed(csr_wfi_allowed));
    entry_t memory_op_n[LSUS], memory_completion_n[LSUS];
    entry_t dispatch_entry[4];
    logic [3:0] dispatch_valid;
    logic [6:0] dispatch_slot[4];
    logic [7:0] speculative_n[2][32], committed_n[2][32];
    logic [PHYS-1:0] free_regs_n[2], reg_ready_n[2];
    logic [6:0] head_n, tail_n;
    integer occupancy_n, allocation_bank_n;
    logic [31:0] pc_n, epoch_n;
    logic frontend_blocked_n;
    logic [31:0] line_address_n[8], line_cause_n[8];
    logic [127:0] line_data_n[8];
    logic [7:0] line_permissions_n[8];
    logic [7:0] line_valid_n, line_fault_n;
    logic [31:0] fetch_cursor_n;
    logic fetch_active_n, fetch_finished_n;
    message_t fetch_request_n, fetch_response_n;
    logic [2:0] served_n[4];
    logic wfi_sleep_n;
    logic step_active_n;
    logic [MULDIVS-1:0] mul_active_n, mul_complete_n;
    logic [FPUS-1:0] fp_active_n, fp_complete_n;
    logic [LSUS-1:0] mem_active_n, mem_complete_n, mem_killed_n;
    logic [MULDIVS-1:0][6:0] mul_slot_n;
    logic [FPUS-1:0][6:0] fp_slot_n;
    logic [LSUS-1:0][6:0] mem_slot_n;
    logic [MULDIVS-1:0][31:0] mul_saved_n;
    logic [FPUS-1:0][63:0] fp_saved_n;
    logic [FPUS-1:0][4:0] fp_saved_flags_n;
    hybrid_rob storage (
        .clk,.rst_n,.flush,.head,.epoch,.csr_write_data,.commit_count,
        .tx_valid,.rx_valid,.rx_ready,.tx,.rx,.memory_completion,
        .mul_start,.fp_start,.memory_start,.executing,
        .dispatch_valid,.dispatch_slot,.dispatch_entry,.data(rob_data));
`ifdef RISCV_FORMAL
    logic [63:0] rvfi_next_order;
    assign rvfi_ixl={4{2'b01}};
`endif
    always_ff @(posedge clk) begin
        speculative<=speculative_n;
        committed<=committed_n;
        free_regs<=free_regs_n;
        reg_ready<=reg_ready_n;
        head<=head_n;
        tail<=tail_n;
        occupancy<=occupancy_n;
        allocation_bank<=allocation_bank_n;
        pc<=pc_n;
        epoch<=epoch_n;
        frontend_blocked<=frontend_blocked_n;
        line_address<=line_address_n;
        line_cause<=line_cause_n;
        line_data<=line_data_n;
        line_permissions<=line_permissions_n;
        line_valid<=line_valid_n;
        line_fault<=line_fault_n;
        fetch_active<=fetch_active_n;
        fetch_finished<=fetch_finished_n;
        fetch_request<=fetch_request_n;
        fetch_response<=fetch_response_n;
        fetch_cursor<=fetch_cursor_n;
        mul_active<=mul_active_n;
        fp_active<=fp_active_n;
        mem_active<=mem_active_n;
        mul_complete<=mul_complete_n;
        fp_complete<=fp_complete_n;
        mem_complete<=mem_complete_n;
        mem_killed<=mem_killed_n;
        mul_slot<=mul_slot_n;
        fp_slot<=fp_slot_n;
        mem_slot<=mem_slot_n;
        mul_saved<=mul_saved_n;
        fp_saved<=fp_saved_n;
        fp_saved_flags<=fp_saved_flags_n;
        memory_op<=memory_op_n;
        memory_completion<=memory_completion_n;
        wfi_sleep<=wfi_sleep_n;
        step_active<=step_active_n;
        served<=served_n;
    end
    always_ff @(posedge clk) begin
`ifdef RISCV_FORMAL
        if(!rst_n) begin
            rvfi_next_order<=0;
            rvfi_valid<='0;
            rvfi_order<='0;
            rvfi_insn<='0;
            rvfi_trap<='0;
            rvfi_halt<='0;
            rvfi_intr<='0;
            rvfi_mode<='0;
            rvfi_rs1_addr<='0;
            rvfi_rs2_addr<='0;
            rvfi_rs1_rdata<='0;
            rvfi_rs2_rdata<='0;
            rvfi_rd_addr<='0;
            rvfi_rd_wdata<='0;
            rvfi_pc_rdata<='0;
            rvfi_pc_wdata<='0;
            rvfi_mem_addr<='0;
            rvfi_mem_rmask<='0;
            rvfi_mem_wmask<='0;
            rvfi_mem_rdata<='0;
            rvfi_mem_wdata<='0;
            rvfi_frd_valid<='0;
            rvfi_frd_addr<='0;
            rvfi_frd_wdata<='0;
            rvfi_csr_valid<='0;
            rvfi_csr_addr<='0;
            rvfi_csr_wdata<='0;
        end else begin
            rvfi_valid<=0;
            for(int l=0;l<4;l++) begin
                if(l<int'(commit_count) || (fault_take && l==0)) begin
                    rvfi_valid[l]<=1;rvfi_order[l]<=rvfi_next_order+64'(l);
                    rvfi_insn[l]<=entries[(int'(head)+l)%ROB].raw;
                    rvfi_trap[l]<=fault_take;rvfi_halt[l]<=debug_enter;
                    rvfi_intr[l]<=interrupt_take && l==int'(commit_count)-1;
                    rvfi_mode[l]<=csr_privilege;
                    rvfi_rs1_addr[l]<=entries[(int'(head)+l)%ROB].d.uses_rs1?entries[(int'(head)+l)%ROB].d.rs1:0;
                    rvfi_rs2_addr[l]<=entries[(int'(head)+l)%ROB].d.uses_rs2?entries[(int'(head)+l)%ROB].d.rs2:0;
                    rvfi_rs1_rdata[l]<=entries[(int'(head)+l)%ROB].operands[0][31:0];
                    rvfi_rs2_rdata[l]<=entries[(int'(head)+l)%ROB].operands[1][31:0];
                    rvfi_rd_addr[l]<=!fault_take && entries[(int'(head)+l)%ROB].dest_valid && !entries[(int'(head)+l)%ROB].dest_fp?entries[(int'(head)+l)%ROB].d.rd:0;
                    rvfi_rd_wdata[l]<=!fault_take && entries[(int'(head)+l)%ROB].dest_valid && !entries[(int'(head)+l)%ROB].dest_fp?entries[(int'(head)+l)%ROB].result[31:0]:0;
                    rvfi_pc_rdata[l]<=entries[(int'(head)+l)%ROB].pc;
                    rvfi_pc_wdata[l]<=flush && (fault_take || l==int'(commit_count)-1)?redirect_pc:entries[(int'(head)+l)%ROB].next_pc;
                    rvfi_mem_addr[l]<=entries[(int'(head)+l)%ROB].memory_addr;
                    rvfi_mem_rmask[l]<=fault_take?0:entries[(int'(head)+l)%ROB].rmask;
                    rvfi_mem_wmask[l]<=fault_take?0:entries[(int'(head)+l)%ROB].wmask;
                    rvfi_mem_rdata[l]<=entries[(int'(head)+l)%ROB].memory_rdata;
                    rvfi_mem_wdata[l]<=entries[(int'(head)+l)%ROB].memory_wdata;
                    rvfi_frd_valid[l]<=!fault_take && entries[(int'(head)+l)%ROB].dest_valid && entries[(int'(head)+l)%ROB].dest_fp;
                    rvfi_frd_addr[l]<=entries[(int'(head)+l)%ROB].d.rd;
                    rvfi_frd_wdata[l]<=entries[(int'(head)+l)%ROB].result;
                    rvfi_csr_valid[l]<=csr_commit_valid && entries[(int'(head)+l)%ROB].instruction[31:20]!=12'h344;
                    rvfi_csr_addr[l]<=entries[(int'(head)+l)%ROB].instruction[31:20];
                    rvfi_csr_wdata[l]<=csr_commit_visible_data;
                end
            end
            rvfi_next_order<=rvfi_next_order+64'(commit_count)+64'(fault_take);
        end
`endif
    end
    always_comb begin: ready_acknowledgements
        entry_t e;
        logic accept;
        logic [PHYS-1:0] mask;
        acknowledged[0]=0;acknowledged[1]=0;e='0;accept=0;mask=0;
        for(int k=4;k<RESULT;k++) begin
            e=entries[rx[k].slot];
            accept=rx_valid[k] && rx_ready[k] && rx[k].epoch==epoch &&
                   rx[k].kind==8 && e.valid && e.dest_valid;
            mask=(PHYS'(1)<<e.pdst) & {PHYS{accept}};
            acknowledged[0]|=mask & {PHYS{!e.dest_fp}};
            acknowledged[1]|=mask & {PHYS{e.dest_fp}};
        end
    end
    // State updates are ordered in this block so same-group rename observes
    // preceding lanes, and commit frees only the superseded physical mappings.
    always_comb begin: next_state
        integer s,b,chosen,allocated,mem_allocated;
        integer l,f,i,r,k;
        logic stop;
        logic [PHYS-1:0] mapped;
        entry_t e;
        s=0;b=0;chosen=0;allocated=0;mem_allocated=0;stop=0;e='0;mapped=0;
        l=0;f=0;i=0;r=0;k=0;
        dispatch_valid=0;
        for(l=0;l<4;l++) begin dispatch_slot[l]=0;dispatch_entry[l]='0;end
        speculative_n=speculative;
        committed_n=committed;
        free_regs_n=free_regs;
        for(f=0;f<2;f++) reg_ready_n[f]=reg_ready[f] | acknowledged[f];
        head_n=head;
        tail_n=tail;
        occupancy_n=occupancy;
        allocation_bank_n=allocation_bank;
        pc_n=pc;
        epoch_n=epoch;
        frontend_blocked_n=frontend_blocked;
        line_address_n=line_address;
        line_cause_n=line_cause;
        line_data_n=line_data;
        line_permissions_n=line_permissions;
        line_valid_n=line_valid;
        line_fault_n=line_fault;
        fetch_active_n=fetch_active;
        fetch_finished_n=fetch_finished;
        fetch_request_n=fetch_request;
        fetch_response_n=fetch_response;
        fetch_cursor_n=fetch_cursor;
        mul_active_n=mul_active;
        fp_active_n=fp_active;
        mem_active_n=mem_active;
        mul_complete_n=mul_complete;
        fp_complete_n=fp_complete;
        mem_complete_n=mem_complete;
        mem_killed_n=mem_killed;
        mul_slot_n=mul_slot;
        fp_slot_n=fp_slot;
        mem_slot_n=mem_slot;
        mul_saved_n=mul_saved;
        fp_saved_n=fp_saved;
        fp_saved_flags_n=fp_saved_flags;
        memory_op_n=memory_op;
        memory_completion_n=memory_completion;
        wfi_sleep_n=wfi_sleep;
        step_active_n=step_active;
        served_n=served;



        if(!rst_n) begin
            head_n=0;tail_n=0;occupancy_n=0;pc_n=0;epoch_n=0;allocation_bank_n=0;fetch_cursor_n=0;
            frontend_blocked_n=0;line_valid_n=0;line_fault_n=0;
            fetch_active_n=0;fetch_finished_n=0;fetch_request_n='0;fetch_response_n='0;
            mul_active_n=0;fp_active_n=0;mem_active_n=0;mul_complete_n=0;fp_complete_n=0;mem_complete_n=0;mem_killed_n=0;
            mul_slot_n=0;fp_slot_n=0;mem_slot_n=0;mul_saved_n=0;fp_saved_n=0;fp_saved_flags_n=0;
            for(i=0;i<LSUS;i++) begin memory_op_n[i]='0;memory_completion_n[i]='0;end
            wfi_sleep_n=0;step_active_n=0;
            for(i=0;i<4;i++) served_n[i]=0;
            for(f=0;f<2;f++) begin
                for(r=0;r<PHYS;r++) begin free_regs_n[f][r]=r>=32;reg_ready_n[f][r]=1;end
                for(r=0;r<32;r++) begin speculative_n[f][r]=8'(r);committed_n[f][r]=8'(r);end

            end
            for(f=0;f<8;f++) begin line_address_n[f]=0;line_cause_n[f]=0;line_data_n[f]=0;line_permissions_n[f]=0;end
        end else begin
            // External transactions already accepted are drained across flush.
            if(fetch_active_n && !fetch_finished_n && fetch_ready) begin
                fetch_response_n=fetch_request_n;fetch_response_n.data[1:0]=fetched_data;
                fetch_response_n.data[2]={32'b0,fetch_cause};
                fetch_response_n.kind=fetch_fault?9:8;fetch_response_n.instruction={24'b0,fetched_permissions};
                fetch_finished_n=1;
            end
            for(i=0;i<LSUS;i++) begin
                if(memory_cancel[i] && mem_active_n[i]) mem_killed_n[i]=1;
                if(mem_active_n[i] && !mem_complete_n[i] && memory_done[i]) begin
                    memory_completion_n[i]=memory_op_n[i];memory_completion_n[i].result=memory_result[i];
                    memory_completion_n[i].fault=memory_fault[i];memory_completion_n[i].cause=memory_cause[i];memory_completion_n[i].tval=memory_tval[i];
                    memory_completion_n[i].memory_addr=memory_paddr[i];memory_completion_n[i].memory_rdata=memory_rdata[i];
                    memory_completion_n[i].memory_wdata=memory_wdata[i];memory_completion_n[i].rmask=memory_rmask[i];memory_completion_n[i].wmask=memory_wmask[i];
                    mem_complete_n[i]=1;
                end
                if(mem_killed_n[i] && mem_complete_n[i]) begin mem_active_n[i]=0;mem_complete_n[i]=0;mem_killed_n[i]=0;end
            end
            for(l=0;l<4;l++) if(l<int'(commit_count)) begin
                s=(int'(head_n)+l)%ROB;e=entries[s];
                if(e.dest_valid) begin
                    committed_n[e.dest_fp][e.d.rd]=e.pdst;
                    free_regs_n[e.dest_fp][e.stale]=1;
                end
            end
            if(flush) begin
                if(control_take && entries[head_n].d.wfi && !csr_wfi_wake_pending) wfi_sleep_n=1;
                if(trap_take || debug_enter || debug_resume_fire || csr_wfi_wake_pending) wfi_sleep_n=0;
                if(debug_resume_fire) step_active_n=debug_step;
                if(debug_enter) step_active_n=0;
                pc_n=redirect_pc;fetch_cursor_n={redirect_pc[31:4],4'b0};epoch_n=epoch_n+1;head_n=0;tail_n=0;occupancy_n=0;frontend_blocked_n=0;
                line_valid_n=0;mul_active_n=0;fp_active_n=0;mul_complete_n=0;fp_complete_n=0;
                mem_killed_n |= mem_active_n;
                for(i=0;i<4;i++) served_n[i]=0;
                for(f=0;f<2;f++) begin
                    mapped=0;
                    for(r=0;r<32;r++) mapped|=PHYS'(1)<<committed_n[f][r];
                    free_regs_n[f]=~mapped;reg_ready_n[f]='1;
                    speculative_n[f]=committed_n[f];
                end
            end else begin
                head_n=head_n+7'(commit_count);occupancy_n=occupancy_n-int'(commit_count);
                for(k=0;k<32;k++) if(read_owner[k]>=0 && tx_valid[k+4] && tx_ready[k+4])
                    served_n[read_owner[k]][read_operand[k]]=1;
                for(k=0;k<4;k++) begin
                    if(rx_valid[k] && rx_ready[k]) served_n[k]=0;
                end
                for(i=0;i<MULDIVS;i++) begin
                    if(tx_valid[RESULT+MUL_BASE+i]) begin mul_active_n[i]=0;mul_complete_n[i]=0;end
                    if(mul_done[i] && mul_active_n[i]) begin mul_complete_n[i]=1;mul_saved_n[i]=mul_result[i];end
                    if(mul_start[i]) begin mul_active_n[i]=1;mul_slot_n[i]=7'(executing[MUL_BASE+i]);end
                end
                for(i=0;i<FPUS;i++) begin
                    if(tx_valid[RESULT+FP_BASE+i]) begin fp_active_n[i]=0;fp_complete_n[i]=0;end
                    if(fp_done[i] && fp_active_n[i]) begin fp_complete_n[i]=1;fp_saved_n[i]=fp_result[i];fp_saved_flags_n[i]=fp_flags[i];end
                    if(fp_start[i]) begin fp_active_n[i]=1;fp_slot_n[i]=7'(executing[FP_BASE+i]);end
                end
                for(i=0;i<LSUS;i++) begin
                    if(tx_valid[RESULT+LSU_BASE+i]) begin mem_active_n[i]=0;mem_complete_n[i]=0;end
                    if(memory_start[i]) begin
                        mem_slot_n[i]=7'(executing[LSU_BASE+i]);memory_op_n[i]=entries[mem_slot_n[i]];
                        mem_active_n[i]=1;mem_complete_n[i]=0;mem_killed_n[i]=0;
                    end
                end
                if(tx_valid[FETCH_REQ] && tx_ready[FETCH_REQ]) fetch_cursor_n=fetch_cursor_n+16;
                if(tx_valid[FETCH_RSP] && tx_ready[FETCH_RSP]) begin fetch_active_n=0;fetch_finished_n=0;end
                if(rx_valid[FETCH_REQ] && rx_ready[FETCH_REQ]) begin fetch_request_n=rx[FETCH_REQ];fetch_active_n=1;fetch_finished_n=0;end
                if(rx_valid[FETCH_RSP] && rx[FETCH_RSP].epoch==epoch_n) begin
                    b=int'(rx[FETCH_RSP].pc[6:4]);line_address_n[b]=rx[FETCH_RSP].pc;
                    line_data_n[b]=rx[FETCH_RSP].data[1:0];line_permissions_n[b]=rx[FETCH_RSP].instruction[7:0];
                    line_fault_n[b]=rx[FETCH_RSP].kind==9;line_cause_n[b]=rx[FETCH_RSP].data[2][31:0];
                    line_valid_n[b]=1;
                end
                allocated=0;mem_allocated=0;stop=0;
                for(l=0;l<4;l++) begin
                    e='0;e.d=decoded[l];e.pc=dec_pc[l];e.raw=dec_raw[l];e.instruction=dec_instruction[l];
                    e.length=dec_length[l];e.next_pc=e.pc+e.length;
                    e.dest_fp=fp_destination(e.instruction,e.d);
                    e.dest_valid=e.dest_fp || ((e.d.reg_write || e.d.fp_compute) && e.d.rd!=0);
                    e.src_used={e.d.fp_uses_rs3,e.d.uses_rs2 || e.d.fp_uses_rs2,e.d.uses_rs1 || e.d.fp_uses_rs1};
                    e.src_fp={e.d.fp_uses_rs3,e.d.fp_uses_rs2,e.d.fp_uses_rs1 && !e.d.uses_rs1};
                    if(!e.src_fp[0] && e.d.rs1==0) e.src_used[0]=0;
                    if(!e.src_fp[1] && e.d.rs2==0) e.src_used[1]=0;
                    e.src[0]=speculative_n[e.src_fp[0]][e.d.rs1];
                    e.src[1]=speculative_n[e.src_fp[1]][e.d.rs2];
                    e.src[2]=speculative_n[e.src_fp[2]][e.instruction[31:27]];
                    e.fault=dec_fault[l] || dec_bad[l] || e.d.illegal ||
                            ((e.d.fp_compute || e.d.fp_load || e.d.fp_store) && !csr_fp_enabled);
                    e.cause=dec_fault[l]?dec_cause[l]:2;e.tval=dec_fault[l]?dec_tval[l]:e.raw;
                    if(e.fault) e.dest_valid=0;
                    chosen=allocate_register(free_regs_n[e.dest_fp],allocation_bank_n);
                    if(!dec_valid[l] || occupancy_n>=ROB || queue_count+allocated>=IQ ||
                       (is_memory(e.d) && memory_count+mem_allocated>=32) || (e.dest_valid && chosen<0)) stop=1;
                    if(!stop) begin
                        e.valid=1;e.done=e.fault;
                        if(e.dest_valid) begin
                            e.pdst=8'(chosen);e.stale=speculative_n[e.dest_fp][e.d.rd];
                            free_regs_n[e.dest_fp][chosen]=0;reg_ready_n[e.dest_fp][chosen]=0;
                            speculative_n[e.dest_fp][e.d.rd]=8'(chosen);allocation_bank_n=(chosen+1)%8;
                        end
                        dispatch_valid[l]=1;dispatch_slot[l]=tail_n;dispatch_entry[l]=e;
                        tail_n=tail_n+1'b1;occupancy_n++;allocated++;
                        if(is_memory(e.d)) mem_allocated++;
                        pc_n=e.next_pc;
                        if(is_control(e.d) || e.fault) begin frontend_blocked_n=1;stop=1;end
                    end
                end
            end
            free_regs_n[0][0]=0;reg_ready_n[0][0]=1;
        end
    end
    // Check ownership at the state boundary, including ROB wrap and recovery.
    // These checks are verification logic, not additional register-file ports.
    // synthesis translate_off
`ifndef SYNTHESIS
    always @(posedge clk) if(rst_n) begin: ownership_checks
        integer live;
        logic [PHYS-1:0] destinations[2];
        live=0;destinations[0]='0;destinations[1]='0;
        assert(occupancy>=0 && occupancy<=ROB && queue_count<=IQ && memory_count<=32);
        assert(int'(commit_count)<=occupancy);
        assert(registers[0][0]==0 && speculative[0][0]==0 && committed[0][0]==0);
        for(int f=0;f<2;f++) for(int r=0;r<32;r++) begin
            assert(!free_regs[f][speculative[f][r]]);
            assert(!free_regs[f][committed[f][r]] && reg_ready[f][committed[f][r]]);
        end
        for(int s=0;s<ROB;s++) if(entries[s].valid) begin
            live++;
            if(entries[s].dest_valid) begin
                assert(!free_regs[entries[s].dest_fp][entries[s].pdst]);
                assert(!destinations[entries[s].dest_fp][entries[s].pdst]);
                destinations[entries[s].dest_fp][entries[s].pdst]=1;
            end
        end
        assert(live==occupancy);
    end
`endif
    // synthesis translate_on
endmodule

// One update circuit per row; packet inputs are shared across the ROB.
module hybrid_rob (
    input logic clk, rst_n, flush,
    input logic [6:0] head,
    input logic [31:0] epoch, csr_write_data,
    input logic [2:0] commit_count,
    input logic [hybrid_pkg::CHANNELS-1:0] tx_valid, rx_valid, rx_ready,
    input hybrid_pkg::message_t tx[hybrid_pkg::CHANNELS], rx[hybrid_pkg::CHANNELS],
    input hybrid_pkg::entry_t memory_completion[hybrid_pkg::LSUS],
    input logic [hybrid_pkg::MULDIVS-1:0] mul_start,
    input logic [hybrid_pkg::FPUS-1:0] fp_start,
    input logic [hybrid_pkg::LSUS-1:0] memory_start,
    input integer executing[hybrid_pkg::UNITS],
    input logic [3:0] dispatch_valid,
    input logic [6:0] dispatch_slot[4],
    input hybrid_pkg::entry_t dispatch_entry[4],
    output wire [hybrid_pkg::ROB*$bits(hybrid_pkg::entry_t)-1:0] data
);
    import hybrid_pkg::*;
    localparam RESULT=36;
    entry_t entries[ROB];
    for(genvar row=0;row<ROB;row++)
        assign data[row*$bits(entry_t)+:$bits(entry_t)]=entries[row];
    // Preserve row hierarchy in synthesis; expand the shared update function
    // only once. The simulator iterates rows without copying packet ports.
`ifdef SYNTHESIS
    for(genvar row=0;row<ROB;row++) begin: rows
        hybrid_rob_row storage (
            .clk(clk),.rst_n(rst_n),.flush(flush),.head(head),.slot(7'(row)),
            .epoch(epoch),.csr_write_data(csr_write_data),.commit_count(commit_count),
            .tx_valid(tx_valid),.rx_valid(rx_valid),.rx_ready(rx_ready),.tx(tx),.rx(rx),
            .memory_completion(memory_completion),.mul_start(mul_start),.fp_start(fp_start),
            .memory_start(memory_start),.executing(executing),.dispatch_valid(dispatch_valid),
            .dispatch_slot(dispatch_slot),.dispatch_entry(dispatch_entry),.entry(entries[row])
        );
    end
`else
    `include "rtl/top/hybrid_rob_update.svh"
    entry_t next_entries[ROB];
    always_comb
        for(int row=0;row<ROB;row++) next_entries[row]=row_update(entries[row],7'(row));
    always_ff @(posedge clk) entries<=next_entries;
`endif
endmodule

`ifdef SYNTHESIS
module hybrid_rob_row (
    input logic clk, rst_n, flush,
    input logic [6:0] head, slot,
    input logic [31:0] epoch, csr_write_data,
    input logic [2:0] commit_count,
    input logic [hybrid_pkg::CHANNELS-1:0] tx_valid, rx_valid, rx_ready,
    input hybrid_pkg::message_t tx[hybrid_pkg::CHANNELS], rx[hybrid_pkg::CHANNELS],
    input hybrid_pkg::entry_t memory_completion[hybrid_pkg::LSUS],
    input logic [hybrid_pkg::MULDIVS-1:0] mul_start,
    input logic [hybrid_pkg::FPUS-1:0] fp_start,
    input logic [hybrid_pkg::LSUS-1:0] memory_start,
    input integer executing[hybrid_pkg::UNITS],
    input logic [3:0] dispatch_valid,
    input logic [6:0] dispatch_slot[4],
    input hybrid_pkg::entry_t dispatch_entry[4],
    output hybrid_pkg::entry_t entry
);
    import hybrid_pkg::*;
    localparam RESULT=36;
    `include "rtl/top/hybrid_rob_update.svh"
    entry_t next_entry;
    always_comb next_entry=row_update(entry,slot);
    always_ff @(posedge clk) entry<=next_entry;
endmodule
`endif
