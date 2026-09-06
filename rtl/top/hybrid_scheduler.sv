// Four issue selections and fourteen execution selections, without age scans.
module hybrid_scheduler (
    input logic [6:0] head,
    input logic [hybrid_pkg::ROB-1:0] waiting, issue_ready, memory_live, memory_pending, memory_ordered,
    input logic [hybrid_pkg::ROB-1:0] class_ready[4],
    input logic [hybrid_pkg::MULDIVS-1:0] mul_active,
    input logic [hybrid_pkg::FPUS-1:0] fp_active,
    input logic [hybrid_pkg::LSUS-1:0] mem_active,
    output integer selected[4], executing[hybrid_pkg::UNITS],
    output wire [7:0] queue_count, memory_count
);
    import hybrid_pkg::*;
    // Preserve the original signed 7-bit age comparison, including wraparound.
    wire [ROB-1:0] priority_mask={ROB{1'b1}}<<(head ^ 7'(ROB/2));
    wire [7:0] waiting_sum[2*ROB], memory_sum[2*ROB];
    assign waiting_sum[0]=0;assign memory_sum[0]=0;
    for(genvar row=0;row<ROB;row++) begin: counts
        assign waiting_sum[ROB+row]={7'b0,waiting[row]};
        assign memory_sum[ROB+row]={7'b0,memory_live[row]};
    end
    for(genvar node=1;node<ROB;node++) begin: count_tree
        assign waiting_sum[node]=waiting_sum[2*node]+waiting_sum[2*node+1];
        assign memory_sum[node]=memory_sum[2*node]+memory_sum[2*node+1];
    end
    assign queue_count=waiting_sum[1];assign memory_count=memory_sum[1];

    always_comb begin: choose
        logic [ROB-1:0] issue_left, memory_left, memory_eligible, execute_left;
        logic available;
        integer first_memory, second_memory, category;
        issue_left=issue_ready;memory_left=memory_pending;memory_eligible='0;
        execute_left='1;available=0;category=0;
        first_memory=select_oldest(memory_left,priority_mask);
        if(first_memory>=0) memory_left[first_memory]=0;
        second_memory=select_oldest(memory_left,priority_mask);
        if(first_memory>=0) begin
            memory_eligible[first_memory]=first_memory==int'(head) || !memory_ordered[first_memory];
            if(second_memory>=0 && !memory_ordered[first_memory] && !memory_ordered[second_memory])
                memory_eligible[second_memory]=1;
        end
        for(int l=0;l<4;l++) begin
            selected[l]=select_oldest(issue_left,priority_mask);
            if(selected[l]>=0) issue_left[selected[l]]=0;
        end
        for(int u=0;u<UNITS;u++) begin
            category=u<MUL_BASE?0:u<FP_BASE?1:u<LSU_BASE?2:3;
            available=u<MUL_BASE?1:u<FP_BASE?!mul_active[u-MUL_BASE]:
                      u<LSU_BASE?!fp_active[u-FP_BASE]:!mem_active[u-LSU_BASE];
            executing[u]=-1;
            if(available) executing[u]=select_oldest(class_ready[category] & execute_left &
                (u<LSU_BASE?{ROB{1'b1}}:memory_eligible),priority_mask);
            if(executing[u]>=0) execute_left[executing[u]]=0;
        end
    end
endmodule
