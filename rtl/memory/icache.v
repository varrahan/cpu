module icache (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        cancel,
    input  wire        invalidate,
    input  wire        cpu_valid,
    input  wire [31:2] cpu_addr,
    input  wire [31:2] cpu_next_addr,
    input  wire        cpu_need_next,
    output wire [31:0] cpu_rdata,
    output wire [15:0] cpu_rdata_next,
    output wire        cpu_current_ready,
    output wire        cpu_ready,
    output wire        cpu_error,

    output wire        mem_req_valid,
    input  wire        mem_req_allow,
    input  wire        mem_req_ready,
    output wire [31:0] mem_req_addr,
    input  wire        mem_rsp_valid,
    output wire        mem_rsp_ready,
    input  wire [31:0] mem_rsp_rdata,
    input  wire        mem_rsp_error
);
    localparam IDLE = 2'd0, REQ = 2'd1, WAIT_RSP = 2'd2, ERROR = 2'd3;

    reg [1:0] state;
    reg [15:0] valid;
    reg [31:0] fill_base;
    reg [3:0]  fill_index;
    reg [23:0] fill_tag;
    reg [1:0]  fill_word;
    reg        drop_fill;
    reg [1:0]  required_word;

    wire [3:0] cpu_index = cpu_addr[7:4];
    wire [1:0] cpu_word  = cpu_addr[3:2];
    wire [31:2] next_addr = cpu_next_addr;
    wire [3:0] next_index = next_addr[7:4];
    wire [1:0] next_word = next_addr[3:2];
    wire [47:0] tag_rdata;
    wire [63:0] data_rdata;
    wire       hit = valid[cpu_index] && tag_rdata[23:0] == cpu_addr[31:8];
    wire       next_hit = valid[next_index] &&
                          tag_rdata[47:24] == next_addr[31:8];
    wire [31:2] miss_addr = hit && cpu_need_next && !next_hit
                            ? next_addr[31:2] : cpu_addr[31:2];
    wire fill_zero_write = state == REQ && !mem_req_allow &&
                           fill_word != required_word;
    wire fill_data_write = state == WAIT_RSP && mem_rsp_valid &&
                           !(drop_fill || cancel || invalidate) &&
                           !mem_rsp_error;
    wire array_write = fill_zero_write || fill_data_write;

    P_MEM_ASYNC #(.DATA_WIDTH(24), .ADDR_WIDTH(4), .READ_PORTS(2)) u_tags (
        .clk(clk), .rst_n(rst_n), .we(array_write && fill_word == 3),
        .waddr(fill_index), .wdata(fill_tag), .wbe(1'b1),
        .raddr({next_index, cpu_index}), .rdata(tag_rdata)
    );
    P_MEM_ASYNC #(
        .DATA_WIDTH(32), .ADDR_WIDTH(6), .READ_PORTS(2), .BYTE_LANES(4)
    ) u_data (
        .clk(clk), .rst_n(rst_n), .we(array_write),
        .waddr({fill_index, fill_word}),
        .wdata(fill_zero_write ? 32'b0 : mem_rsp_rdata), .wbe(4'b1111),
        .raddr({next_index, next_word, cpu_index, cpu_word}),
        .rdata(data_rdata)
    );

    assign cpu_rdata = data_rdata[31:0];
    assign cpu_rdata_next = data_rdata[47:32];
    assign cpu_current_ready = state == IDLE && hit;
    assign cpu_error = state == ERROR;
    assign cpu_ready = cpu_valid && (cpu_error ||
                       (state == IDLE && hit && (!cpu_need_next || next_hit)));

    assign mem_req_valid = state == REQ && mem_req_allow;
    assign mem_req_addr  = fill_base + {28'b0, fill_word, 2'b00};
    assign mem_rsp_ready = state == WAIT_RSP;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            valid <= 0;
            fill_base <= 0;
            fill_index <= 0;
            fill_tag <= 0;
            fill_word <= 0;
            drop_fill <= 0;
            required_word <= 0;
        end else begin
            if (invalidate) valid <= 0;
            case (state)
                IDLE: begin
                    drop_fill <= 0;
                    if (cpu_valid && !cancel && !invalidate && !cpu_ready) begin
                        fill_base  <= {miss_addr[31:4], 4'b0};
                        fill_index <= miss_addr[7:4];
                        fill_tag   <= miss_addr[31:8];
                        fill_word  <= 0;
                        required_word <= miss_addr[3:2];
                        valid[miss_addr[7:4]] <= 0;
                        state <= REQ;
                    end
                end
                REQ: begin
                    if (!mem_req_allow) begin
                        if (fill_word == required_word)
                            state <= ERROR;
                        else begin
                            if (fill_word == 3) begin
                                valid[fill_index] <= 1;
                                state <= IDLE;
                            end else begin
                                fill_word <= fill_word + 1;
                            end
                        end
                    end else if ((cancel || invalidate) && !mem_req_ready) begin
                        state <= IDLE;
                    end else if (mem_req_ready) begin
                        drop_fill <= cancel || invalidate;
                        state <= WAIT_RSP;
                    end
                end
                WAIT_RSP: begin
                    if (cancel || invalidate) drop_fill <= 1;
                    if (mem_rsp_valid) begin
                        if (drop_fill || cancel || invalidate) begin
                            drop_fill <= 0;
                            state <= IDLE;
                        end else if (mem_rsp_error) begin
                            state <= ERROR;
                        end else begin
                            if (fill_word == 3) begin
                                valid[fill_index] <= 1;
                                state <= IDLE;
                            end else begin
                                fill_word <= fill_word + 1;
                                state <= REQ;
                            end
                        end
                    end
                end
                ERROR: if (cancel || invalidate) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
