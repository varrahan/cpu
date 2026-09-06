// Common transition for the simulation loop and synthesized row cells.
// Match masks are decoded once by hybrid_rob. Highest channel/lane wins,
// including when several packets update the same row in one cycle.
    function automatic entry_t row_update(
        input entry_t previous,
        input logic retire_row, command_row, start_row,
        input logic [EVENTS-1:0] row_matches,
        input logic [3:0] issue_mask, dispatch_mask,
        input logic [UNITS-1:0] execute_mask,
        input logic [31:0] kinds[3],
        input logic [63:0] operand_values[32],
        input rob_completion_t completion_values[EVENTS],
        input logic [EVENTS-1:0] any_completion, no_dest_completion,
        input logic [$clog2(UNITS)-1:0] issue_units[4],
        input memory_trace_t traces[LSUS],
        input entry_t dispatch_values[4]
    );
        entry_t next_entry, dispatched;
        rob_completion_t completed;
        logic [31:0] operand_pick;
        logic [EVENTS-1:0] complete_pick;
        logic [3:0] dispatch_pick;
        logic [63:0] operand_data;
        logic found;
        integer p,k,l,u;
        next_entry=previous;
        dispatched='0;completed='0;operand_pick='0;complete_pick='0;
        dispatch_pick='0;operand_data='0;found=0;
        p=0;k=0;l=0;u=0;
        if(!rst_n || flush) next_entry='0;
        else begin
            if(retire_row) next_entry.valid=0;
            if(next_entry.valid) begin
                for(p=0;p<3;p++) begin
                    operand_pick='0;found=0;operand_data='0;
                    for(k=31;k>=0;k--) begin
                        operand_pick[k]=row_matches[k] && kinds[p][k] && !found;
                        found |= row_matches[k] && kinds[p][k];
                    end
                    for(k=0;k<32;k++)
                        operand_data |= operand_values[k] & {64{operand_pick[k]}};
                    if(found) begin
                        next_entry.operands[p]=operand_data;
                        next_entry.received[p]=1;
                    end
                end
                found=0;
                for(k=EVENTS-1;k>=0;k--) begin
                    complete_pick[k]=row_matches[k] &&
                        (any_completion[k] || (no_dest_completion[k] && !previous.dest_valid)) && !found;
                    found |= row_matches[k] &&
                        (any_completion[k] || (no_dest_completion[k] && !previous.dest_valid));
                end
                for(k=0;k<EVENTS;k++)
                    completed |= completion_values[k] & {$bits(rob_completion_t){complete_pick[k]}};
                if(found) begin
                    next_entry.done=1;next_entry.result=completed.result;
                    next_entry.next_pc=completed.next_pc;next_entry.fault=completed.fault;
                    next_entry.cause=completed.cause;next_entry.tval=completed.tval;
                    if(previous.d.fp_compute) next_entry.flags=completed.flags;
                end
                if(command_row) next_entry.command=1;
                for(l=0;l<4;l++) if(issue_mask[l]) begin
                    next_entry.issued=1;next_entry.unit_id=issue_units[l];
                end
                if(|execute_mask) begin
                    next_entry.executed=1;
                    if(previous.d.csr_en) next_entry.csr_wdata=csr_write_data;
                end
                for(u=0;u<LSUS;u++) if(execute_mask[LSU_BASE+u]) begin
                    next_entry.memory_addr=traces[u].addr;
                    next_entry.memory_rdata=traces[u].rdata;
                    next_entry.memory_wdata=traces[u].wdata;
                    next_entry.rmask=traces[u].rmask;next_entry.wmask=traces[u].wmask;
                end
                if(start_row) next_entry.executed=1;
            end
            found=0;
            for(l=3;l>=0;l--) begin
                dispatch_pick[l]=dispatch_mask[l] && !found;
                found |= dispatch_mask[l];
            end
            for(l=0;l<4;l++)
                dispatched |= dispatch_values[l] & {$bits(entry_t){dispatch_pick[l]}};
            if(found) next_entry=dispatched;
        end
        return next_entry;
    endfunction
