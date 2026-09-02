(* techmap_celltype = "P_CHI2_LUT3" *)
module _equivalence_lut3 #(
    parameter [7:0] INIT = 8'b0
) (
    input wire a,
    input wire b,
    input wire c,
    output wire y
);
    assign y = INIT[{c, b, a}];
endmodule
