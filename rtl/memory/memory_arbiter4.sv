module memory_arbiter4 (
    input logic clk, input logic rst_n,
    input logic m0_req_valid, output logic m0_req_ready,
    input logic m0_req_write, input logic [31:0] m0_req_addr,
    input logic [31:0] m0_req_wdata, input logic [3:0] m0_req_be,
    input logic m0_req_amo, input logic [4:0] m0_req_amo_op,
    output logic m0_rsp_valid, input logic m0_rsp_ready,
    output logic [31:0] m0_rsp_rdata, output logic m0_rsp_error,
    input logic m1_req_valid, output logic m1_req_ready,
    input logic m1_req_write, input logic [31:0] m1_req_addr,
    input logic [31:0] m1_req_wdata, input logic [3:0] m1_req_be,
    input logic m1_req_amo, input logic [4:0] m1_req_amo_op,
    output logic m1_rsp_valid, input logic m1_rsp_ready,
    output logic [31:0] m1_rsp_rdata, output logic m1_rsp_error,
    input logic m2_req_valid, output logic m2_req_ready,
    input logic m2_req_write, input logic [31:0] m2_req_addr,
    input logic [31:0] m2_req_wdata, input logic [3:0] m2_req_be,
    input logic m2_req_amo, input logic [4:0] m2_req_amo_op,
    output logic m2_rsp_valid, input logic m2_rsp_ready,
    output logic [31:0] m2_rsp_rdata, output logic m2_rsp_error,
    input logic m3_req_valid, output logic m3_req_ready,
    input logic m3_req_write, input logic [31:0] m3_req_addr,
    input logic [31:0] m3_req_wdata, input logic [3:0] m3_req_be,
    input logic m3_req_amo, input logic [4:0] m3_req_amo_op,
    output logic m3_rsp_valid, input logic m3_rsp_ready,
    output logic [31:0] m3_rsp_rdata, output logic m3_rsp_error,
    output logic ext_req_valid, input logic ext_req_ready,
    output logic ext_req_write, output logic [31:0] ext_req_addr,
    output logic [31:0] ext_req_wdata, output logic [3:0] ext_req_be,
    output logic ext_req_amo, output logic [4:0] ext_req_amo_op,
    input logic ext_rsp_valid, output logic ext_rsp_ready,
    input logic [31:0] ext_rsp_rdata, input logic ext_rsp_error
);
    logic busy;
    logic [1:0] owner;
    logic hold;
    logic [1:0] hold_owner;
    logic [1:0] selected;
    logic selected_valid;

    always_comb begin
        selected = 0;
        selected_valid = 0;
        if (!busy && hold) begin
            selected = hold_owner;
            case (hold_owner)
                0: selected_valid = m0_req_valid;
                1: selected_valid = m1_req_valid;
                2: selected_valid = m2_req_valid;
                default: selected_valid = m3_req_valid;
            endcase
        end else if (!busy) begin
            if (m0_req_valid) begin selected = 0; selected_valid = 1; end
            else if (m1_req_valid) begin selected = 1; selected_valid = 1; end
            else if (m2_req_valid) begin selected = 2; selected_valid = 1; end
            else if (m3_req_valid) begin selected = 3; selected_valid = 1; end
        end
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
        if (!selected_valid) begin
            ext_req_write = 0;
            ext_req_addr = 0;
            ext_req_wdata = 0;
            ext_req_be = 0;
            ext_req_amo = 0;
            ext_req_amo_op = 0;
        end
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

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            busy <= 0;
            owner <= 0;
            hold <= 0;
            hold_owner <= 0;
        end
        else begin
            if (!busy && ext_req_valid && ext_req_ready) begin
                busy <= 1;
                owner <= selected;
                hold <= 0;
            end else if (!busy && ext_req_valid) begin
                hold <= 1;
                hold_owner <= selected;
            end
            if (busy && ext_rsp_valid && ext_rsp_ready) busy <= 0;
        end
    end
`ifdef FORMAL
    logic formal_past_valid = 0;
    initial assume(!rst_n);
    always_ff @(posedge clk) begin
        formal_past_valid <= 1;
        if (formal_past_valid) assume(rst_n);
        if (formal_past_valid && rst_n) begin
            if ($past(rst_n && m0_req_valid && !m0_req_ready)) begin
                assume(m0_req_valid);
                assume($stable({m0_req_write, m0_req_addr, m0_req_wdata,
                                m0_req_be, m0_req_amo, m0_req_amo_op}));
            end
            if ($past(rst_n && m1_req_valid && !m1_req_ready)) begin
                assume(m1_req_valid);
                assume($stable({m1_req_write, m1_req_addr, m1_req_wdata,
                                m1_req_be, m1_req_amo, m1_req_amo_op}));
            end
            if ($past(rst_n && m2_req_valid && !m2_req_ready)) begin
                assume(m2_req_valid);
                assume($stable({m2_req_write, m2_req_addr, m2_req_wdata,
                                m2_req_be, m2_req_amo, m2_req_amo_op}));
            end
            if ($past(rst_n && m3_req_valid && !m3_req_ready)) begin
                assume(m3_req_valid);
                assume($stable({m3_req_write, m3_req_addr, m3_req_wdata,
                                m3_req_be, m3_req_amo, m3_req_amo_op}));
            end
            if ($past(rst_n && ext_req_valid && !ext_req_ready)) begin
                assert(ext_req_valid);
                assert($stable({ext_req_write, ext_req_addr, ext_req_wdata,
                                ext_req_be, ext_req_amo, ext_req_amo_op}));
            end
            if (ext_req_write || ext_req_amo) assert(ext_req_valid);
        end
    end
`endif
endmodule
