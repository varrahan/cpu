module selector_formal (
    input wire [hybrid_pkg::ROB-1:0] candidates,
    input wire [6:0] head
);
    import hybrid_pkg::*;
    integer reference_slot;
    always_comb begin
        reference_slot=-1;
        for(int slot=0;slot<ROB;slot++)
            if(candidates[slot] && (reference_slot<0 ||
                7'(slot-int'(head))<7'(reference_slot-int'(head)))) reference_slot=slot;
        assert(select_oldest(candidates,{ROB{1'b1}}<<(head ^ 7'(ROB/2)))==reference_slot);
    end
endmodule
