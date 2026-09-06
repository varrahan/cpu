`timescale 1ns/1ps
module tb_fpu_random;
    import "DPI-C" function int unsigned sf_f32(
        input int unsigned op, input int unsigned a, input int unsigned b,
        input int unsigned rm, output int unsigned flags);
    import "DPI-C" function longint unsigned sf_f64(
        input int unsigned op, input longint unsigned a,
        input longint unsigned b, input int unsigned rm,
        output int unsigned flags);
    import "DPI-C" function int unsigned sf_fma32(
        input int unsigned op, input int unsigned a, input int unsigned b,
        input int unsigned c, input int unsigned rm,
        output int unsigned flags);
    import "DPI-C" function longint unsigned sf_fma64(
        input int unsigned op, input longint unsigned a,
        input longint unsigned b, input longint unsigned c,
        input int unsigned rm, output int unsigned flags);
    import "DPI-C" function int unsigned sf_cmp32(
        input int unsigned op, input int unsigned a, input int unsigned b,
        output int unsigned flags);
    import "DPI-C" function int unsigned sf_cmp64(
        input int unsigned op, input longint unsigned a,
        input longint unsigned b, output int unsigned flags);
    import "DPI-C" function longint unsigned sf_convert(
        input int unsigned op, input longint unsigned a,
        input int unsigned rm, output int unsigned flags);

    logic clk = 0, rst_n = 0, start = 0, flush = 0;
    logic [31:0] instr = 0, rs1_int = 0;
    logic [63:0] frs1 = 0, frs2 = 0, frs3 = 0;
    logic [2:0] frm = 0;
    wire ready, busy, done, illegal, result_to_int, write_fp;
    wire [63:0] result;
    wire [4:0] flags;
    integer tests = 0;

    always #5 clk = ~clk;
    fpu_unit dut (.*);

    function automatic [31:0] op_fp(
        input [6:0] funct7, input [4:0] rs2, input [2:0] rm);
        op_fp = {funct7, rs2, 5'd1, rm, 5'd3, 7'h53};
    endfunction

    function automatic [31:0] op_fma(
        input [6:0] opcode, input bit fp64, input [2:0] rm);
        op_fma = {5'd2, 1'b0, fp64, 5'd0, 5'd1, rm, 5'd3, opcode};
    endfunction

    function automatic [6:0] arithmetic_funct7(input integer op, input bit fp64);
        case (op)
            0: arithmetic_funct7 = fp64 ? 7'b0000001 : 7'b0000000;
            1: arithmetic_funct7 = fp64 ? 7'b0000101 : 7'b0000100;
            2: arithmetic_funct7 = fp64 ? 7'b0001001 : 7'b0001000;
            3: arithmetic_funct7 = fp64 ? 7'b0001101 : 7'b0001100;
            default: arithmetic_funct7 = fp64 ? 7'b0101101 : 7'b0101100;
        endcase
    endfunction

    function automatic [6:0] fma_opcode(input integer op);
        case (op)
            0: fma_opcode = 7'h43;
            1: fma_opcode = 7'h47;
            2: fma_opcode = 7'h4b;
            default: fma_opcode = 7'h4f;
        endcase
    endfunction

    task automatic issue(
        input [31:0] operation, input [63:0] expected,
        input [4:0] expected_flags, input bit expected_to_int,
        input bit expected_write_fp);
        integer wait_cycles;
        begin
            while (!ready) @(posedge clk);
            instr = operation;
            start = 1;
            @(posedge clk); #1;
            start = 0;
            wait_cycles = 0;
            while (!done && wait_cycles < 200) begin
                @(posedge clk); #1;
                wait_cycles++;
            end
            if (!done || illegal || result !== expected ||
                flags !== expected_flags ||
                result_to_int !== expected_to_int ||
                write_fp !== expected_write_fp)
                $fatal(1, "SoftFloat mismatch insn=%h got=%h/%02x expected=%h/%02x",
                       operation, result, flags, expected, expected_flags);
            tests++;
        end
    endtask

    task automatic check32(
        input integer op, input int unsigned a, input int unsigned b,
        input integer rm, input bit dynamic);
        int unsigned z, ref_flags;
        begin
            z = sf_f32(op, a, b, rm, ref_flags);
            frs1 = {32'hffff_ffff, a};
            frs2 = {32'hffff_ffff, b};
            frm = rm[2:0];
            issue(op_fp(arithmetic_funct7(op, 0), 0,
                        dynamic ? 3'b111 : rm[2:0]),
                  {32'hffff_ffff, z}, ref_flags[4:0], 0, 1);
        end
    endtask

    task automatic check64(
        input integer op, input longint unsigned a,
        input longint unsigned b, input integer rm, input bit dynamic);
        longint unsigned z;
        int unsigned ref_flags;
        begin
            z = sf_f64(op, a, b, rm, ref_flags);
            frs1 = a;
            frs2 = b;
            frm = rm[2:0];
            issue(op_fp(arithmetic_funct7(op, 1), 0,
                        dynamic ? 3'b111 : rm[2:0]),
                  z, ref_flags[4:0], 0, 1);
        end
    endtask

    initial begin : random_vectors
        integer op, rm, n;
        int unsigned a32, b32, c32, z32, ref_flags;
        longint unsigned a64, b64, c64, z64, converted;
        repeat (4) @(posedge clk);
        rst_n = 1;
        void'($urandom(32'h5eed_c0de));

        // Deterministic IEEE-754 edges: NaNs, infinities, signed zero,
        // subnormals, divide-by-zero, invalid, underflow, and inexact.
        check32(0, 32'h7f80_0000, 32'hff80_0000, 0, 0);
        check32(0, 32'h7fa0_0001, 32'h3f80_0000, 0, 0);
        check32(0, 32'h0000_0001, 32'h0000_0001, 0, 0);
        check32(0, 32'h8000_0000, 32'h0000_0000, 3, 1);
        check32(3, 32'h3f80_0000, 32'h0000_0000, 0, 0);
        check32(4, 32'hbf80_0000, 0, 0, 0);
        check64(0, 64'h7ff0_0000_0000_0000,
                   64'hfff0_0000_0000_0000, 0, 0);
        check64(0, 64'h7ff4_0000_0000_0001,
                   64'h3ff0_0000_0000_0000, 0, 0);
        check64(0, 64'h0000_0000_0000_0001,
                   64'h0000_0000_0000_0001, 0, 0);
        check64(3, 64'h3ff0_0000_0000_0000, 0, 0, 0);
        check64(4, 64'hbff0_0000_0000_0000, 0, 0, 0);

        for (op = 0; op < 5; op++)
            for (rm = 0; rm < 5; rm++)
                for (n = 0; n < 50; n++) begin
                    a32 = $urandom;
                    b32 = $urandom;
                    check32(op, a32, b32, rm, n[0]);
                    a64 = {$urandom, $urandom};
                    b64 = {$urandom, $urandom};
                    check64(op, a64, b64, rm, n[0]);
                end

        for (op = 0; op < 4; op++)
            for (rm = 0; rm < 5; rm++)
                for (n = 0; n < 50; n++) begin
                    a32 = $urandom; b32 = $urandom; c32 = $urandom;
                    z32 = sf_fma32(op, a32, b32, c32, rm, ref_flags);
                    frs1 = {32'hffff_ffff, a32};
                    frs2 = {32'hffff_ffff, b32};
                    frs3 = {32'hffff_ffff, c32};
                    frm = rm[2:0];
                    issue(op_fma(fma_opcode(op), 0, n[0] ? 3'b111 : rm[2:0]),
                          {32'hffff_ffff, z32}, ref_flags[4:0], 0, 1);
                    a64 = {$urandom, $urandom};
                    b64 = {$urandom, $urandom};
                    c64 = {$urandom, $urandom};
                    z64 = sf_fma64(op, a64, b64, c64, rm, ref_flags);
                    frs1 = a64; frs2 = b64; frs3 = c64;
                    issue(op_fma(fma_opcode(op), 1, n[0] ? 3'b111 : rm[2:0]),
                          z64, ref_flags[4:0], 0, 1);
                end

        for (op = 0; op < 3; op++)
            for (n = 0; n < 100; n++) begin
                a32 = $urandom; b32 = $urandom;
                z32 = sf_cmp32(op, a32, b32, ref_flags);
                frs1 = {32'hffff_ffff, a32};
                frs2 = {32'hffff_ffff, b32};
                issue(op_fp(7'b1010000, 0, op[2:0]), z32,
                      ref_flags[4:0], 1, 0);
                a64 = {$urandom, $urandom};
                b64 = {$urandom, $urandom};
                z32 = sf_cmp64(op, a64, b64, ref_flags);
                frs1 = a64; frs2 = b64;
                issue(op_fp(7'b1010001, 0, op[2:0]), z32,
                      ref_flags[4:0], 1, 0);
            end

        for (op = 0; op < 10; op++)
            for (rm = 0; rm < 5; rm++)
                for (n = 0; n < 20; n++) begin
                    a64 = {$urandom, $urandom};
                    converted = sf_convert(op, a64, rm, ref_flags);
                    frm = rm[2:0];
                    rs1_int = a64[31:0];
                    frs1 = (op <= 1 || op == 8)
                           ? {32'hffff_ffff, a64[31:0]} : a64;
                    case (op)
                        0, 1: instr = op_fp(7'b1100000, op[0], rm[2:0]);
                        2, 3: instr = op_fp(7'b1100001, op[0], rm[2:0]);
                        4, 5: instr = op_fp(7'b1101000, op[0], rm[2:0]);
                        6, 7: instr = op_fp(7'b1101001, op[0], rm[2:0]);
                        8: instr = op_fp(7'b0100001, 0, rm[2:0]);
                        default: instr = op_fp(7'b0100000, 1, rm[2:0]);
                    endcase
                    issue(instr, converted, ref_flags[4:0], op < 4, op >= 4);
                end

        $display("PASS: %0d expanded Berkeley SoftFloat comparisons", tests);
        $finish;
    end
endmodule
