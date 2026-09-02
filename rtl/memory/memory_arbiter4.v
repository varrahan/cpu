module memory_arbiter4 (
    input wire clk, input wire rst_n,
    input wire m0_req_valid, output wire m0_req_ready,
    input wire m0_req_write, input wire [31:0] m0_req_addr,
    input wire [31:0] m0_req_wdata, input wire [3:0] m0_req_be,
    input wire m0_req_amo, input wire [4:0] m0_req_amo_op,
    output wire m0_rsp_valid, input wire m0_rsp_ready,
    output wire [31:0] m0_rsp_rdata, output wire m0_rsp_error,
    input wire m1_req_valid, output wire m1_req_ready,
    input wire m1_req_write, input wire [31:0] m1_req_addr,
    input wire [31:0] m1_req_wdata, input wire [3:0] m1_req_be,
    input wire m1_req_amo, input wire [4:0] m1_req_amo_op,
    output wire m1_rsp_valid, input wire m1_rsp_ready,
    output wire [31:0] m1_rsp_rdata, output wire m1_rsp_error,
    input wire m2_req_valid, output wire m2_req_ready,
    input wire m2_req_write, input wire [31:0] m2_req_addr,
    input wire [31:0] m2_req_wdata, input wire [3:0] m2_req_be,
    input wire m2_req_amo, input wire [4:0] m2_req_amo_op,
    output wire m2_rsp_valid, input wire m2_rsp_ready,
    output wire [31:0] m2_rsp_rdata, output wire m2_rsp_error,
    input wire m3_req_valid, output wire m3_req_ready,
    input wire m3_req_write, input wire [31:0] m3_req_addr,
    input wire [31:0] m3_req_wdata, input wire [3:0] m3_req_be,
    input wire m3_req_amo, input wire [4:0] m3_req_amo_op,
    output wire m3_rsp_valid, input wire m3_rsp_ready,
    output wire [31:0] m3_rsp_rdata, output wire m3_rsp_error,
    output wire ext_req_valid, input wire ext_req_ready,
    output reg ext_req_write, output reg [31:0] ext_req_addr,
    output reg [31:0] ext_req_wdata, output reg [3:0] ext_req_be,
    output reg ext_req_amo, output reg [4:0] ext_req_amo_op,
    input wire ext_rsp_valid, output wire ext_rsp_ready,
    input wire [31:0] ext_rsp_rdata, input wire ext_rsp_error
);
    reg busy;
    reg [1:0] owner;
    reg [1:0] selected;
    reg selected_valid;

    always @(*) begin
        selected = 0;
        selected_valid = !busy;
        if (m0_req_valid) selected = 0;
        else if (m1_req_valid) selected = 1;
        else if (m2_req_valid) selected = 2;
        else if (m3_req_valid) selected = 3;
        else selected_valid = 0;
        case (selected)
            0: begin ext_req_write = m0_req_write; ext_req_addr = m0_req_addr;
                ext_req_wdata = m0_req_wdata; ext_req_be = m0_req_be;
                ext_req_amo = m0_req_amo; ext_req_amo_op = m0_req_amo_op; end
            1: begin ext_req_write = m1_req_write; ext_req_addr = m1_req_addr;
                ext_req_wdata = m1_req_wdata; ext_req_be = m1_req_be;
                ext_req_amo = m1_req_amo; ext_req_amo_op = m1_req_amo_op; end
            2: begin ext_req_write = m2_req_write; ext_req_addr = m2_req_addr;
                ext_req_wdata = m2_req_wdata; ext_req_be = m2_req_be;
                ext_req_amo = m2_req_amo; ext_req_amo_op = m2_req_amo_op; end
            default: begin ext_req_write = m3_req_write;
                ext_req_addr = m3_req_addr; ext_req_wdata = m3_req_wdata;
                ext_req_be = m3_req_be; ext_req_amo = m3_req_amo;
                ext_req_amo_op = m3_req_amo_op; end
        endcase
    end

    assign ext_req_valid = selected_valid;
    assign m0_req_ready = selected_valid && selected == 0 && ext_req_ready;
    assign m1_req_ready = selected_valid && selected == 1 && ext_req_ready;
    assign m2_req_ready = selected_valid && selected == 2 && ext_req_ready;
    assign m3_req_ready = selected_valid && selected == 3 && ext_req_ready;
    assign m0_rsp_valid = busy && owner == 0 && ext_rsp_valid;
    assign m1_rsp_valid = busy && owner == 1 && ext_rsp_valid;
    assign m2_rsp_valid = busy && owner == 2 && ext_rsp_valid;
    assign m3_rsp_valid = busy && owner == 3 && ext_rsp_valid;
    assign m0_rsp_rdata = ext_rsp_rdata;
    assign m1_rsp_rdata = ext_rsp_rdata;
    assign m2_rsp_rdata = ext_rsp_rdata;
    assign m3_rsp_rdata = ext_rsp_rdata;
    assign m0_rsp_error = ext_rsp_error;
    assign m1_rsp_error = ext_rsp_error;
    assign m2_rsp_error = ext_rsp_error;
    assign m3_rsp_error = ext_rsp_error;
    assign ext_rsp_ready = owner == 0 ? m0_rsp_ready :
                           owner == 1 ? m1_rsp_ready :
                           owner == 2 ? m2_rsp_ready : m3_rsp_ready;

    always @(posedge clk) begin
        if (!rst_n) begin busy <= 0; owner <= 0; end
        else begin
            if (!busy && ext_req_valid && ext_req_ready) begin
                busy <= 1;
                owner <= selected;
            end
            if (busy && ext_rsp_valid && ext_rsp_ready) busy <= 0;
        end
    end
`ifdef FORMAL
    reg formal_past_valid = 0;
    initial assume(!rst_n);
    always @(posedge clk) begin
        formal_past_valid <= 1;
        if (formal_past_valid) assume(rst_n);
        if (formal_past_valid && rst_n) begin
            if ($past(ext_req_valid && !ext_req_ready)) begin
                assert(ext_req_valid);
                assert($stable({ext_req_write, ext_req_addr, ext_req_wdata,
                                ext_req_be, ext_req_amo, ext_req_amo_op}));
            end
            if (ext_req_write || ext_req_amo) assert(ext_req_valid);
        end
    end
`endif
endmodule
