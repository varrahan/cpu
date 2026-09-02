module safety_harness;
    (* gclk *) reg clk;
    (* anyseq *) reg rst_n;

    regfile regfile_dut (.clk(clk), .rst_n(rst_n));
    icache icache_dut (.clk(clk), .rst_n(rst_n));
    dcache dcache_dut (.clk(clk), .rst_n(rst_n));
    sv32_mmu mmu_dut (.clk(clk), .rst_n(rst_n));
    memory_arbiter4 arbiter_dut (.clk(clk), .rst_n(rst_n));
endmodule
