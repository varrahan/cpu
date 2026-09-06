`timescale 1ns/1ps
module tb_control;
    import hybrid_pkg::*;
    localparam int RESULT=36;
    logic clk=0, rst_n=0, flush=0;
    logic [6:0] head=0;
    logic [31:0] epoch=0, csr_write_data=0;
    logic [2:0] commit_count=0;
    logic [CHANNELS-1:0] tx_valid=0, rx_valid=0, rx_ready=0;
    // The 5.020 simulator otherwise schedules projections of procedurally driven
    // unpacked-array ports only at initialization. Keep these inputs dynamic.
    message_t tx[CHANNELS] /* verilator public_flat_rw */;
    message_t rx[CHANNELS] /* verilator public_flat_rw */;
    entry_t memory_completion[LSUS] /* verilator public_flat_rw */;
    entry_t dispatch_entry[4] /* verilator public_flat_rw */;
    logic [MULDIVS-1:0] mul_start=0;
    logic [FPUS-1:0] fp_start=0;
    logic [LSUS-1:0] memory_start=0;
    integer executing[UNITS];
    logic [3:0] dispatch_valid=0;
    logic [6:0] dispatch_slot[4];
    wire [ROB*$bits(entry_t)-1:0] data;
    entry_t reference_entries[ROB], next_reference[ROB];
    hybrid_rob dut (.*);
    // Also exercise the actual storage module instantiated by SYNTHESIS.
    entry_t synthesized_row;
    hybrid_rob_row row_storage (
        .clk,.rst_n,.flush,.csr_write_data,.operand_kind(dut.operand_kind),
        .operands(dut.operands),.completions(dut.completions),.memory_trace(dut.memory_trace),
        .complete_any(dut.complete_any),.complete_no_dest(dut.complete_no_dest),
        .issue_unit(dut.issue_unit),.dispatch_entry,
        .retire_row(dut.retired[0]),.command_row(dut.commanded[0]),.start_row(dut.started[0]),
        .hits(dut.hits[0]),.issue_hits(dut.issue_hits[0]),.dispatch_hits(dut.dispatch_hits[0]),
        .execute_hits(dut.execute_hits[0]),.entry(synthesized_row));
    `include "sim/rob_reference.svh"

    logic [ROB-1:0] waiting='0, issue_ready='0, memory_live='0, memory_pending='0, memory_ordered='0;
    logic [ROB-1:0] class_ready[4];
    logic [MULDIVS-1:0] mul_active=0;
    logic [FPUS-1:0] fp_active=0;
    logic [LSUS-1:0] mem_active=0;
    wire [7:0] queue_count, memory_count;
    integer selected[4], scheduled[UNITS];
    hybrid_scheduler scheduler (.head,.waiting,.issue_ready,.memory_live,.memory_pending,
        .memory_ordered,.class_ready,.mul_active,.fp_active,.mem_active,
        .selected,.executing(scheduled),.queue_count,.memory_count);

    function automatic integer reference_oldest(input logic [ROB-1:0] candidates);
        integer best;
        best=-1;
        for(int slot=0;slot<ROB;slot++)
            if(candidates[slot] && (best<0 || 7'(slot-int'(head))<7'(best-int'(head)))) best=slot;
        return best;
    endfunction
    task automatic check_scheduler;
        logic [ROB-1:0] remaining, eligible;
        integer first_mem, second_mem, chosen, category;
        logic available;
        #1;
        assert(queue_count==$countones(waiting) && memory_count==$countones(memory_live))
            else $fatal(1,"scheduler population count");
        remaining=memory_pending;eligible='0;
        first_mem=reference_oldest(remaining);
        if(first_mem>=0) remaining[first_mem]=0;
        second_mem=reference_oldest(remaining);
        if(first_mem>=0) begin
            eligible[first_mem]=first_mem==int'(head) || !memory_ordered[first_mem];
            if(second_mem>=0 && !memory_ordered[first_mem] && !memory_ordered[second_mem])
                eligible[second_mem]=1;
        end
        remaining=issue_ready;
        for(int l=0;l<4;l++) begin
            chosen=reference_oldest(remaining);
            assert(selected[l]==chosen) else $fatal(1,"issue selection lane %0d head %0d",l,head);
            if(chosen>=0) remaining[chosen]=0;
        end
        remaining='1;
        for(int u=0;u<UNITS;u++) begin
            category=u<MUL_BASE?0:u<FP_BASE?1:u<LSU_BASE?2:3;
            available=u<MUL_BASE?1:u<FP_BASE?!mul_active[u-MUL_BASE]:
                u<LSU_BASE?!fp_active[u-FP_BASE]:!mem_active[u-LSU_BASE];
            chosen=-1;
            if(available) chosen=reference_oldest(class_ready[category] & remaining &
                (u<LSU_BASE?{ROB{1'b1}}:eligible));
            assert(scheduled[u]==chosen) else $fatal(1,"execution selection unit %0d head %0d",u,head);
            if(chosen>=0) remaining[chosen]=0;
        end
    endtask
    function automatic entry_t random_entry;
        entry_t value;
        value='0;
        for(int word_index=0;word_index<($bits(entry_t)+31)/32;word_index++)
            value=(value<<32)|entry_t'($urandom);
        return value;
    endfunction
    function automatic message_t random_message;
        message_t value;
        value='0;
        for(int w=0;w<($bits(message_t)+31)/32;w++)
            value=(value<<32)|message_t'($urandom);
        return value;
    endfunction
    task automatic tick;
        #1;
        for(int row=0;row<ROB;row++) next_reference[row]=reference_row_update(reference_entries[row],7'(row));
        clk=1;#1;
        assert(synthesized_row===next_reference[0]) else $fatal(1,"synthesized ROB row transition");
        for(int row=0;row<ROB;row++) begin
            if(data[row*$bits(entry_t)+:$bits(entry_t)]!==next_reference[row]) begin
                $display("expected %h actual %h",next_reference[row],data[row*$bits(entry_t)+:$bits(entry_t)]);
                $fatal(1,"ROB transition mismatch row %0d time %0t",row,$time);
            end
            reference_entries[row]=next_reference[row];
        end
        clk=0;
    endtask
    initial begin
        integer seed, hot;
        message_t packet;
        seed=32'h5eedc0de;seed=$urandom(seed);
        for(int k=0;k<CHANNELS;k++) begin tx[k]='0;rx[k]='0;end
        for(int u=0;u<UNITS;u++) executing[u]=-1;
        for(int l=0;l<4;l++) begin dispatch_slot[l]=0;dispatch_entry[l]='0;end
        for(int u=0;u<LSUS;u++) memory_completion[u]='0;
        for(int c=0;c<4;c++) class_ready[c]='0;
        tick();
        // Every head and single ready slot, plus empty/full masks and random conflicts.
        for(int h=0;h<ROB;h++) begin
            head=7'(h);issue_ready='0;check_scheduler();
            issue_ready='1;waiting='1;memory_live='1;check_scheduler();
            for(int slot=0;slot<ROB;slot++) begin
                issue_ready=ROB'(1)<<slot;check_scheduler();
            end
        end
        for(int trial=0;trial<2000;trial++) begin
            head=7'($urandom);mul_active=MULDIVS'($urandom);
            fp_active=FPUS'($urandom);mem_active=LSUS'($urandom);
            for(int row=0;row<ROB;row++) begin
                waiting[row]=1'($urandom);issue_ready[row]=1'($urandom);
                memory_live[row]=1'($urandom);memory_pending[row]=1'($urandom);
                memory_ordered[row]=1'($urandom);
                for(int c=0;c<4;c++) class_ready[c][row]=1'($urandom);
            end
            check_scheduler();
        end
        $display("PASS scheduler: all head/slot pairs, empty/full masks, 2000 random schedules");
        rst_n=1;
        for(int trial=0;trial<3000;trial++) begin
            hot=$urandom_range(0,ROB-1);head=7'($urandom);csr_write_data=$urandom;
            commit_count=3'($urandom);flush=trial%101==0;rst_n=trial%257!=0;
            if(trial%31==0) epoch++;
            tx_valid=CHANNELS'({$urandom,$urandom});
            rx_valid=CHANNELS'({$urandom,$urandom});rx_ready=CHANNELS'({$urandom,$urandom});
            for(int k=0;k<CHANNELS;k++) begin
                packet=random_message();
                packet.slot=trial%2==0?7'(hot):7'($urandom);
                tx[k]=packet;
                packet=random_message();
                packet.slot=trial%2==0?7'(hot):7'($urandom);
                packet.epoch=k%4==0?epoch-1:epoch;
                packet.kind=4'((trial+k)%16);
                rx[k]=packet;
            end
            mul_start=MULDIVS'($urandom);fp_start=FPUS'($urandom);memory_start=LSUS'($urandom);
            for(int u=0;u<UNITS;u++) executing[u]=trial%2==0?hot:int'($urandom_range(0,ROB+2))-1;
            dispatch_valid=4'($urandom);
            for(int l=0;l<4;l++) begin
                dispatch_slot[l]=trial%3==0?7'(hot):7'($urandom);
                dispatch_entry[l]=random_entry();
                dispatch_entry[l].valid=1;
            end
            if(trial<ROB/4) begin
                dispatch_valid='1;
                for(int l=0;l<4;l++) dispatch_slot[l]=7'(4*trial+l);
            end
            for(int u=0;u<LSUS;u++) memory_completion[u]=random_entry();
            tick();
        end
        $display("PASS ROB: 3000 cycles, all 128 full records checked against original transitions");
        $finish;
    end
endmodule
