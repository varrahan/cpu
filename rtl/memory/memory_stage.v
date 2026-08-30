module memory_stage (
    input  wire [1:0]  addr,
    input  wire [31:0] wdata,
    input  wire [2:0]  funct3,
    input  wire [31:0] word_rdata,
    output reg  [31:0] store_wdata,
    output reg  [3:0]  store_be,
    output reg  [31:0] load_rdata,
    output reg         misaligned
);
    reg [15:0] shifted;

    always @(*) begin
        store_wdata = 0;
        store_be = 0;
        load_rdata = 0;
        misaligned = 0;
        shifted = word_rdata >> ({30'b0, addr} * 8);

        case (funct3)
            3'b000: begin
                store_be = 4'b0001 << addr;
                store_wdata = {24'b0, wdata[7:0]} <<
                              ({30'b0, addr} * 8);
                load_rdata = {{24{shifted[7]}}, shifted[7:0]};
            end
            3'b001: begin
                misaligned = addr[0];
                store_be = 4'b0011 << {addr[1], 1'b0};
                store_wdata = {16'b0, wdata[15:0]} <<
                              ({30'b0, addr} * 8);
                load_rdata = {{16{shifted[15]}}, shifted[15:0]};
            end
            3'b010: begin
                misaligned = |addr;
                store_be = 4'b1111;
                store_wdata = wdata;
                load_rdata = word_rdata;
            end
            3'b100: load_rdata = {24'b0, shifted[7:0]};
            3'b101: begin
                misaligned = addr[0];
                load_rdata = {16'b0, shifted[15:0]};
            end
            default: misaligned = 1;
        endcase
    end
endmodule
