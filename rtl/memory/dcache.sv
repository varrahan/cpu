module dcache (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        cpu_valid,
    input  logic        cpu_write,
    input  logic        cpu_double,
    input  logic        cpu_cacheable,
    input  logic        cpu_amo,
    input  logic [4:0]  cpu_amo_op,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    input  logic [63:0] cpu_wdata64,
    input  logic [3:0]  cpu_be,
    output logic [31:0] cpu_rdata,
    output logic [63:0] cpu_rdata64,
    output logic        cpu_ready,
    output logic        cpu_error,
    input  logic        reservation_invalidate,
    // Second cache-hit read port; misses use the existing CPU port.
    input  logic [31:0] parallel_addr,
    output logic [63:0] parallel_rdata,
    output logic parallel_hit,

    output logic        mem_req_valid,
    input  logic        mem_req_allow,
    input  logic        mem_req_ready,
    output logic        mem_req_write,
    output logic [31:0] mem_req_addr,
    output logic [31:0] mem_req_wdata,
    output logic [3:0]  mem_req_be,
    output logic        mem_req_amo,
    output logic [4:0]  mem_req_amo_op,
    input  logic        mem_rsp_valid,
    output logic        mem_rsp_ready,
    input  logic [31:0] mem_rsp_rdata,
    input  logic        mem_rsp_error
);
    localparam IDLE = 4'd0, LOAD_REQ = 4'd1, LOAD_WAIT = 4'd2,
               STORE_REQ = 4'd3, STORE_WAIT = 4'd4, COMPLETE = 4'd5,
               AMO_REQ = 4'd6, AMO_WAIT = 4'd7;

    logic [3:0] state;
    logic [15:0] valid;
    logic [31:0] fill_base;
    logic [3:0]  fill_index;
    logic [23:0] fill_tag;
    logic [1:0]  fill_word;
    logic [3:0]  fill_required_mask;
    logic        fill_cacheable;
    logic        fill_double;
    logic [31:0] store_addr;
    logic [31:0] store_wdata;
    logic [3:0]  store_be;
    logic [3:0]  store_index;
    logic [1:0]  store_word;
    logic        store_hit;
    logic        store_double;
    logic        store_second;
    logic [31:0] amo_addr;
    logic [31:0] amo_wdata;
    logic [4:0]  amo_op;
    logic        amo_sc_failed;
    logic        reservation_valid;
    logic [31:2] reservation_addr;
    logic [31:0] complete_rdata;
    logic [31:0] complete_rdata_high;
    logic        complete_error;
    wire [3:0] cpu_index = cpu_addr[7:4];
    wire [1:0] cpu_word  = cpu_addr[3:2];
    wire [47:0] tag_rdata;
    wire [127:0] data_rdata;
    wire       hit = cpu_cacheable && valid[cpu_index] &&
                     tag_rdata[23:0] == cpu_addr[31:8];
    wire load_zero_write = state == LOAD_REQ && !mem_req_allow &&
                           !fill_required_mask[fill_word];
    wire load_data_write = state == LOAD_WAIT && fill_cacheable &&
                           mem_rsp_valid && !mem_rsp_error;
    wire store_data_write = state == STORE_WAIT && mem_rsp_valid &&
                            !mem_rsp_error && store_hit;
    wire fill_array_write = load_zero_write || load_data_write;
    wire array_write = fill_array_write || store_data_write;

    wire [7:0] tag_addresses = {parallel_addr[7:4], cpu_index};
    wire [23:0] data_addresses = {parallel_addr[7:2]+6'd1, parallel_addr[7:2],
                                  cpu_index, cpu_word+1'b1, cpu_index, cpu_word};
    async_memory #(.DATA_WIDTH(24), .ADDR_WIDTH(4), .READ_PORTS(2)) u_tags (
        .clk(clk), .rst_n(rst_n), .we(fill_array_write && fill_word == 3),
        .waddr(fill_index), .wdata(fill_tag), .wbe(1'b1),
        .raddr(tag_addresses), .rdata(tag_rdata)
    );
    async_memory #(
        .DATA_WIDTH(32), .ADDR_WIDTH(6), .READ_PORTS(4), .BYTE_LANES(4)
    ) u_data (
        .clk(clk), .rst_n(rst_n), .we(array_write),
        .waddr(store_data_write ? {store_index, store_word}
                                : {fill_index, fill_word}),
        .wdata(store_data_write ? store_wdata
                                : load_zero_write ? 32'b0 : mem_rsp_rdata),
        .wbe(store_data_write ? store_be : 4'b1111),
        .raddr(data_addresses),
        .rdata(data_rdata)
    );

    assign parallel_hit = state == IDLE && valid[parallel_addr[7:4]] &&
                          tag_rdata[47:24] == parallel_addr[31:8];
    assign parallel_rdata = data_rdata[127:64];

    assign cpu_rdata = state == COMPLETE ? complete_rdata
                                         : data_rdata[31:0];
    assign cpu_rdata64 = state == COMPLETE && !fill_cacheable
                         ? {complete_rdata_high, complete_rdata} : data_rdata[63:0];
    assign cpu_ready = cpu_valid &&
                       ((state == IDLE && !cpu_write && !cpu_amo && hit) ||
                        state == COMPLETE);
    assign cpu_error = state == COMPLETE && complete_error;

    assign mem_req_valid = (state == LOAD_REQ || state == STORE_REQ ||
                            state == AMO_REQ) && mem_req_allow;
    assign mem_req_write = state == STORE_REQ;
    assign mem_req_addr  = state == AMO_REQ ? amo_addr :
                           state == STORE_REQ ? store_addr
                           : fill_base + {28'b0, fill_word, 2'b00};
    assign mem_req_wdata = state == AMO_REQ ? amo_wdata : store_wdata;
    assign mem_req_be    = state == AMO_REQ ? 4'b1111 : store_be;
    assign mem_req_amo   = state == AMO_REQ && !amo_sc_failed;
    assign mem_req_amo_op = amo_op;
    assign mem_rsp_ready = state == LOAD_WAIT || state == STORE_WAIT ||
                           state == AMO_WAIT;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            valid <= 0;
            fill_base <= 0;
            fill_index <= 0;
            fill_tag <= 0;
            fill_word <= 0;
            fill_required_mask <= 0;
            fill_cacheable <= 0;
            fill_double <= 0;
            store_addr <= 0;
            store_wdata <= 0;
            store_be <= 0;
            store_index <= 0;
            store_word <= 0;
            store_hit <= 0;
            store_double <= 0;
            store_second <= 0;
            amo_addr <= 0;
            amo_wdata <= 0;
            amo_op <= 0;
            amo_sc_failed <= 0;
            reservation_valid <= 0;
            reservation_addr <= 0;
            complete_rdata <= 0;
            complete_rdata_high <= 0;
            complete_error <= 0;
        end else begin
            if (reservation_invalidate) reservation_valid <= 0;
            case (state)
                IDLE: begin
                    complete_error <= 0;
                    if (cpu_valid && cpu_amo) begin
                        if (cpu_amo_op == 5'b00011 &&
                            (!reservation_valid ||
                             reservation_addr != cpu_addr[31:2])) begin
                            amo_addr <= cpu_addr;
                            amo_wdata <= cpu_wdata;
                            amo_op <= cpu_amo_op;
                            amo_sc_failed <= 1;
                            reservation_valid <= 0;
                            state <= AMO_REQ;
                        end else begin
                            amo_addr <= cpu_addr;
                            amo_wdata <= cpu_wdata;
                            amo_op <= cpu_amo_op;
                            amo_sc_failed <= 0;
                            valid[cpu_index] <= 0;
                            if (cpu_amo_op != 5'b00010)
                                reservation_valid <= 0;
                            state <= AMO_REQ;
                        end
                    end else if (cpu_valid && cpu_write) begin
                        store_addr  <= cpu_addr;
                        store_wdata <= cpu_double ? cpu_wdata64[31:0]
                                                  : cpu_wdata;
                        store_be    <= cpu_double ? 4'b1111 : cpu_be;
                        store_index <= cpu_index;
                        store_word  <= cpu_word;
                        store_hit   <= hit;
                        store_double <= cpu_double;
                        store_second <= 0;
                        reservation_valid <= 0;
                        state <= STORE_REQ;
                    end else if (cpu_valid && !hit) begin
                        fill_base  <= cpu_cacheable
                                      ? {cpu_addr[31:4], 4'b0}
                                      : {cpu_addr[31:2], 2'b0};
                        fill_index <= cpu_index;
                        fill_tag   <= cpu_addr[31:8];
                        fill_word  <= 0;
                        fill_required_mask <= cpu_cacheable
                            ? (4'b0001 << cpu_word) |
                              (cpu_double ? (4'b0010 << cpu_word) : 0)
                            : (cpu_double ? 4'b0011 : 4'b0001);
                        fill_cacheable <= cpu_cacheable;
                        fill_double <= cpu_double;
                        valid[cpu_index] <= 0;
                        state <= LOAD_REQ;
                    end
                end
                LOAD_REQ: if (!mem_req_allow) begin
                    if (fill_required_mask[fill_word]) begin
                        complete_error <= 1;
                        state <= COMPLETE;
                    end else begin
                        if (fill_word == 3) begin
                            valid[fill_index] <= 1;
                            state <= IDLE;
                        end else begin
                            fill_word <= fill_word + 1;
                        end
                    end
                end else if (mem_req_ready) state <= LOAD_WAIT;
                LOAD_WAIT: if (mem_rsp_valid) begin
                    if (mem_rsp_error) begin
                        complete_error <= 1;
                        state <= COMPLETE;
                    end else if (!fill_cacheable) begin
                        if (fill_word == 0) begin
                            complete_rdata <= mem_rsp_rdata;
                        end else begin
                            complete_rdata_high <= mem_rsp_rdata;
                        end
                        if (fill_double && fill_word == 0) begin
                            fill_word <= 1;
                            state <= LOAD_REQ;
                        end else begin
                            state <= COMPLETE;
                        end
                    end else begin
                        if (fill_word == 3) begin
                            valid[fill_index] <= 1;
                            state <= IDLE;
                        end else begin
                            fill_word <= fill_word + 1;
                            state <= LOAD_REQ;
                        end
                    end
                end
                STORE_REQ: if (!mem_req_allow) begin
                    complete_error <= 1;
                    state <= COMPLETE;
                end else if (mem_req_ready) state <= STORE_WAIT;
                STORE_WAIT: if (mem_rsp_valid) begin
                    complete_error <= mem_rsp_error;
                    if (!mem_rsp_error && store_double && !store_second) begin
                        store_addr <= store_addr + 4;
                        store_wdata <= cpu_wdata64[63:32];
                        store_be <= 4'b1111;
                        store_word <= store_word + 1'b1;
                        store_second <= 1;
                        state <= STORE_REQ;
                    end else begin
                        state <= COMPLETE;
                    end
                end
                AMO_REQ: if (!mem_req_allow) begin
                    complete_error <= 1;
                    state <= COMPLETE;
                end else if (mem_req_ready) state <= AMO_WAIT;
                AMO_WAIT: if (mem_rsp_valid) begin
                    complete_error <= mem_rsp_error;
                    complete_rdata <= amo_sc_failed ? 1 :
                                      amo_op == 5'b00011 ? 0 : mem_rsp_rdata;
                    if (!mem_rsp_error && amo_op == 5'b00010) begin
                        reservation_valid <= 1;
                        reservation_addr <= amo_addr[31:2];
                    end
                    state <= COMPLETE;
                end
                COMPLETE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
`ifdef FORMAL
    logic formal_past_valid = 0;
    initial assume(!rst_n);
    always_ff @(posedge clk) begin
        formal_past_valid <= 1;
        if (formal_past_valid) assume(rst_n);
        if (formal_past_valid && rst_n) begin
        if ($past(rst_n && mem_req_valid && !mem_req_ready)) begin
            assume(mem_req_allow);
            assert(mem_req_valid);
            assert($stable({mem_req_write, mem_req_addr, mem_req_wdata,
                            mem_req_be, mem_req_amo, mem_req_amo_op}));
        end
        if (state == AMO_REQ && amo_op == 5'b00011 && !amo_sc_failed &&
            $past(state != AMO_REQ))
            assert($past(state == IDLE && cpu_valid && cpu_amo &&
                         cpu_amo_op == 5'b00011 && reservation_valid &&
                         reservation_addr == cpu_addr[31:2]));
        if ($past(rst_n && state == IDLE && cpu_valid && cpu_amo &&
                  cpu_amo_op == 5'b00011 &&
                  (!reservation_valid || reservation_addr != cpu_addr[31:2])))
            assert(state == AMO_REQ && amo_sc_failed && !mem_req_amo);
        if ($past(rst_n && state == LOAD_WAIT && mem_rsp_valid &&
                  mem_rsp_error))
            assert(valid[$past(fill_index)] == 0);
        end
    end
`endif
endmodule
