module muldiv_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        flush,
    input  logic [2:0]  op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        ready,
    output logic        busy,
    output logic         done,
    output logic  [31:0] result
);
    logic [2:0] cycles;
    logic [31:0] pending_result;
    logic signed [31:0] signed_a;
    logic signed [31:0] signed_b;
    logic signed [63:0] signed_product;
    logic signed [64:0] signed_unsigned_product;
    logic [31:0] magnitude_a;
    logic [31:0] magnitude_b;
    logic [31:0] unsigned_quotient;
    logic [31:0] unsigned_remainder;

    assign ready = cycles == 0;
    assign busy = cycles != 0;

    always_comb begin
        signed_a = a;
        signed_b = b;
        signed_product = signed_a * signed_b;
        signed_unsigned_product = signed_a * $signed({1'b0, b});
        magnitude_a = a[31] ? (~a + 1'b1) : a;
        magnitude_b = b[31] ? (~b + 1'b1) : b;
        unsigned_quotient = magnitude_b ? magnitude_a / magnitude_b : 0;
        unsigned_remainder = magnitude_b ? magnitude_a % magnitude_b : magnitude_a;
        case (op)
            3'b000: pending_result = a * b;
            3'b001: pending_result = signed_product[63:32];
            3'b010: pending_result = signed_unsigned_product[63:32];
            3'b011: pending_result = ({32'b0, a} * {32'b0, b}) >> 32;
            3'b100: pending_result = (b == 0) ? 32'hffff_ffff :
                                            (a == 32'h8000_0000 && b == 32'hffff_ffff)
                                            ? 32'h8000_0000 :
                                            (a[31] ^ b[31]) ? (~unsigned_quotient + 1'b1)
                                                            : unsigned_quotient;
            3'b101: pending_result = (b == 0) ? 32'hffff_ffff : a / b;
            3'b110: pending_result = (b == 0) ? a :
                                            (a == 32'h8000_0000 && b == 32'hffff_ffff)
                                            ? 0 : a[31] ? (~unsigned_remainder + 1'b1)
                                                        : unsigned_remainder;
            default: pending_result = (b == 0) ? a : a % b;
        endcase
    end

    always_ff @(posedge clk) begin
        done <= 0;
        if (!rst_n || flush) begin
            cycles <= 0;
            result <= 0;
        end else if (start && ready) begin
            result <= pending_result;
            cycles <= 3;
        end else if (cycles != 0) begin
            cycles <= cycles - 1;
            if (cycles == 1) done <= 1;
        end
    end
endmodule
