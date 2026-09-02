module top_harness;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;
    top dut (.clk(clk), .rst_n(rst_n));
endmodule
