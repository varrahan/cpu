// 256-byte direct-mapped cache, 16-byte read/fill lines, one external request.
module hybrid_icache (
    input logic clk, rst_n, invalidate,
    input logic valid,
    input logic [31:0] address,
    output logic ready, error,
    output logic [127:0] data,
    output logic mem_req_valid,
    input logic mem_req_ready, mem_req_allow,
    output logic [31:0] mem_req_addr,
    input logic mem_rsp_valid, mem_rsp_error,
    output logic mem_rsp_ready,
    input logic [31:0] mem_rsp_rdata
);
    logic [127:0] lines [16];
    logic [23:0] tags [16];
    logic [15:0] present;
    logic [31:0] fill;
    logic [1:0] beat;
    logic drop, failed;
    typedef enum logic [1:0] {IDLE, REQUEST, RESPONSE, COMPLETE} state_t;
    state_t state;
    wire hit = present[address[7:4]] && tags[address[7:4]] == address[31:8];
    assign ready = valid && ((state == IDLE && hit) || state == COMPLETE);
    assign error = state == COMPLETE && failed;
    assign data = ready && !error ? lines[address[7:4]] : 0;
    assign mem_req_valid = state == REQUEST && mem_req_allow;
    assign mem_req_addr = fill + {28'b0, beat, 2'b0};
    assign mem_rsp_ready = state == RESPONSE;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE; present <= 0; fill <= 0; beat <= 0;
            drop <= 0; failed <= 0;
            for (int i=0; i<16; i++) begin lines[i] <= 0; tags[i] <= 0; end
        end else begin
            if (invalidate) begin present <= 0; drop <= 1; end
            case (state)
                IDLE: if (valid && !hit) begin
                    fill <= {address[31:4],4'b0}; beat <= 0;
                    present[address[7:4]] <= 0; failed <= 0; drop <= invalidate;
                    state <= REQUEST;
                end
                REQUEST: if (!mem_req_allow) begin
                    // Per-halfword PMP checks at fetch reject these zero lanes.
                    lines[fill[7:4]][beat*32 +:32] <= 0;
                    if (beat == 3) begin
                        tags[fill[7:4]] <= fill[31:8];
                        present[fill[7:4]] <= !drop && !invalidate;
                        state <= COMPLETE;
                    end else beat <= beat + 1'b1;
                end else if (mem_req_ready) state <= RESPONSE;
                RESPONSE: if (mem_rsp_valid) begin
                    lines[fill[7:4]][beat*32 +:32] <= mem_rsp_error ? 0 : mem_rsp_rdata;
                    failed <= failed || mem_rsp_error;
                    if (beat == 3 || mem_rsp_error) begin
                        tags[fill[7:4]] <= fill[31:8];
                        present[fill[7:4]] <= !drop && !invalidate && !mem_rsp_error;
                        state <= COMPLETE;
                    end else begin beat <= beat + 1'b1; state <= REQUEST; end
                end
                COMPLETE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
