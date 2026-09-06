package hybrid_pkg;
    localparam int PHYS = 256;
    localparam int ROB = 128;
    localparam int IQ = 64;
    localparam int ALUS = 8, MULDIVS = 2, FPUS = 2, LSUS = 2;
    localparam int MUL_BASE = ALUS, FP_BASE = MUL_BASE + MULDIVS;
    localparam int LSU_BASE = FP_BASE + FPUS, UNITS = LSU_BASE + LSUS;
    // Dedicated producer channels: issue, register responses, results, fetch.
    localparam int CHANNELS = 4 + 32 + UNITS + 2;
    typedef struct packed {
        logic [31:0] epoch;
        logic [6:0] slot;
        logic [7:0] destination;
        logic [3:0] kind;
        logic [31:0] instruction;
        logic [31:0] pc;
        logic [2:0][63:0] data;
    } message_t;
    localparam int MESSAGE_BITS = $bits(message_t);
    typedef struct packed {
        logic [4:0] rs1, rs2, rd;
        logic [31:0] imm;
        logic [3:0] alu_op;
        logic alu_src, mem_read, mem_write, reg_write, branch, jal, jalr;
        logic [2:0] funct3;
        logic lui, auipc, uses_rs1, uses_rs2, illegal, fence, fence_i;
        logic muldiv;
        logic [2:0] muldiv_op;
        logic amo;
        logic [4:0] amo_op;
        logic fp_compute, fp_load, fp_store, fp_uses_rs1, fp_uses_rs2, fp_uses_rs3;
        logic csr_en;
        logic [1:0] csr_cmd;
        logic csr_imm, ecall, ebreak, mret, sret, sfence_vma, wfi;
    } decode_t;
    typedef struct packed {
        logic valid, issued, command, executed, done, fault;
        logic [2:0] received;
        logic [$clog2(UNITS)-1:0] unit_id;
        logic [31:0] pc, raw, instruction, next_pc, cause, tval;
        logic [2:0] length;
        decode_t d;
        logic dest_fp, dest_valid;
        logic [7:0] pdst, stale;
        logic [2:0] src_used, src_fp;
        logic [2:0][7:0] src;
        logic [2:0][63:0] operands;
        logic [63:0] result;
        logic [4:0] flags;
        logic [31:0] memory_addr, memory_rdata, memory_wdata, csr_wdata;
        logic [3:0] rmask, wmask;
    } entry_t;
    typedef struct packed {
        logic fault;
        logic [63:0] result;
        logic [31:0] next_pc, cause, tval;
        logic [4:0] flags;
    } rob_completion_t;
    typedef struct packed {
        logic [31:0] addr, rdata, wdata;
        logic [3:0] rmask, wmask;
    } memory_trace_t;
    typedef struct packed {
        logic valid, dest_valid, dest_fp;
        logic [7:0] pdst;
    } writeback_info_t;
    typedef struct packed {
        logic [31:0] instruction, pc;
        logic [2:0] src_used, src_fp;
        logic [2:0][7:0] src;
        logic [$clog2(UNITS)-1:0] category;
    } issue_info_t;
    // A seven-level binary priority tree finds the first set bit. Search the
    // caller's circular priority mask first, then wrap to physical slot zero.
    function automatic integer select_oldest(
        input logic [ROB-1:0] candidates, priority_mask
    );
        logic [ROB-1:0] remaining;
        logic [6:0] index;
        integer b;
        remaining=candidates & priority_mask;
        if(remaining==0) remaining=candidates;
        index=0;
        for(b=6;b>=0;b--) begin
            if((remaining & ((ROB'(1)<<(1<<b))-ROB'(1)))==0) begin
                index[b]=1;remaining >>= 1<<b;
            end
        end
        return candidates==0 ? -1 : int'(index);
    endfunction

    function automatic integer allocate_register(input logic [PHYS-1:0] available,
                                                 input integer first_bank);
        integer bank_choice[8], bank, chosen, b, row, offset;
        logic [31:0] rows, first;
        logic [4:0] row_index;
        // Encode each bank once, then choose banks in round-robin order.
        // Constant physical indices avoid a full PRF mux for every candidate.
        b=0;row=0;offset=0;
        for(b=0;b<8;b++) begin
            for(row=0;row<32;row++) rows[row]=available[row*8+b];
            // Isolate the lowest free row, then encode its one-hot position.
            first=rows & (~rows+32'd1);
            row_index[0]=|(first & 32'haaaa_aaaa);
            row_index[1]=|(first & 32'hcccc_cccc);
            row_index[2]=|(first & 32'hf0f0_f0f0);
            row_index[3]=|(first & 32'hff00_ff00);
            row_index[4]=|(first & 32'hffff_0000);
            bank_choice[b]=rows==0?-1:int'({row_index,3'(b)});
        end
        chosen=-1;
        for(offset=0;offset<8;offset++) begin
            bank=(first_bank+offset)%8;
            if(chosen<0 && bank_choice[bank]>=0) chosen=bank_choice[bank];
        end
        return chosen;
    endfunction
endpackage
