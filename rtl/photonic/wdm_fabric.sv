// Cycle-level, synthesizable endpoint contract. Optical PHY replacement must
// implement the same bounded queues, serialization and returned-credit delay.
module wdm_fabric #(
    parameter int CHANNELS = hybrid_pkg::CHANNELS,
    parameter int BITS = hybrid_pkg::MESSAGE_BITS,
    parameter int BITS_PER_CYCLE = BITS,
    parameter int FLIGHT_CYCLES = 1,
    parameter int CREDIT_CYCLES = 1,
    parameter int DEPTH = 8
) (
    input logic clk, rst_n, flush,
    input logic [CHANNELS-1:0] tx_valid,
    output logic [CHANNELS-1:0] tx_ready,
    input logic [BITS-1:0] tx_data [CHANNELS],
    output logic [CHANNELS-1:0] rx_valid,
    input logic [CHANNELS-1:0] rx_ready,
    output logic [BITS-1:0] rx_data [CHANNELS],
    output logic idle,
    output logic [CHANNELS-1:0] channel_idle
);
    localparam int SERIAL = (BITS + BITS_PER_CYCLE - 1) / BITS_PER_CYCLE;
    localparam int PTR = $clog2(DEPTH);
    localparam int COUNT = $clog2(DEPTH+1);
    localparam int SERIAL_COUNT = $clog2(SERIAL+1);
    localparam int DELAY_COUNT = $clog2(SERIAL+FLIGHT_CYCLES+1);
    logic [CHANNELS-1:0] empty;
    initial begin
        assert(BITS_PER_CYCLE > 0 && FLIGHT_CYCLES >= 1 && CREDIT_CYCLES >= 1);
        assert(DEPTH >= 2 && (DEPTH & (DEPTH-1)) == 0);
    end
    assign idle = &empty;
    assign channel_idle = empty;
    for (genvar c = 0; c < CHANNELS; c++) begin: channel
        logic [BITS-1:0] queue [DEPTH];
        logic [PTR-1:0] head, tail;
        logic [COUNT-1:0] used, credits;
        logic [SERIAL_COUNT-1:0] serializer;
        logic [DELAY_COUNT-1:0] delay [DEPTH];
        logic [CREDIT_CYCLES-1:0] returning;
        logic [31:0] generation, return_generation[CREDIT_CYCLES];
        logic [CREDIT_CYCLES-1:0] current_returning;
        for(genvar t=0;t<CREDIT_CYCLES;t++)
            assign current_returning[t]=returning[t] && return_generation[t]==generation;
        wire push = tx_valid[c] && tx_ready[c];
        wire pop = rx_valid[c] && rx_ready[c];
        assign tx_ready[c] = rst_n && !flush && credits != 0 && serializer == 0;
        assign rx_valid[c] = rst_n && !flush && used != 0 && delay[head] == 0;
        assign rx_data[c] = rx_valid[c] ? queue[head] : '0;
        assign empty[c] = used == 0 && credits == DEPTH;
        always_ff @(posedge clk) begin
            if (!rst_n) begin
                head <= 0; tail <= 0; used <= 0; credits <= DEPTH;
                serializer <= 0; returning <= 0;
                generation<=0;
                for(int t=0;t<CREDIT_CYCLES;t++) return_generation[t]<=0;
                for (int k = 0; k < DEPTH; k++) begin queue[k] <= '0; delay[k] <= 0; end
            end else begin
                // Credit tokens include the epoch. A late credit from flushed
                // traffic must not grant space in the new generation.
                returning <= (returning << 1) | CREDIT_CYCLES'(pop);
                return_generation[0]<=generation;
                for(int t=1;t<CREDIT_CYCLES;t++) return_generation[t]<=return_generation[t-1];
                if(flush) begin
                    head<=0;tail<=0;used<=0;credits<=DEPTH;serializer<=0;
                    generation<=generation+1;
                    for(int k=0;k<DEPTH;k++) begin queue[k]<='0;delay[k]<=0;end
                end else begin
                used <= used + int'(push) - int'(pop);
                credits <= credits - int'(push) + int'(current_returning[CREDIT_CYCLES-1]);
                if (serializer != 0) serializer <= serializer - 1;
                for (int k = 0; k < DEPTH; k++)
                    if (delay[k] != 0) delay[k] <= delay[k] - 1;
                if (push) begin
                    queue[tail] <= tx_data[c];
                    delay[tail] <= SERIAL + FLIGHT_CYCLES - 1;
                    tail <= tail + 1'b1;
                    serializer <= SERIAL - 1;
                end
                if (pop) head <= head + 1'b1;
                assert(used >= 0 && used <= DEPTH && credits >= 0 && credits <= DEPTH);
                assert(used + credits + $countones(current_returning) == DEPTH);
                end
            end
        end
    end
endmodule
