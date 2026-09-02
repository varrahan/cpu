`timescale 1ps/1ps

// Logical models for photonic standard-cell contracts. Physical loss,
// wavelength, rate, and delay live in photonic/cells.json rather than RTL.
module P_CHI2_LUT3 #(
    parameter [7:0] INIT = 8'b0
) (
    input  wire a,
    input  wire b,
    input  wire c,
    output wire y
);
    function automatic evaluate;
        input aa;
        input bb;
        input cc;
        integer index;
        reg first;
        reg candidate;
        begin
            first = 1'b1;
            candidate = 1'bx;
            for (index = 0; index < 8; index = index + 1)
                if (((aa !== 1'b0 && aa !== 1'b1) || aa === index[0]) &&
                    ((bb !== 1'b0 && bb !== 1'b1) || bb === index[1]) &&
                    ((cc !== 1'b0 && cc !== 1'b1) || cc === index[2])) begin
                    if (first) begin
                        candidate = INIT[index];
                        first = 1'b0;
                    end else if (candidate !== INIT[index]) begin
                        candidate = 1'bx;
                    end
                end
            evaluate = candidate;
        end
    endfunction

    assign y = evaluate(a, b, c);
endmodule

module P_TBIN_DFF (
    input  wire D,
    input  wire CLK,
    output reg  Q
);
    // Functional abstraction of an active-cavity time-bin state cell.
    always @(posedge CLK) Q <= D;
endmodule

module P_TBIN_DFFR (
    input  wire D,
    input  wire RESET,
    input  wire CLK,
    output reg  Q
);
    always @(posedge CLK or posedge RESET)
        if (RESET) Q <= 1'b0;
        else Q <= D;
endmodule

module P_SPLIT2 (
    input wire A,
    output wire Y0,
    output wire Y1
);
    assign Y0 = A;
    assign Y1 = A;
endmodule

module P_REGEN2R (
    input wire A,
    output wire Y
);
    assign Y = A;
endmodule

module photonic_encode_word (
    input  wire [31:0] data,
    input  wire        valid,
    output wire [31:0] true_rail,
    output wire [31:0] false_rail,
    output wire        encoding_fault
);
    assign true_rail = valid ? data : 0;
    assign false_rail = valid ? ~data : 0;
    assign encoding_fault = |(true_rail & false_rail);
endmodule

module photonic_decode_word (
    input  wire [31:0] true_rail,
    input  wire [31:0] false_rail,
    output wire [31:0] data,
    output wire        valid,
    output wire        encoding_fault
);
    assign data = true_rail;
    assign valid = &(true_rail ^ false_rail);
    assign encoding_fault = |(true_rail & false_rail);
endmodule
