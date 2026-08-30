`timescale 1ps/1ps

module tb_photonic_cells;
    reg a, b, c, clk, d, reset, word_valid;
    reg [31:0] word;
    wire parity, q, q_reset;
    wire [31:0] true_rail, false_rail, decoded;
    wire encoded_fault, decoded_valid, decoded_fault;

    task clock_and_check;
        input value;
        begin
            d = value;
            #4 clk = 1;
            #1;
            if (q !== value) $fatal(1, "100 GHz state-cell mismatch");
            #4 clk = 0;
            #1;
        end
    endtask

    P_CHI2_LUT3 #(.INIT(8'h96)) parity_lut
        (.a(a), .b(b), .c(c), .y(parity));
    P_TBIN_DFF latch (.D(d), .CLK(clk), .Q(q));
    P_TBIN_DFFR reset_latch
        (.D(d), .RESET(reset), .CLK(clk), .Q(q_reset));
    photonic_encode_word encoder (
        .data(word), .valid(word_valid), .true_rail(true_rail),
        .false_rail(false_rail), .encoding_fault(encoded_fault)
    );
    photonic_decode_word decoder (
        .true_rail(true_rail), .false_rail(false_rail), .data(decoded),
        .valid(decoded_valid), .encoding_fault(decoded_fault)
    );

    integer i;
    initial begin
        clk = 0;
        d = 0;
        reset = 0;
        word = 32'ha5a5_5a5a;
        word_valid = 1;
        for (i = 0; i < 8; i = i + 1) begin
            {c, b, a} = i[2:0];
            #1;
            if (parity !== ^i[2:0]) $fatal(1, "LUT3 mismatch at %0d", i);
        end
        if (!decoded_valid || decoded_fault || encoded_fault || decoded != word)
            $fatal(1, "dual-rail encode/decode mismatch");
        word_valid = 0;
        #1;
        if (decoded_valid || true_rail != 0 || false_rail != 0)
            $fatal(1, "invalid dual-rail word mismatch");
        clock_and_check(1);
        if (q_reset !== 1) $fatal(1, "predicate-reset latch capture failed");
        reset = 1; #1;
        if (q_reset !== 0) $fatal(1, "predicate-reset latch clear failed");
        reset = 0;
        clock_and_check(0);
        clock_and_check(1);
        clock_and_check(0);
        $display("PASS: photonic logical-cell regression complete");
        $finish;
    end
endmodule
