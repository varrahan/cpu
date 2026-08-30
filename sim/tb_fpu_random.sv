`timescale 1ns/1ps
module tb_fpu_random;
    import "DPI-C" function int unsigned sf_f32(
        input int unsigned op, input int unsigned a, input int unsigned b,
        input int unsigned rm, output int unsigned flags);
    import "DPI-C" function longint unsigned sf_f64(
        input int unsigned op, input longint unsigned a,
        input longint unsigned b, input int unsigned rm,
        output int unsigned flags);
    logic clk = 0, rst_n = 0, start = 0, flush = 0;
    logic [31:0] instr = 0, rs1_int = 0;
    logic [63:0] frs1 = 0, frs2 = 0, frs3 = 0;
    logic [2:0] frm = 0;
    wire ready, busy, done, illegal, result_to_int, write_fp;
    wire [63:0] result; wire [4:0] flags;
    integer tests = 0;
    always #5 clk = ~clk;
    P_FPU64 dut (.*);
    function automatic [31:0] op_fp(input [6:0] funct7, input [2:0] rm);
        op_fp = {funct7, 5'd0, 5'd1, rm, 5'd3, 7'h53};
    endfunction
    function automatic [31:0] finite32(input [31:0] value);
        begin finite32 = value; if (&value[30:23]) finite32[30:23] = 8'hfe; end
    endfunction
    function automatic [63:0] finite64(input [63:0] value);
        begin finite64 = value; if (&value[62:52]) finite64[62:52] = 11'h7fe; end
    endfunction
    task automatic issue(input [31:0] operation,
                         input [63:0] expected, input [4:0] expected_flags);
        integer wait_cycles;
        begin
            while (!ready) @(posedge clk);
            instr = operation; start = 1; @(posedge clk); #1; start = 0;
            wait_cycles = 0;
            while (!done && wait_cycles < 200) begin
                @(posedge clk); #1; wait_cycles++;
            end
            if (!done || illegal || result !== expected ||
                flags !== expected_flags || result_to_int || !write_fp)
                $fatal(1, "SoftFloat mismatch insn=%h got=%h/%02x expected=%h/%02x",
                       operation, result, flags, expected, expected_flags);
            tests++;
        end
    endtask
    initial begin : random_vectors
        integer op, rm, n;
        int unsigned a32, b32, z32, ref_flags;
        longint unsigned a64, b64, z64;
        repeat (4) @(posedge clk); rst_n = 1;
        void'($urandom(32'h5eed_c0de));
        for (op = 0; op < 4; op++) for (rm = 0; rm < 5; rm++)
            for (n = 0; n < 100; n++) begin
                a32 = finite32($urandom); b32 = finite32($urandom);
                if (op == 2 && b32[30:0] == 0) b32 = 32'h3f80_0000;
                if (op == 3) a32[31] = 0;
                z32 = sf_f32(op, a32, b32, rm, ref_flags);
                frs1 = {32'hffff_ffff, a32}; frs2 = {32'hffff_ffff, b32};
                issue(op_fp(op == 0 ? 7'b0000000 : op == 1 ? 7'b0001000 :
                            op == 2 ? 7'b0001100 : 7'b0101100, rm[2:0]),
                      {32'hffff_ffff, z32}, ref_flags[4:0]);
                a64 = finite64({$urandom, $urandom});
                b64 = finite64({$urandom, $urandom});
                if (op == 2 && b64[62:0] == 0) b64 = 64'h3ff0000000000000;
                if (op == 3) a64[63] = 0;
                z64 = sf_f64(op, a64, b64, rm, ref_flags);
                frs1 = a64; frs2 = b64;
                issue(op_fp(op == 0 ? 7'b0000001 : op == 1 ? 7'b0001001 :
                            op == 2 ? 7'b0001101 : 7'b0101101, rm[2:0]),
                      z64, ref_flags[4:0]);
            end
        $display("PASS: %0d randomized Berkeley SoftFloat comparisons", tests);
        $finish;
    end
endmodule
