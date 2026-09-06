`timescale 1ns/1ps

module tb_extended_units;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg [15:0] compressed;
    wire [31:0] instruction;
    wire compressed_illegal;
    rvc_decompressor rvc (
        .compressed(compressed), .instruction(instruction),
        .illegal(compressed_illegal)
    );

    reg mul_start = 0, mul_flush = 0;
    reg [2:0] mul_op;
    reg [31:0] mul_a, mul_b;
    wire mul_ready, mul_busy, mul_done;
    wire [31:0] mul_result;
    muldiv_unit muldiv (
        .clk(clk), .rst_n(rst_n), .start(mul_start), .flush(mul_flush),
        .op(mul_op), .a(mul_a), .b(mul_b), .ready(mul_ready),
        .busy(mul_busy), .done(mul_done), .result(mul_result)
    );

    task expect_rvc;
        input [15:0] value;
        input [31:0] expected;
        begin
            compressed = value;
            #1;
            if (compressed_illegal || instruction !== expected)
                $fatal(1, "RVC mismatch %h -> %h", value, instruction);
        end
    endtask

    task expect_muldiv;
        input [2:0] operation;
        input [31:0] a;
        input [31:0] b;
        input [31:0] expected;
        begin
            while (!mul_ready) @(posedge clk);
            mul_op = operation;
            mul_a = a;
            mul_b = b;
            mul_start = 1;
            @(posedge clk);
            #1 mul_start = 0;
            while (!mul_done) begin @(posedge clk); #1; end
            if (mul_result !== expected)
                $fatal(1, "M mismatch op=%b a=%h b=%h got=%h pending=%h sa=%h sb=%h",
                       operation, a, b, mul_result, muldiv.pending_result,
                       muldiv.signed_a, muldiv.signed_b);
        end
    endtask

    initial begin
        compressed = 0;
        mul_op = 0;
        mul_a = 0;
        mul_b = 0;

        expect_rvc(16'h0001, 32'h0000_0013); // C.NOP
        expect_rvc(16'h0085, 32'h0010_8093); // C.ADDI x1, 1
        expect_rvc(16'h517d, 32'hfff0_0113); // C.LI x2, -1
        expect_rvc(16'h8082, 32'h0000_8067); // C.JR x1
        expect_rvc(16'h9082, 32'h0000_80e7); // C.JALR x1
        expect_rvc(16'h9002, 32'h0010_0073); // C.EBREAK
        expect_rvc(16'h829a, 32'h0060_02b3); // C.MV x5, x6
        expect_rvc(16'h929a, 32'h0062_82b3); // C.ADD x5, x6
        expect_rvc(16'h4292, 32'h0041_2283); // C.LWSP x5, 4
        expect_rvc(16'hc216, 32'h0051_2223); // C.SWSP x5, 4
        expect_rvc(16'h0040, 32'h0041_0413); // C.ADDI4SPN x8, 4
        compressed = 16'h0000;
        #1;
        if (!compressed_illegal) $fatal(1, "reserved C.ADDI4SPN accepted");

        repeat (2) @(posedge clk);
        rst_n = 1;
        expect_muldiv(3'b000, 32'hffff_fffe, 3, 32'hffff_fffa); // MUL
        expect_muldiv(3'b001, 32'h8000_0000, 2, 32'hffff_ffff); // MULH
        expect_muldiv(3'b010, 32'hffff_ffff, 2, 32'hffff_ffff); // MULHSU
        expect_muldiv(3'b011, 32'hffff_ffff, 2, 1); // MULHU
        expect_muldiv(3'b100, 32'h8000_0000, 32'hffff_ffff, 32'h8000_0000);
        expect_muldiv(3'b101, 7, 0, 32'hffff_ffff);
        expect_muldiv(3'b110, 32'hffff_fff9, 3, 32'hffff_ffff);
        expect_muldiv(3'b111, 7, 3, 1);

        $display("PASS: RV32 M/C unit regression complete");
        $finish;
    end
endmodule
