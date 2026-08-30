`timescale 1ns/1ps

module tb_arch_units;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    reg [31:0] instr;
    wire [4:0] rs1, rs2, rd;
    wire [31:0] imm;
    wire [3:0] alu_op;
    wire [2:0] funct3;
    wire alu_src, mem_read, mem_write, reg_write, branch, jal, jalr;
    wire lui, auipc, uses_rs1, uses_rs2, illegal, fence, fence_i;
    wire muldiv, amo, fp_compute, fp_load, fp_store;
    wire fp_uses_rs1, fp_uses_rs2, fp_uses_rs3;
    wire [2:0] muldiv_op;
    wire [4:0] amo_op;
    wire csr_en, csr_imm, ecall, ebreak, mret, sret, sfence_vma, wfi;
    wire [1:0] csr_cmd;

    decoder dec (.*);

    reg [11:0] read_addr, commit_addr;
    reg read_write_intent, commit_valid, retire, trap_enter, csr_mret;
    reg [31:0] commit_data, trap_pc, trap_cause, trap_tval;
    reg fp_flags_valid, fp_dirty;
    reg [4:0] fp_flags;
    wire [31:0] read_data, trap_vector, return_pc;
    wire [2:0] frm_out;
    wire read_illegal;

    csr_file csr (
        .clk(clk), .rst_n(rst_n), .read_addr(read_addr),
        .read_write_intent(read_write_intent), .read_data(read_data),
        .read_illegal(read_illegal), .commit_valid(commit_valid),
        .commit_addr(commit_addr), .commit_data(commit_data), .retire(retire),
        .fp_flags_valid(fp_flags_valid), .fp_flags(fp_flags),
        .fp_dirty(fp_dirty),
        .irq_m_software(1'b0), .irq_m_timer(1'b0),
        .irq_m_external(1'b0), .irq_s_software(1'b0),
        .irq_s_timer(1'b0), .irq_s_external(1'b0), .nmi(1'b0),
        .trap_enter(trap_enter), .trap_pc(trap_pc), .trap_cause(trap_cause),
        .trap_tval(trap_tval), .mret(csr_mret), .sret(1'b0),
        .trap_vector(trap_vector),
        .return_pc(return_pc), .frm_out(frm_out)
    );

    task tick;
        begin @(posedge clk); #1; end
    endtask

    task expect_decode;
        input [31:0] value;
        input expected_illegal;
        begin
            instr = value;
            #1;
            if (illegal !== expected_illegal)
                $fatal(1, "decode legality mismatch for %h", value);
        end
    endtask

    task select_csr;
        input [11:0] address;
        input write_intent;
        begin
            read_addr = address;
            read_write_intent = write_intent;
            #1;
        end
    endtask

    task write_csr;
        input [11:0] address;
        input [31:0] value;
        begin
            commit_addr = address;
            commit_data = value;
            commit_valid = 1;
            tick();
            commit_valid = 0;
        end
    endtask

    reg [31:0] count_before;
    initial begin
        instr = 0;
        read_addr = 0;
        read_write_intent = 0;
        commit_valid = 0;
        commit_addr = 0;
        commit_data = 0;
        retire = 0;
        trap_enter = 0;
        trap_pc = 0;
        trap_cause = 0;
        trap_tval = 0;
        csr_mret = 0;
        fp_flags_valid = 0;
        fp_flags = 0;
        fp_dirty = 0;

        expect_decode(32'h0000_000f, 0); // FENCE
        expect_decode(32'h1050_0073, 0); // WFI
        expect_decode(32'h0000_100f, 0); // FENCE.I
        expect_decode(32'h0220_81b3, 0); // MUL x3,x1,x2
        expect_decode(32'h1000_a12f, 0); // LR.W x2,(x1)
        expect_decode(32'h0020_a1af, 0); // AMOADD.W x3,x2,(x1)
        expect_decode(32'h0031_20d3, 0); // FADD.S f1,f2,f3
        expect_decode(32'h0000_a087, 0); // FLW f1,0(x1)
        expect_decode(32'h0010_b027, 0); // FSD f1,0(x1)
        expect_decode(32'h0200_1013, 1); // reserved SLLI encoding
        expect_decode(32'h0400_0033, 1); // reserved R-type encoding
        expect_decode(32'h0000_2063, 1); // reserved branch funct3
        expect_decode(32'h0000_6103, 1); // reserved load funct3
        expect_decode(32'h0000_3023, 1); // reserved store funct3
        expect_decode(32'h0000_10e7, 1); // reserved JALR funct3
        expect_decode(32'h0000_0000, 1); // unknown opcode

        repeat (2) tick();
        rst_n = 1;
        tick();

        select_csr(12'h301, 0);
        if (read_illegal || read_data != 32'h4014_112d)
            $fatal(1, "MISA read mismatch");
        select_csr(12'h301, 1);
        if (!read_illegal) $fatal(1, "MISA write was not rejected");
        select_csr(12'h123, 0);
        if (!read_illegal) $fatal(1, "unknown CSR was not rejected");

        write_csr(12'h003, 32'h0000_0063);
        select_csr(12'h003, 0);
        if (read_illegal || read_data[7:0] != 8'h63 || frm_out != 3)
            $fatal(1, "FCSR write mismatch");
        fp_flags = 5'b10100;
        fp_flags_valid = 1;
        tick();
        fp_flags_valid = 0;
        select_csr(12'h001, 0);
        if (read_data[4:0] != 5'b10111) $fatal(1, "fflags accrue mismatch");

        write_csr(12'h305, 32'h0000_0123);
        if (trap_vector != 32'h0000_0120) $fatal(1, "mtvec WARL mismatch");
        write_csr(12'h341, 32'h0000_0457);
        if (return_pc != 32'h0000_0456) $fatal(1, "mepc WARL mismatch");

        write_csr(12'h300, 32'h0000_0008);
        trap_pc = 32'h0000_0123;
        trap_cause = 11;
        trap_tval = 32'hdead_beef;
        trap_enter = 1;
        tick();
        trap_enter = 0;
        select_csr(12'h300, 0);
        if (read_data[7] != 1 || read_data[3] != 0)
            $fatal(1, "mstatus trap transition mismatch");
        select_csr(12'h341, 0);
        if (read_data != 32'h122) $fatal(1, "trap mepc mismatch");
        select_csr(12'h342, 0);
        if (read_data != 11) $fatal(1, "trap mcause mismatch");
        select_csr(12'h343, 0);
        if (read_data != 32'hdead_beef) $fatal(1, "trap mtval mismatch");
        csr_mret = 1;
        tick();
        csr_mret = 0;
        select_csr(12'h300, 0);
        if (read_data[7] != 1 || read_data[3] != 1)
            $fatal(1, "mstatus MRET transition mismatch");

        select_csr(12'hb00, 0);
        count_before = read_data;
        repeat (3) tick();
        select_csr(12'hb00, 0);
        if (read_data != count_before + 3) $fatal(1, "mcycle mismatch");
        write_csr(12'h320, 1);
        select_csr(12'hb00, 0);
        count_before = read_data;
        repeat (3) tick();
        select_csr(12'hb00, 0);
        if (read_data != count_before) $fatal(1, "mcycle inhibit mismatch");

        write_csr(12'h320, 0);
        select_csr(12'hb02, 0);
        count_before = read_data;
        retire = 1;
        repeat (2) tick();
        retire = 0;
        select_csr(12'hb02, 0);
        if (read_data != count_before + 2) $fatal(1, "minstret mismatch");
        write_csr(12'h320, 4);
        select_csr(12'hb02, 0);
        count_before = read_data;
        retire = 1;
        repeat (2) tick();
        retire = 0;
        select_csr(12'hb02, 0);
        if (read_data != count_before) $fatal(1, "minstret inhibit mismatch");

        $display("PASS: decoder and machine-CSR signoff regression complete");
        $finish;
    end
endmodule
