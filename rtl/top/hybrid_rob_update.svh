// Shared by the compact simulation loop and the synthesized row instances.
    function automatic entry_t completion(input entry_t e,input message_t m);
        entry_t result;
        result=e;result.done=1;result.result=m.data[0];result.next_pc=m.pc;
        result.fault=m.kind==9;result.cause=m.data[1][31:0];result.tval=m.data[2][31:0];
        if(e.d.fp_compute) result.flags=m.instruction[4:0];
        return result;
    endfunction
    function automatic entry_t row_update(input entry_t previous, input logic [6:0] slot);
        entry_t next_entry;
        message_t done_message;
        logic complete_now;
        integer l, k, operand, u;
        next_entry=previous;done_message='0;complete_now=0;
        l=0;k=0;operand=0;u=0;
        if(!rst_n || flush) next_entry='0;
        else begin
            for(l=0;l<4;l++)
                if(l<int'(commit_count) && 7'(head+l)==slot) next_entry.valid=0;
            if(next_entry.valid) begin
                for(k=4;k<RESULT+UNITS;k++)
                    if(rx_valid[k] && rx_ready[k] && rx[k].epoch==epoch &&
                       rx[k].slot==slot) begin
                        if(k<RESULT && rx[k].kind<3) begin
                            for(operand=0;operand<3;operand++) if(rx[k].kind==operand) begin
                                next_entry.operands[operand]=rx[k].data[0];
                                next_entry.received[operand]=1;
                            end
                        end else if((k<RESULT && rx[k].kind>=8) ||
                                    (k>=RESULT && (!next_entry.dest_valid || rx[k].kind==9))) begin
                            complete_now=1;done_message=rx[k];
                        end
                    end
                if(complete_now) next_entry=completion(next_entry,done_message);
                for(k=0;k<4;k++) begin
                    if(rx_valid[k] && rx[k].epoch==epoch && rx[k].slot==slot && next_entry.valid)
                        next_entry.command=1;
                    if(tx_valid[k] && tx[k].slot==slot) begin
                        next_entry.issued=1;next_entry.unit_id=tx[k].destination[$clog2(UNITS)-1:0];
                    end
                end
                for(u=0;u<UNITS;u++) if(tx_valid[RESULT+u] && tx[RESULT+u].slot==slot) begin
                    next_entry.executed=1;
                    if(next_entry.d.csr_en) next_entry.csr_wdata=csr_write_data;
                    if(u>=LSU_BASE) begin
                        next_entry.memory_addr=memory_completion[u-LSU_BASE].memory_addr;
                        next_entry.memory_rdata=memory_completion[u-LSU_BASE].memory_rdata;
                        next_entry.memory_wdata=memory_completion[u-LSU_BASE].memory_wdata;
                        next_entry.rmask=memory_completion[u-LSU_BASE].rmask;next_entry.wmask=memory_completion[u-LSU_BASE].wmask;
                    end
                end
                for(u=0;u<MULDIVS;u++) if(mul_start[u] && executing[MUL_BASE+u]==int'(slot)) next_entry.executed=1;
                for(u=0;u<FPUS;u++) if(fp_start[u] && executing[FP_BASE+u]==int'(slot)) next_entry.executed=1;
                for(u=0;u<LSUS;u++) if(memory_start[u] && executing[LSU_BASE+u]==int'(slot)) next_entry.executed=1;
            end
            for(l=0;l<4;l++)
                if(dispatch_valid[l] && dispatch_slot[l]==slot) next_entry=dispatch_entry[l];
        end
        return next_entry;
    endfunction
