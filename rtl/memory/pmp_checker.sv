module pmp_checker (
    input  logic [31:0] addr,
    input  logic [3:0]  size,
    input  logic [1:0]  privilege,
    input  logic        access_read,
    input  logic        access_write,
    input  logic        access_execute,
    input  logic [31:0] pmpcfg0,
    input  logic [31:0] pmpaddr0,
    input  logic [31:0] pmpaddr1,
    input  logic [31:0] pmpaddr2,
    input  logic [31:0] pmpaddr3,
    output logic         allow
);
    localparam [1:0] PRIV_M = 2'b11;
    logic [31:0] pmpaddr [0:3];
    logic [7:0] cfg;
    logic [1:0] mode;
    logic [32:0] lower, upper, access_first, access_last;
    logic [29:0] low_mask;
    integer i, ones;
    logic matched;

    function automatic [5:0] trailing_ones;
        input [31:0] value;
        integer k;
        logic counting;
        begin
            trailing_ones = 0;
            counting = 1;
            for (k = 0; k < 30; k = k + 1)
                if (counting && value[k]) trailing_ones = k + 1;
                else counting = 0;
        end
    endfunction

    always_comb begin
        pmpaddr[0] = pmpaddr0;
        pmpaddr[1] = pmpaddr1;
        pmpaddr[2] = pmpaddr2;
        pmpaddr[3] = pmpaddr3;
        access_first = {1'b0, addr};
        access_last = access_first + (size ? size : 1) - 1;
        allow = privilege == PRIV_M;
        matched = 0;
        for (i = 0; i < 4; i = i + 1) begin
            cfg = pmpcfg0[i*8 +: 8];
            mode = cfg[4:3];
            lower = 0;
            upper = 0;
            low_mask = 0;
            ones = 0;
            if (mode == 2'b01) begin
                lower = i == 0 ? 0 : {pmpaddr[i-1], 2'b0};
                upper = {pmpaddr[i], 2'b0};
            end else if (mode == 2'b10) begin
                lower = {pmpaddr[i], 2'b0};
                upper = lower + 4;
            end else if (mode == 2'b11) begin
                ones = trailing_ones(pmpaddr[i]);
                low_mask = ones == 0 ? 0 : (30'h1 << ones) - 1;
                if (ones >= 29) begin
                    lower = 0;
                    upper = 33'h1_0000_0000;
                end else begin
                    lower = {1'b0,
                             (pmpaddr[i][29:0] & ~low_mask), 2'b0};
                    upper = lower + (33'h1 << (ones + 3));
                end
            end

            if (!matched && mode != 0 && access_last >= lower &&
                access_first < upper) begin
                matched = 1;
                if (privilege == PRIV_M && !cfg[7])
                    allow = 1;
                else
                    allow = access_first >= lower && access_last < upper &&
                            (!access_read || cfg[0]) &&
                            (!access_write || cfg[1]) &&
                            (!access_execute || cfg[2]);
            end
        end
        if (privilege != PRIV_M && !matched) allow = 0;
    end
`ifdef FORMAL
    always_comb begin
        if (privilege != PRIV_M &&
            pmpcfg0[4:3] == 0 && pmpcfg0[12:11] == 0 &&
            pmpcfg0[20:19] == 0 && pmpcfg0[28:27] == 0)
            assert(!allow);
        if (privilege == PRIV_M &&
            !(pmpcfg0[7] || pmpcfg0[15] || pmpcfg0[23] || pmpcfg0[31]))
            assert(allow);
    end
`endif
endmodule
