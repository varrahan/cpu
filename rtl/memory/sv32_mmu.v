module sv32_mmu (
    input wire clk, input wire rst_n, input wire flush,
    input wire req_valid, input wire [31:0] vaddr,
    input wire [1:0] privilege,
    input wire access_read, input wire access_write, input wire access_execute,
    input wire mstatus_sum, input wire mstatus_mxr,
    input wire [31:0] satp,
    output wire resp_ready, output wire [31:0] paddr,
    output wire page_fault, output wire access_fault,
    output wire mem_req_valid, input wire mem_req_ready,
    input wire mem_req_allow, output wire mem_req_write,
    output wire [31:0] mem_req_addr, output wire [31:0] mem_req_wdata,
    output wire [3:0] mem_req_be, output wire mem_req_amo,
    output wire [4:0] mem_req_amo_op,
    input wire mem_rsp_valid, output wire mem_rsp_ready,
    input wire [31:0] mem_rsp_rdata, input wire mem_rsp_error
);
    localparam [1:0] PRIV_U = 0, PRIV_S = 1, PRIV_M = 3;
    localparam [3:0] IDLE = 0, L1_REQ = 1, L1_WAIT = 2,
                     L0_REQ = 3, L0_WAIT = 4, EVAL = 5,
                     AD_REQ = 6, AD_WAIT = 7, COMPLETE = 8;
    reg [3:0] state;
    reg [31:0] saved_vaddr, pte, pte_addr;
    reg [1:0] saved_privilege;
    reg saved_read, saved_write, saved_execute, saved_sum, saved_mxr;
    reg level;
    reg [31:0] walk_addr;
    reg [31:0] result_paddr;
    reg result_page_fault, result_access_fault;
    reg [31:0] ad_mask;

    reg [3:0] tlb_valid;
    reg [19:0] tlb_vpn [0:3];
    reg [21:0] tlb_ppn [0:3];
    reg [8:0] tlb_asid [0:3];
    reg [7:0] tlb_flags [0:3];
    reg tlb_superpage [0:3];
    reg [1:0] tlb_replace;
    reg tlb_hit;
    reg [31:0] tlb_paddr;
    reg tlb_permission;
    integer i;

    wire translation_enabled = satp[31] && privilege != PRIV_M;
    wire [9:0] vpn0 = saved_vaddr[21:12];
    wire pte_valid = pte[0] && !(pte[2] && !pte[1]);
    wire pte_leaf = pte[1] || pte[3];

    function automatic leaf_permission_ok;
        input [4:0] flags;
        input [1:0] priv;
        input rd, wr, ex, sum, mxr;
        reg user_page;
        begin
            user_page = flags[4];
            leaf_permission_ok = flags[0] && !(flags[2] && !flags[1]) &&
                (!wr || flags[2]) &&
                (!rd || flags[1] || (mxr && flags[3])) &&
                (!ex || flags[3]) &&
                (priv == PRIV_U ? user_page :
                 priv == PRIV_S ? (!user_page || (!ex && sum)) : 1'b1);
        end
    endfunction

    function automatic permission_ok;
        input [7:0] flags;
        input [1:0] priv;
        input rd, wr, ex, sum, mxr;
        begin
            permission_ok = leaf_permission_ok(flags[4:0], priv, rd, wr, ex,
                                                sum, mxr) && flags[6] &&
                            (!wr || flags[7]);
        end
    endfunction

    always @(*) begin
        tlb_hit = 0;
        tlb_paddr = vaddr;
        tlb_permission = 0;
        for (i = 0; i < 4; i = i + 1)
            if (!tlb_hit && tlb_valid[i] && tlb_asid[i] == satp[30:22] &&
                (tlb_superpage[i] ? tlb_vpn[i][19:10] == vaddr[31:22]
                                  : tlb_vpn[i] == vaddr[31:12])) begin
                tlb_hit = 1;
                tlb_paddr = tlb_superpage[i]
                            ? {tlb_ppn[i][21:10], vaddr[21:0]}
                            : {tlb_ppn[i][19:0], vaddr[11:0]};
                tlb_permission = permission_ok(
                    tlb_flags[i], privilege, access_read, access_write,
                    access_execute, mstatus_sum, mstatus_mxr);
            end
    end

    assign resp_ready = req_valid &&
                        (!translation_enabled || tlb_hit || state == COMPLETE);
    assign paddr = !translation_enabled ? vaddr :
                   tlb_hit ? tlb_paddr : result_paddr;
    assign page_fault = translation_enabled &&
                        (tlb_hit ? !tlb_permission : result_page_fault);
    assign access_fault = translation_enabled && !tlb_hit && result_access_fault;

    assign mem_req_valid = (state == L1_REQ || state == L0_REQ ||
                            state == AD_REQ) && mem_req_allow;
    assign mem_req_write = 0;
    assign mem_req_addr = state == AD_REQ ? pte_addr : walk_addr;
    assign mem_req_wdata = state == AD_REQ ? ad_mask : 0;
    assign mem_req_be = 4'b1111;
    assign mem_req_amo = state == AD_REQ;
    assign mem_req_amo_op = 5'b01000; // AMOOR.W
    assign mem_rsp_ready = state == L1_WAIT || state == L0_WAIT ||
                           state == AD_WAIT;

    always @(posedge clk) begin
        if (!rst_n || flush) begin
            state <= IDLE;
            tlb_valid <= 0;
            tlb_replace <= 0;
            saved_vaddr <= 0;
            saved_privilege <= 0;
            saved_read <= 0;
            saved_write <= 0;
            saved_execute <= 0;
            saved_sum <= 0;
            saved_mxr <= 0;
            level <= 0;
            walk_addr <= 0;
            pte <= 0;
            pte_addr <= 0;
            result_paddr <= 0;
            result_page_fault <= 0;
            result_access_fault <= 0;
            ad_mask <= 0;
            for (i = 0; i < 4; i = i + 1) begin
                tlb_vpn[i] <= 0;
                tlb_ppn[i] <= 0;
                tlb_asid[i] <= 0;
                tlb_flags[i] <= 0;
                tlb_superpage[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: if (req_valid && translation_enabled && !tlb_hit) begin
                    saved_vaddr <= vaddr;
                    saved_privilege <= privilege;
                    saved_read <= access_read;
                    saved_write <= access_write;
                    saved_execute <= access_execute;
                    saved_sum <= mstatus_sum;
                    saved_mxr <= mstatus_mxr;
                    result_page_fault <= 0;
                    result_access_fault <= 0;
                    if (satp[21:20] != 0) begin
                        result_access_fault <= 1;
                        state <= COMPLETE;
                    end else begin
                        walk_addr <= {satp[19:0], 12'b0} +
                                     {vaddr[31:22], 2'b0};
                        state <= L1_REQ;
                    end
                end
                L1_REQ: if (!mem_req_allow) begin
                    result_access_fault <= 1; state <= COMPLETE;
                end else if (mem_req_ready) state <= L1_WAIT;
                L1_WAIT: if (mem_rsp_valid) begin
                    if (mem_rsp_error) begin
                        result_access_fault <= 1; state <= COMPLETE;
                    end else begin
                        pte <= mem_rsp_rdata; pte_addr <= walk_addr;
                        level <= 1; state <= EVAL;
                    end
                end
                L0_REQ: if (!mem_req_allow) begin
                    result_access_fault <= 1; state <= COMPLETE;
                end else if (mem_req_ready) state <= L0_WAIT;
                L0_WAIT: if (mem_rsp_valid) begin
                    if (mem_rsp_error) begin
                        result_access_fault <= 1; state <= COMPLETE;
                    end else begin
                        pte <= mem_rsp_rdata; pte_addr <= walk_addr;
                        level <= 0; state <= EVAL;
                    end
                end
                EVAL: begin
                    if (!pte_valid) begin
                        result_page_fault <= 1; state <= COMPLETE;
                    end else if (!pte_leaf) begin
                        if (!level || pte[7:4] != 0 || pte[31:30] != 0) begin
                            result_page_fault <= 1; state <= COMPLETE;
                        end else begin
                            walk_addr <= {pte[29:10], 12'b0} + {vpn0, 2'b0};
                            state <= L0_REQ;
                        end
                    end else if ((level && pte[19:10] != 0) ||
                                 pte[31:30] != 0 ||
                                 !leaf_permission_ok(pte[4:0],
                                     saved_privilege, saved_read, saved_write,
                                     saved_execute, saved_sum, saved_mxr)) begin
                        result_page_fault <= 1; state <= COMPLETE;
                    end else if (!pte[6] || (saved_write && !pte[7])) begin
                        ad_mask <= 32'h0000_0040 |
                                   (saved_write ? 32'h0000_0080 : 0);
                        state <= AD_REQ;
                    end else begin
                        result_paddr <= level
                            ? {pte[31:20], saved_vaddr[21:0]}
                            : {pte[29:10], saved_vaddr[11:0]};
                        tlb_valid[tlb_replace] <= 1;
                        tlb_vpn[tlb_replace] <= saved_vaddr[31:12];
                        tlb_ppn[tlb_replace] <= pte[31:10];
                        tlb_asid[tlb_replace] <= satp[30:22];
                        tlb_flags[tlb_replace] <= {pte[7:1], pte[0]};
                        tlb_superpage[tlb_replace] <= level;
                        tlb_replace <= tlb_replace + 1;
                        state <= COMPLETE;
                    end
                end
                AD_REQ: if (!mem_req_allow) begin
                    result_access_fault <= 1; state <= COMPLETE;
                end else if (mem_req_ready) state <= AD_WAIT;
                AD_WAIT: if (mem_rsp_valid) begin
                    if (mem_rsp_error) begin
                        result_access_fault <= 1; state <= COMPLETE;
                    end else begin
                        pte <= mem_rsp_rdata | ad_mask;
                        state <= EVAL;
                    end
                end
                COMPLETE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
`ifdef FORMAL
    reg formal_past_valid = 0;
    initial assume(!rst_n);
    always @(posedge clk) begin
        formal_past_valid <= 1;
        if (formal_past_valid) assume(rst_n);
        if (formal_past_valid && rst_n) begin
        if ($past(rst_n && mem_req_valid && !mem_req_ready)) begin
            assert(mem_req_valid);
            assert($stable({mem_req_addr, mem_req_write, mem_req_wdata,
                            mem_req_be, mem_req_amo, mem_req_amo_op}));
        end
        if (resp_ready) assert(!(page_fault && access_fault));
        if ($past(rst_n && flush)) assert(tlb_valid == 0);
        if (state == AD_REQ || state == AD_WAIT) begin
            assert(mem_req_amo_op == 5'b01000);
            assert(mem_req_wdata[7:6] != 0);
        end
        end
    end
`endif
endmodule
