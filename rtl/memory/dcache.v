module dcache (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cpu_valid,
    input  wire        cpu_write,
    input  wire        cpu_double,
    input  wire        cpu_amo,
    input  wire [4:0]  cpu_amo_op,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [63:0] cpu_wdata64,
    input  wire [3:0]  cpu_be,
    output wire [31:0] cpu_rdata,
    output wire [63:0] cpu_rdata64,
    output wire        cpu_ready,
    output wire        cpu_error,
    input  wire        reservation_invalidate,

    output wire        mem_req_valid,
    input  wire        mem_req_allow,
    input  wire        mem_req_ready,
    output wire        mem_req_write,
    output wire [31:0] mem_req_addr,
    output wire [31:0] mem_req_wdata,
    output wire [3:0]  mem_req_be,
    output wire        mem_req_amo,
    output wire [4:0]  mem_req_amo_op,
    input  wire        mem_rsp_valid,
    output wire        mem_rsp_ready,
    input  wire [31:0] mem_rsp_rdata,
    input  wire        mem_rsp_error
);
    localparam IDLE = 4'd0, LOAD_REQ = 4'd1, LOAD_WAIT = 4'd2,
               STORE_REQ = 4'd3, STORE_WAIT = 4'd4, COMPLETE = 4'd5,
               AMO_REQ = 4'd6, AMO_WAIT = 4'd7;

    reg [3:0] state;
    reg [15:0] valid;
    reg [31:0] fill_base;
    reg [3:0]  fill_index;
    reg [23:0] fill_tag;
    reg [1:0]  fill_word;
    reg [3:0]  fill_required_mask;
    reg [31:0] store_addr;
    reg [31:0] store_wdata;
    reg [3:0]  store_be;
    reg [3:0]  store_index;
    reg [1:0]  store_word;
    reg        store_hit;
    reg        store_double;
    reg        store_second;
    reg [31:0] amo_addr;
    reg [31:0] amo_wdata;
    reg [4:0]  amo_op;
    reg        reservation_valid;
    reg [31:2] reservation_addr;
    reg [31:0] complete_rdata;
    reg        complete_error;
    wire [3:0] cpu_index = cpu_addr[7:4];
    wire [1:0] cpu_word  = cpu_addr[3:2];
    wire [23:0] tag_rdata;
    wire [63:0] data_rdata;
    wire       hit = valid[cpu_index] && tag_rdata == cpu_addr[31:8];
    wire load_zero_write = state == LOAD_REQ && !mem_req_allow &&
                           !fill_required_mask[fill_word];
    wire load_data_write = state == LOAD_WAIT && mem_rsp_valid &&
                           !mem_rsp_error;
    wire store_data_write = state == STORE_WAIT && mem_rsp_valid &&
                            !mem_rsp_error && store_hit;
    wire fill_array_write = load_zero_write || load_data_write;
    wire array_write = fill_array_write || store_data_write;

    P_MEM_ASYNC #(.DATA_WIDTH(24), .ADDR_WIDTH(4), .READ_PORTS(1)) u_tags (
        .clk(clk), .rst_n(rst_n), .we(fill_array_write && fill_word == 3),
        .waddr(fill_index), .wdata(fill_tag), .wbe(1'b1),
        .raddr(cpu_index), .rdata(tag_rdata)
    );
    P_MEM_ASYNC #(
        .DATA_WIDTH(32), .ADDR_WIDTH(6), .READ_PORTS(2), .BYTE_LANES(4)
    ) u_data (
        .clk(clk), .rst_n(rst_n), .we(array_write),
        .waddr(store_data_write ? {store_index, store_word}
                                : {fill_index, fill_word}),
        .wdata(store_data_write ? store_wdata
                                : load_zero_write ? 32'b0 : mem_rsp_rdata),
        .wbe(store_data_write ? store_be : 4'b1111),
        .raddr({cpu_index, cpu_word + 1'b1, cpu_index, cpu_word}),
        .rdata(data_rdata)
    );

    assign cpu_rdata = state == COMPLETE ? complete_rdata
                                         : data_rdata[31:0];
    assign cpu_rdata64 = data_rdata;
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
    assign mem_req_amo   = state == AMO_REQ;
    assign mem_req_amo_op = amo_op;
    assign mem_rsp_ready = state == LOAD_WAIT || state == STORE_WAIT ||
                           state == AMO_WAIT;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            valid <= 0;
            fill_base <= 0;
            fill_index <= 0;
            fill_tag <= 0;
            fill_word <= 0;
            fill_required_mask <= 0;
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
            reservation_valid <= 0;
            reservation_addr <= 0;
            complete_rdata <= 0;
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
                            complete_rdata <= 1;
                            reservation_valid <= 0;
                            state <= COMPLETE;
                        end else begin
                            amo_addr <= cpu_addr;
                            amo_wdata <= cpu_wdata;
                            amo_op <= cpu_amo_op;
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
                        fill_base  <= {cpu_addr[31:4], 4'b0};
                        fill_index <= cpu_index;
                        fill_tag   <= cpu_addr[31:8];
                        fill_word  <= 0;
                        fill_required_mask <= (4'b0001 << cpu_word) |
                                              (cpu_double
                                               ? (4'b0010 << cpu_word) : 0);
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
                    complete_rdata <= amo_op == 5'b00011 ? 0 : mem_rsp_rdata;
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
    reg formal_past_valid = 0;
    initial assume(!rst_n);
    always @(posedge clk) begin
        formal_past_valid <= 1;
        if (formal_past_valid) assume(rst_n);
        if (formal_past_valid && rst_n) begin
        if ($past(rst_n && mem_req_valid && !mem_req_ready)) begin
            assert(mem_req_valid);
            assert($stable({mem_req_write, mem_req_addr, mem_req_wdata,
                            mem_req_be, mem_req_amo, mem_req_amo_op}));
        end
        if (state == AMO_REQ && amo_op == 5'b00011)
            assert($past(state == IDLE && cpu_valid && cpu_amo &&
                         cpu_amo_op == 5'b00011 && reservation_valid &&
                         reservation_addr == cpu_addr[31:2]));
        if ($past(state == IDLE && cpu_valid && cpu_amo &&
                  cpu_amo_op == 5'b00011 &&
                  (!reservation_valid || reservation_addr != cpu_addr[31:2])))
            assert(state == COMPLETE && complete_rdata == 1 &&
                   !mem_req_valid);
        if ($past(rst_n && state == LOAD_WAIT && mem_rsp_valid &&
                  mem_rsp_error))
            assert(valid[$past(fill_index)] == 0);
        end
    end
`endif
endmodule
