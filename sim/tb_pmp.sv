`timescale 1ns/1ps
module tb_pmp;
    logic [31:0] addr, cfg, a0, a1, a2, a3;
    logic [3:0] size;
    logic [1:0] privilege;
    logic access_read, access_write, access_execute;
    wire allow;
    pmp_checker dut (.*,
        .pmpcfg0(cfg), .pmpaddr0(a0), .pmpaddr1(a1),
        .pmpaddr2(a2), .pmpaddr3(a3));

    task expect_allow;
        input expected;
        begin #1; if (allow !== expected) $fatal(1, "PMP mismatch"); end
    endtask

    initial begin
        addr = 32'h1000; size = 4; privilege = 1;
        access_read = 1; access_write = 0; access_execute = 0;
        cfg = 0; a0 = 0; a1 = 0; a2 = 0; a3 = 0;
        expect_allow(0);
        a0 = 32'h0000_0400; cfg[7:0] = 8'b0001_1001; // 8-byte NAPOT R
        expect_allow(1);
        addr = 32'h1004; size = 8; expect_allow(0); // partial overlap
        addr = 32'h1000; size = 4; access_read = 0; access_write = 1;
        expect_allow(0);
        privilege = 3; expect_allow(1); // unlocked M bypass
        cfg[7] = 1; expect_allow(0);     // locked entry applies to M
        $display("PASS: PMP priority/range regression complete");
        $finish;
    end
endmodule
