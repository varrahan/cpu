module riscv_debug_transport (
    input logic core_clk, input logic core_rst_n,
    input logic tck, input logic trst_n, input logic tms, input logic tdi,
    output logic tdo,
    output logic debug_req, output logic debug_resume,
    output logic debug_reg_valid, output logic debug_reg_write,
    output logic [5:0] debug_reg_addr,
    output logic [63:0] debug_reg_wdata,
    input logic debug_reg_ready, input logic [63:0] debug_reg_rdata,
    input logic debug_halted, input logic [31:0] debug_dpc,
    input logic [1:0] debug_privilege,
    output logic debug_dpc_write, output logic [31:0] debug_dpc_wdata,
    output logic debug_step
);
    localparam logic [4:0] IR_IDCODE = 5'h01;
    localparam logic [4:0] IR_DTMCS = 5'h10;
    localparam logic [4:0] IR_DMI = 5'h11;
    localparam [3:0] TEST_LOGIC_RESET = 0, RUN_TEST_IDLE = 1,
        SELECT_DR_SCAN = 2, CAPTURE_DR = 3, SHIFT_DR = 4, EXIT1_DR = 5,
        PAUSE_DR = 6, EXIT2_DR = 7, UPDATE_DR = 8, SELECT_IR_SCAN = 9,
        CAPTURE_IR = 10, SHIFT_IR = 11, EXIT1_IR = 12, PAUSE_IR = 13,
        EXIT2_IR = 14, UPDATE_IR = 15;
    logic [3:0] tap_state, tap_next;
    logic [4:0] ir, ir_shift;
    logic [40:0] dr_shift;
    logic bypass;
    logic [6:0] dmi_addr_tck, rsp_addr_tck;
    logic [31:0] dmi_data_tck, rsp_data_tck;
    logic [1:0] dmi_op_tck, rsp_op_tck, dmi_status_tck;
    logic req_toggle_tck, request_pending_tck;
    logic rsp_toggle_core;
    (* ASYNC_REG = "TRUE" *) logic [1:0] rsp_toggle_sync_tck;
    (* ASYNC_REG = "TRUE" *) logic [1:0] req_toggle_sync_core;
    logic req_seen_core;
    logic [6:0] rsp_addr_core;
    logic [31:0] rsp_data_core;
    logic [1:0] rsp_op_core;
    logic [31:0] data0, data1;
    logic dmactive, abstract_busy, dcsr_step, halted_q;
    logic resume_ack, step_resume_pending;
    logic [2:0] cmderr, dcsr_cause;
    logic [1:0] dcsr_prv;

    assign debug_step = dcsr_step;

    always_comb begin
        case (tap_state)
            TEST_LOGIC_RESET: tap_next = tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
            RUN_TEST_IDLE: tap_next = tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
            SELECT_DR_SCAN: tap_next = tms ? SELECT_IR_SCAN : CAPTURE_DR;
            CAPTURE_DR: tap_next = tms ? EXIT1_DR : SHIFT_DR;
            SHIFT_DR: tap_next = tms ? EXIT1_DR : SHIFT_DR;
            EXIT1_DR: tap_next = tms ? UPDATE_DR : PAUSE_DR;
            PAUSE_DR: tap_next = tms ? EXIT2_DR : PAUSE_DR;
            EXIT2_DR: tap_next = tms ? UPDATE_DR : SHIFT_DR;
            UPDATE_DR: tap_next = tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
            SELECT_IR_SCAN: tap_next = tms ? TEST_LOGIC_RESET : CAPTURE_IR;
            CAPTURE_IR: tap_next = tms ? EXIT1_IR : SHIFT_IR;
            SHIFT_IR: tap_next = tms ? EXIT1_IR : SHIFT_IR;
            EXIT1_IR: tap_next = tms ? UPDATE_IR : PAUSE_IR;
            PAUSE_IR: tap_next = tms ? EXIT2_IR : PAUSE_IR;
            EXIT2_IR: tap_next = tms ? UPDATE_IR : SHIFT_IR;
            default: tap_next = tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
        endcase
    end

    always_comb begin
        tdo = 0;
        if (tap_state == SHIFT_IR) tdo = ir_shift[0];
        if (tap_state == SHIFT_DR) tdo = ir == 5'h1f ? bypass : dr_shift[0];
    end

    always_ff @(posedge tck or negedge trst_n) begin
        if (!trst_n) begin
            tap_state <= TEST_LOGIC_RESET; ir <= IR_IDCODE; ir_shift <= 0;
            dr_shift <= 0; bypass <= 0; dmi_addr_tck <= 0; dmi_data_tck <= 0;
            dmi_op_tck <= 0; rsp_addr_tck <= 0; rsp_data_tck <= 0;
            rsp_op_tck <= 0; dmi_status_tck <= 0; req_toggle_tck <= 0;
            request_pending_tck <= 0; rsp_toggle_sync_tck <= 0;
        end else begin
            tap_state <= tap_next;
            rsp_toggle_sync_tck <= {rsp_toggle_sync_tck[0], rsp_toggle_core};
            if (rsp_toggle_sync_tck[1] != rsp_toggle_sync_tck[0]) begin
                rsp_addr_tck <= rsp_addr_core;
                rsp_data_tck <= rsp_data_core;
                rsp_op_tck <= rsp_op_core;
                request_pending_tck <= 0;
                if (rsp_op_core != 0) dmi_status_tck <= rsp_op_core;
            end
            if (tap_state == TEST_LOGIC_RESET) ir <= IR_IDCODE;
            if (tap_state == CAPTURE_IR) ir_shift <= 5'b00001;
            if (tap_state == SHIFT_IR) ir_shift <= {tdi, ir_shift[4:1]};
            if (tap_state == UPDATE_IR) ir <= ir_shift;
            if (tap_state == CAPTURE_DR) begin
                case (ir)
                    IR_IDCODE: dr_shift <= {9'b0, 32'h0000_0001};
                    IR_DTMCS: dr_shift <= {9'b0, 17'b0, 3'd1,
                                           dmi_status_tck, 6'd7, 4'd1};
                    IR_DMI: dr_shift <= request_pending_tck
                        ? {dmi_addr_tck, 32'b0, 2'b11}
                        : {rsp_addr_tck, rsp_data_tck, rsp_op_tck};
                    default: bypass <= 0;
                endcase
            end
            if (tap_state == SHIFT_DR) begin
                if (ir == 5'h1f) bypass <= tdi;
                else if (ir == IR_DMI) dr_shift <= {tdi, dr_shift[40:1]};
                else dr_shift[31:0] <= {tdi, dr_shift[31:1]};
            end
            if (tap_state == UPDATE_DR && ir == IR_DTMCS && dr_shift[16])
                dmi_status_tck <= 0;
            if (tap_state == UPDATE_DR && ir == IR_DMI && dr_shift[1:0] != 0) begin
                if (request_pending_tck) dmi_status_tck <= 2'b11;
                else begin
                    dmi_addr_tck <= dr_shift[40:34];
                    dmi_data_tck <= dr_shift[33:2];
                    dmi_op_tck <= dr_shift[1:0];
                    req_toggle_tck <= ~req_toggle_tck;
                    request_pending_tck <= 1;
                end
            end
        end
    end

    always_ff @(posedge core_clk) begin
        if (!core_rst_n) begin
            req_toggle_sync_core <= 0; req_seen_core <= 0;
            rsp_toggle_core <= 0; rsp_addr_core <= 0; rsp_data_core <= 0;
            rsp_op_core <= 0; data0 <= 0; data1 <= 0; dmactive <= 0;
            abstract_busy <= 0; cmderr <= 0; dcsr_step <= 0;
            dcsr_cause <= 3; dcsr_prv <= 3; halted_q <= 0;
            resume_ack <= 0; step_resume_pending <= 0;
            debug_req <= 0; debug_resume <= 0; debug_reg_valid <= 0;
            debug_reg_write <= 0; debug_reg_addr <= 0; debug_reg_wdata <= 0;
            debug_dpc_write <= 0; debug_dpc_wdata <= 0;
        end else begin
            req_toggle_sync_core <= {req_toggle_sync_core[0], req_toggle_tck};
            halted_q <= debug_halted;
            debug_dpc_write <= 0;
            if (debug_req && debug_halted) debug_req <= 0;
            if (debug_resume && !debug_halted) begin
                debug_resume <= 0; resume_ack <= 1;
            end
            if (!halted_q && debug_halted) begin
                dcsr_cause <= step_resume_pending ? 3'd4 : 3'd3;
                dcsr_prv <= debug_privilege;
                step_resume_pending <= 0;
            end
            if (abstract_busy && debug_reg_valid && debug_reg_ready) begin
                if (!debug_reg_write) begin
                    data0 <= debug_reg_rdata[31:0];
                    if (debug_reg_addr[5]) data1 <= debug_reg_rdata[63:32];
                end
                debug_reg_valid <= 0; abstract_busy <= 0;
            end
            if (req_toggle_sync_core[1] != req_seen_core) begin
                req_seen_core <= req_toggle_sync_core[1];
                rsp_addr_core <= dmi_addr_tck; rsp_data_core <= 0;
                rsp_op_core <= 0;
                if (dmi_op_tck == 2'b01) begin
                    case (dmi_addr_tck)
                        7'h04: rsp_data_core <= data0;
                        7'h05: rsp_data_core <= data1;
                        7'h10: rsp_data_core <= {31'b0, dmactive};
                        7'h11: rsp_data_core <= 32'd3 | (32'd1 << 7) |
                            (debug_halted ? ((32'd1 << 8) | (32'd1 << 9))
                                          : ((32'd1 << 10) | (32'd1 << 11))) |
                            (resume_ack ? ((32'd1 << 16) | (32'd1 << 17)) : 0);
                        7'h16: rsp_data_core <= {19'b0, abstract_busy,
                                                1'b0, cmderr, 4'b0, 4'd2};
                        default: rsp_data_core <= 0;
                    endcase
                end else if (dmi_op_tck == 2'b10) begin
                    case (dmi_addr_tck)
                        7'h04: data0 <= dmi_data_tck;
                        7'h05: data1 <= dmi_data_tck;
                        7'h10: begin
                            dmactive <= dmi_data_tck[0];
                            if (!dmi_data_tck[0]) begin
                                debug_req <= 0; debug_resume <= 0;
                                cmderr <= 0; resume_ack <= 0;
                            end else begin
                                if (dmi_data_tck[31]) debug_req <= 1;
                                if (!dmi_data_tck[30]) resume_ack <= 0;
                                if (dmi_data_tck[30]) begin
                                    debug_resume <= 1;
                                    step_resume_pending <= dcsr_step;
                                end
                            end
                        end
                        7'h16: cmderr <= cmderr & ~dmi_data_tck[10:8];
                        7'h17: begin
                            if (abstract_busy) cmderr <= 3'd1;
                            else if (dmi_data_tck[31:24] != 0 ||
                                     dmi_data_tck[22:20] != 3'd2 ||
                                     !dmi_data_tck[17]) cmderr <= 3'd2;
                            else if (dmi_data_tck[15:0] == 16'h7b0) begin
                                if (dmi_data_tck[16]) dcsr_step <= data0[2];
                                else data0 <= {4'h4, 19'b0, dcsr_cause,
                                              3'b0, dcsr_step, dcsr_prv};
                            end else if (dmi_data_tck[15:0] == 16'h7b1) begin
                                if (dmi_data_tck[16]) begin
                                    debug_dpc_wdata <= data0;
                                    debug_dpc_write <= debug_halted;
                                end else data0 <= debug_dpc;
                            end else if (dmi_data_tck[15:0] == 16'h0301 &&
                                         !dmi_data_tck[16]) begin
                                data0 <= 32'h4014_112d;
                            end else if (dmi_data_tck[15:12] == 4'h1 &&
                                         dmi_data_tck[11:5] <= 7'd1) begin
                                if (!debug_halted) cmderr <= 3'd4;
                                else begin
                                    debug_reg_addr <= {dmi_data_tck[5],
                                                       dmi_data_tck[4:0]};
                                    debug_reg_wdata <= {data1, data0};
                                    debug_reg_write <= dmi_data_tck[16];
                                    debug_reg_valid <= 1; abstract_busy <= 1;
                                end
                            end else cmderr <= 3'd2;
                        end
                        default: begin end
                    endcase
                end else rsp_op_core <= 2'b10;
                rsp_toggle_core <= ~rsp_toggle_core;
            end
        end
    end
endmodule
