// Exhaustive bounded check of the actual serialized endpoint RTL.
module hybrid_fabric_formal(input logic clk, rst_n, flush,
    input logic [1:0] tx_valid, rx_ready, input logic [7:0] data0, data1);
    wire [1:0] tx_ready, rx_valid;
    wire [7:0] tx_data[2], rx_data[2];
    wire idle;
    wire [1:0] channel_idle;
    assign tx_data[0]=data0;
    assign tx_data[1]=data1;
    wdm_fabric #(.CHANNELS(2),.BITS(8),.BITS_PER_CYCLE(4),
        .DEPTH(2),.FLIGHT_CYCLES(1),.CREDIT_CYCLES(2)) dut (.*);
    reg past_valid=0;
    always @(posedge clk) begin
        past_valid<=1;
        if(past_valid && rst_n && $past(rst_n) && !flush && !$past(flush)) begin
            for(integer c=0;c<2;c++)
                if($past(rx_valid[c] && !rx_ready[c])) begin
                    assert(rx_valid[c]);
                    assert(rx_data[c]==$past(rx_data[c]));
                end
        end
        if(past_valid && $past(!rst_n || flush)) begin
            assert(!rx_valid);
            assert(idle);
        end
    end
endmodule

// The bank encoders must preserve the original rotating-bank, lowest-row policy.
module hybrid_allocator_formal(input logic [255:0] available, input logic [2:0] first_bank,
    input logic enable);
    import hybrid_pkg::*;
    integer expected, physical, actual, bank, row;
    always_comb begin
        expected=-1;physical=0;actual=-1;bank=0;row=0;
        for(bank=0;bank<8;bank++) for(row=0;row<32;row++) begin
            physical=((int'(first_bank)+bank)%8)+row*8;
            if(expected<0 && available[physical]) expected=physical;
        end
        // Match the conditional call in the CPU, including latch checking.
        if(enable) actual=allocate_register(available,int'(first_bank));
        assert(actual==(enable?expected:-1));
    end
endmodule
