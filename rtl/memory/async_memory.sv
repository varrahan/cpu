module async_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 5,
    parameter READ_PORTS = 2,
    parameter BYTE_LANES = 1
) (
    input  logic                               clk,
    input  logic                               rst_n,
    input  logic                               we,
    input  logic [ADDR_WIDTH-1:0]              waddr,
    input  logic [DATA_WIDTH-1:0]              wdata,
    input  logic [BYTE_LANES-1:0]              wbe,
    input  logic [READ_PORTS*ADDR_WIDTH-1:0]   raddr,
    output logic [READ_PORTS*DATA_WIDTH-1:0]   rdata
);
    localparam DEPTH = 1 << ADDR_WIDTH;
    localparam LANE_WIDTH = DATA_WIDTH / BYTE_LANES;
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    genvar read_port;
    integer address, lane;

    generate
        for (read_port = 0; read_port < READ_PORTS; read_port = read_port + 1)
            assign rdata[read_port*DATA_WIDTH +: DATA_WIDTH] =
                mem[raddr[read_port*ADDR_WIDTH +: ADDR_WIDTH]];
    endgenerate

    always_ff @(posedge clk)
        if (!rst_n)
            for (address = 0; address < DEPTH; address = address + 1)
                mem[address] <= {DATA_WIDTH{1'b0}};
        else if (we)
            for (lane = 0; lane < BYTE_LANES; lane = lane + 1)
                if (wbe[lane])
                    mem[waddr][lane*LANE_WIDTH +: LANE_WIDTH] <=
                        wdata[lane*LANE_WIDTH +: LANE_WIDTH];
endmodule
