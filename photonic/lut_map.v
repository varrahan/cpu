(* techmap_celltype = "$lut" *)
module _photonic_lut_map #(
    parameter WIDTH = 0,
    parameter [7:0] LUT = 0
) (
    input  wire [WIDTH-1:0] A,
    output wire             Y
);
    wire [2:0] A_PAD;
    assign A_PAD = A;

    generate
        if (WIDTH == 1) begin
            P_CHI2_LUT3 #(.INIT({6'b0, LUT[1:0]})) cell
                (.a(A_PAD[0]), .b(1'b0), .c(1'b0), .y(Y));
        end else if (WIDTH == 2) begin
            P_CHI2_LUT3 #(.INIT({4'b0, LUT[3:0]})) cell
                (.a(A_PAD[0]), .b(A_PAD[1]), .c(1'b0), .y(Y));
        end else begin
            P_CHI2_LUT3 #(.INIT(LUT)) cell
                (.a(A_PAD[0]), .b(A_PAD[1]), .c(A_PAD[2]), .y(Y));
        end
    endgenerate
endmodule
