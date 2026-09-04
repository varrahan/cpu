module regfile_harness;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;

    regfile dut (.clk(clk), .rst_n(rst_n));
endmodule

module icache_harness;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;

    icache dut (.clk(clk), .rst_n(rst_n));
endmodule

module dcache_harness;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;

    dcache dut (.clk(clk), .rst_n(rst_n), .cpu_cacheable(1'b1));
endmodule

module mmu_harness;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;

    sv32_mmu dut (.clk(clk), .rst_n(rst_n));
endmodule

module arbiter_harness;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;

    memory_arbiter4 dut (.clk(clk), .rst_n(rst_n));
endmodule
