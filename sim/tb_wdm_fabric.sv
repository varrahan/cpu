module tb_wdm_fabric;
    logic clk=0, rst_n=0, flush=0;
    always #5 clk=~clk;
    logic [1:0] tx_valid=0, tx_ready, rx_valid, rx_ready=0;
    logic [15:0] tx_data[2], rx_data[2];
    logic idle;
    wire [1:0] channel_idle;
    integer sent[2], received[2], cycle=0, parallel_received=0, generation=0;
    logic automatic_traffic=1;
    wdm_fabric #(.CHANNELS(2),.BITS(16),.BITS_PER_CYCLE(4),
        .FLIGHT_CYCLES(2),.CREDIT_CYCLES(3),.DEPTH(8)) dut (.*);
    always @(posedge clk) if(rst_n && automatic_traffic) begin
        cycle++;
        for(int c=0;c<2;c++) begin
            if(tx_valid[c] && tx_ready[c]) sent[c]++;
            if(rx_valid[c] && rx_ready[c]) begin
                assert(rx_data[c]==16'(received[c]+c*1000+generation*10000))
                    else $fatal(1,"channel %0d lost/reordered packet %0d: %0d",c,received[c],rx_data[c]);
                received[c]++;
                if(c==1 && !rx_ready[0]) parallel_received++;
            end
        end
        if(cycle>2000) $fatal(1,"fabric did not drain");
    end
    always @(negedge clk) if(rst_n && automatic_traffic) begin
        rx_ready[0]=cycle>60 && cycle%7!=0;rx_ready[1]=cycle%5!=0;
        for(int c=0;c<2;c++) begin
            tx_valid[c]=sent[c]<64;
            tx_data[c]=16'(sent[c]+c*1000+generation*10000);
        end
    end
    initial begin
        for(int c=0;c<2;c++) begin sent[c]=0;received[c]=0;tx_data[c]=0;end
        repeat(3) @(negedge clk);rst_n=1;
        wait(received[0]==64 && received[1]==64 && idle);
        assert(parallel_received>0) else $fatal(1,"blocked channel stalled its neighbor");
        // Kill buffered packets, a partially serialized packet, and credits in
        // flight; a new generation must never receive any old payload.
        @(posedge clk); #1; automatic_traffic=0;rx_ready=0;tx_valid=3;
        tx_data[0]=16'hdead;tx_data[1]=16'hbeef;
        repeat(14) @(posedge clk);
        #1;tx_valid=0;rx_ready=2;
        @(posedge clk); #1;flush=1;
        @(posedge clk); #1;flush=0;rx_ready=0;
        assert(!rx_valid && idle) else $fatal(1,"flush retained traffic or credits");
        generation=1;cycle=0;
        for(int c=0;c<2;c++) begin sent[c]=0;received[c]=0;end
        automatic_traffic=1;
        wait(received[0]==64 && received[1]==64 && idle);
        @(negedge clk);rst_n=0;
        repeat(2) @(negedge clk);
        assert(!rx_valid && idle) else $fatal(1,"reset retained traffic");
        $display("PASS: WDM serialization, credits, backpressure, independent channels, flush and reset");
        $finish;
    end
endmodule
