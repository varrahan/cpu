`timescale 1ns/1ps

module tb_fpu;
    logic clk = 0;
    logic rst_n = 0;
    logic start = 0;
    logic flush = 0;
    logic [31:0] instr = 0;
    logic [31:0] rs1_int = 0;
    logic [63:0] frs1 = 0, frs2 = 0, frs3 = 0;
    logic [2:0] frm = 0;
    wire ready, busy, done, illegal, result_to_int, write_fp;
    wire [63:0] result;
    wire [4:0] flags;

    always #5 clk = ~clk;

    fpu_wrapper dut (.*);

    function automatic [31:0] op_fp;
        input [6:0] funct7;
        input [4:0] rs2;
        input [2:0] funct3;
        begin op_fp = {funct7, rs2, 5'd1, funct3, 5'd3, 7'h53}; end
    endfunction

    task automatic issue_and_expect;
        input [31:0] operation;
        input [63:0] expected_result;
        input [4:0] expected_flags;
        input expected_to_int;
        input expected_write_fp;
        integer timeout;
        begin
            while (!ready) begin @(posedge clk); #1; end
            instr = operation;
            start = 1;
            @(posedge clk);
            #1;
            start = 0;
            timeout = 0;
            while (!done && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (!done) $fatal(1, "FPU timeout for %h", operation);
            if (illegal) $fatal(1, "legal FPU instruction rejected: %h", operation);
            if (result !== expected_result || flags !== expected_flags ||
                result_to_int !== expected_to_int || write_fp !== expected_write_fp)
                $fatal(1, "FPU mismatch insn=%h result=%h flags=%b int=%b fp=%b",
                       operation, result, flags, result_to_int, write_fp);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1;

        frs1 = 64'hffff_ffff_3fc0_0000; // 1.5f
        frs2 = 64'hffff_ffff_4010_0000; // 2.25f
        issue_and_expect(op_fp(7'b0000000, 0, 3'b000),
                         64'hffff_ffff_4070_0000, 0, 0, 1); // FADD.S 3.75

        frs1 = 64'h3ff8_0000_0000_0000; // 1.5
        frs2 = 64'h4002_0000_0000_0000; // 2.25
        issue_and_expect(op_fp(7'b0000001, 0, 3'b000),
                         64'h400e_0000_0000_0000, 0, 0, 1); // FADD.D 3.75

        frs1 = 64'hffff_ffff_3f80_0000; // 1.0f
        frs2 = 64'hffff_ffff_0000_0000; // 0.0f
        issue_and_expect(op_fp(7'b0001100, 0, 3'b000),
                         64'hffff_ffff_7f80_0000, 5'b01000, 0, 1); // FDIV.S

        frs1 = 64'hffff_ffff_4070_0000; // 3.75f
        issue_and_expect(op_fp(7'b1100000, 0, 3'b000),
                         64'h0000_0000_0000_0004, 5'b00001, 1, 0); // FCVT.W.S

        frs1 = 64'hfff0_0000_0000_0000; // -infinity
        issue_and_expect(op_fp(7'b1110001, 0, 3'b001),
                         64'h0000_0000_0000_0001, 0, 1, 0); // FCLASS.D

        rs1_int = 32'hdead_beef;
        issue_and_expect(op_fp(7'b1111000, 0, 3'b000),
                         64'hffff_ffff_dead_beef, 0, 0, 1); // FMV.W.X

        instr = op_fp(7'b0000000, 0, 3'b101);
        #1;
        if (!illegal) $fatal(1, "reserved rounding mode accepted");

        $display("PASS: RV32 F/D execution regression complete");
        $finish;
    end
endmodule
