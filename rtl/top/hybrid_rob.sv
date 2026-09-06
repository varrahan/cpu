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
    localparam int RESULT=36, EVENTS=32+UNITS;
    entry_t entries[ROB];
    logic [31:0] operand_kind[3];
    logic [63:0] operands[32];
    rob_completion_t completions[EVENTS];
    memory_trace_t memory_trace[LSUS];
    logic [EVENTS-1:0] complete_any, complete_no_dest;
    logic [$clog2(UNITS)-1:0] issue_unit[4];
    wire [ROB-1:0] receive_target[CHANNELS], transmit_target[CHANNELS];
    wire [ROB-1:0] commit_target[4], dispatch_target[4], launch_target[UNITS];
    logic [ROB-1:0] retired, commanded, started;
    wire [EVENTS-1:0] hits[ROB];
    wire [3:0] issue_hits[ROB], dispatch_hits[ROB];
    wire [UNITS-1:0] execute_hits[ROB];

    // Decode packet acceptance and slot addresses once, before the row boundary.
    for(genvar k=0;k<CHANNELS;k++) begin: targets
        assign receive_target[k]=(ROB'(1)<<rx[k].slot) &
            {ROB{rx_valid[k] && rx[k].epoch==epoch}};
        assign transmit_target[k]=(ROB'(1)<<tx[k].slot) & {ROB{tx_valid[k]}};
    end
    for(genvar k=0;k<EVENTS;k++) begin: completion_fields
        assign complete_any[k]=k<32 ? rx[k+4].kind>=8 : rx[k+4].kind==9;
        assign complete_no_dest[k]=k>=32;
        assign completions[k]={rx[k+4].kind==9,rx[k+4].data[0],rx[k+4].pc,
            rx[k+4].data[1][31:0],rx[k+4].data[2][31:0],rx[k+4].instruction[4:0]};
    end
    for(genvar k=0;k<32;k++) begin: operand_fields
        assign operands[k]=rx[k+4].data[0];
        for(genvar p=0;p<3;p++) assign operand_kind[p][k]=rx[k+4].kind==p;
    end
    for(genvar u=0;u<LSUS;u++)
        assign memory_trace[u]={memory_completion[u].memory_addr,
            memory_completion[u].memory_rdata,memory_completion[u].memory_wdata,
            memory_completion[u].rmask,memory_completion[u].wmask};
    for(genvar l=0;l<4;l++) begin: lane_targets
        assign issue_unit[l]=tx[l].destination[$clog2(UNITS)-1:0];
        assign commit_target[l]=(ROB'(1)<<7'(head+l)) & {ROB{l<int'(commit_count)}};
        assign dispatch_target[l]=(ROB'(1)<<dispatch_slot[l]) & {ROB{dispatch_valid[l]}};
    end
    for(genvar u=0;u<UNITS;u++) begin: launch_targets
        if(u<MUL_BASE) assign launch_target[u]='0;
        else if(u<FP_BASE)
            assign launch_target[u]=(ROB'(1)<<executing[u]) & {ROB{mul_start[u-MUL_BASE]}};
        else if(u<LSU_BASE)
            assign launch_target[u]=(ROB'(1)<<executing[u]) & {ROB{fp_start[u-FP_BASE]}};
        else assign launch_target[u]=(ROB'(1)<<executing[u]) & {ROB{memory_start[u-LSU_BASE]}};
    end
    always_comb begin
        retired='0;commanded='0;started='0;
        for(int l=0;l<4;l++) begin
            retired |= commit_target[l];commanded |= receive_target[l];
        end
        for(int u=0;u<UNITS;u++) started |= launch_target[u];
    end
    for(genvar row=0;row<ROB;row++) begin: row_inputs
        assign data[row*$bits(entry_t)+:$bits(entry_t)]=entries[row];
        for(genvar k=0;k<EVENTS;k++)
            assign hits[row][k]=receive_target[k+4][row] && rx_ready[k+4];
        for(genvar l=0;l<4;l++) begin
            assign issue_hits[row][l]=transmit_target[l][row];
            assign dispatch_hits[row][l]=dispatch_target[l][row];
        end
        for(genvar u=0;u<UNITS;u++) assign execute_hits[row][u]=transmit_target[RESULT+u][row];
    end
`ifdef SYNTHESIS
    // Keep the wide state arrays bounded in Yosys; common decoding stays outside.
    for(genvar row=0;row<ROB;row++) begin: rows
        hybrid_rob_row storage (
            .clk,.rst_n,.flush,.csr_write_data,.operand_kind,.operands,.completions,
            .memory_trace,.complete_any,.complete_no_dest,.issue_unit,.dispatch_entry,
            .retire_row(retired[row]),.command_row(commanded[row]),.start_row(started[row]),
            .hits(hits[row]),.issue_hits(issue_hits[row]),.dispatch_hits(dispatch_hits[row]),
            .execute_hits(execute_hits[row]),.entry(entries[row]));
    end
`else
    `include "rtl/top/hybrid_rob_update.svh"
    entry_t next_entries[ROB];
    always_comb
        for(int row=0;row<ROB;row++) next_entries[row]=row_update(entries[row],
            retired[row],commanded[row],started[row],hits[row],issue_hits[row],
            dispatch_hits[row],execute_hits[row],operand_kind,operands,completions,
            complete_any,complete_no_dest,issue_unit,memory_trace,dispatch_entry);
    always_ff @(posedge clk) entries<=next_entries;
`endif
endmodule

module hybrid_rob_row (
    input logic clk, rst_n, flush,
    input logic [31:0] csr_write_data,
    input logic [31:0] operand_kind[3],
    input logic [63:0] operands[32],
    input hybrid_pkg::rob_completion_t completions[32+hybrid_pkg::UNITS],
    input hybrid_pkg::memory_trace_t memory_trace[hybrid_pkg::LSUS],
    input logic [32+hybrid_pkg::UNITS-1:0] complete_any, complete_no_dest,
    input logic [$clog2(hybrid_pkg::UNITS)-1:0] issue_unit[4],
    input hybrid_pkg::entry_t dispatch_entry[4],
    input logic retire_row, command_row, start_row,
    input logic [32+hybrid_pkg::UNITS-1:0] hits,
    input logic [3:0] issue_hits, dispatch_hits,
    input logic [hybrid_pkg::UNITS-1:0] execute_hits,
    output hybrid_pkg::entry_t entry
);
    import hybrid_pkg::*;
    localparam int EVENTS=32+UNITS;
    `include "rtl/top/hybrid_rob_update.svh"
    entry_t next_entry;
    always_comb next_entry=row_update(entry,retire_row,command_row,start_row,
        hits,issue_hits,dispatch_hits,execute_hits,operand_kind,operands,completions,
        complete_any,complete_no_dest,issue_unit,memory_trace,dispatch_entry);
    always_ff @(posedge clk) entry<=next_entry;
endmodule
