module fpu_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic        flush,
    input  logic [31:0] instr,
    input  logic [31:0] rs1_int,
    input  logic [63:0] frs1,
    input  logic [63:0] frs2,
    input  logic [63:0] frs3,
    input  logic [2:0]  frm,
    output logic        ready,
    output logic        busy,
    output logic        done,
    output logic        illegal,
    output logic [63:0] result,
    output logic [4:0]  flags,
    output logic        result_to_int,
    output logic        write_fp
);
    localparam fpnew_pkg::fpu_implementation_t RV32D_PIPE = '{
        PipeRegs:   '{default: 2},
        UnitTypes:  '{'{default: fpnew_pkg::PARALLEL},
                      '{default: fpnew_pkg::MERGED},
                      '{default: fpnew_pkg::PARALLEL},
                      '{default: fpnew_pkg::MERGED}},
        PipeConfig: fpnew_pkg::DISTRIBUTED
    };

    logic [2:0][63:0] operands;
    fpnew_pkg::roundmode_e round_mode;
    fpnew_pkg::operation_e operation;
    fpnew_pkg::fp_format_e src_format, dst_format;
    fpnew_pkg::int_format_e int_format;
    logic operation_modifier;
    logic decoded_to_int, decoded_write_fp, bypass;
    logic [63:0] bypass_result;
    logic [4:0] bypass_flags;

    logic fp_in_ready, fp_out_valid, fp_busy;
    logic [63:0] fp_result;
    fpnew_pkg::status_t fp_status;
    logic [1:0] fp_tag;
    logic pending, bypass_pending;

    wire [6:0] opcode = instr[6:0];
    wire [6:0] funct7 = instr[31:25];
    wire [2:0] funct3 = instr[14:12];
    wire [4:0] rs2 = instr[24:20];

    function automatic [3:0] resolved_rounding;
        input [2:0] encoded;
        input [2:0] dynamic_mode;
        begin
            if (encoded <= 3'b100)
                resolved_rounding = {1'b0, encoded};
            else if (encoded == 3'b111 && dynamic_mode <= 3'b100)
                resolved_rounding = {1'b0, dynamic_mode};
            else
                resolved_rounding = {1'b1, 3'b000};
        end
    endfunction

    wire [3:0] standard_rounding = resolved_rounding(funct3, frm);

    always_comb begin
        operands = '{default: 64'b0};
        round_mode = fpnew_pkg::RNE;
        operation = fpnew_pkg::ADD;
        src_format = fpnew_pkg::FP32;
        dst_format = fpnew_pkg::FP32;
        int_format = fpnew_pkg::INT32;
        operation_modifier = 1'b0;
        decoded_to_int = 1'b0;
        decoded_write_fp = 1'b1;
        bypass = 1'b0;
        bypass_result = 64'b0;
        bypass_flags = 5'b0;
        illegal = 1'b0;

        case (opcode)
            7'h43, 7'h47, 7'h4b, 7'h4f: begin
                if (instr[26:25] > 2'b01) begin
                    illegal = 1'b1;
                end else begin
                    src_format = instr[25] ? fpnew_pkg::FP64 : fpnew_pkg::FP32;
                    dst_format = src_format;
                    operands[0] = frs1;
                    operands[1] = frs2;
                    operands[2] = frs3;
                    round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                    if (standard_rounding[3]) illegal = 1'b1;
                    case (opcode)
                        7'h43: begin operation = fpnew_pkg::FMADD;  operation_modifier = 1'b0; end
                        7'h47: begin operation = fpnew_pkg::FMADD;  operation_modifier = 1'b1; end
                        7'h4b: begin operation = fpnew_pkg::FNMSUB; operation_modifier = 1'b0; end
                        default: begin operation = fpnew_pkg::FNMSUB; operation_modifier = 1'b1; end
                    endcase
                end
            end
            7'h53: begin
                src_format = funct7[0] ? fpnew_pkg::FP64 : fpnew_pkg::FP32;
                dst_format = src_format;
                operands[0] = frs1;
                operands[1] = frs2;
                operands[2] = frs2;
                case (funct7)
                    7'b0000000, 7'b0000001: begin
                        operation = fpnew_pkg::ADD;
                        operands[1] = frs1;
                        operands[2] = frs2;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b0000100, 7'b0000101: begin
                        operation = fpnew_pkg::ADD;
                        operation_modifier = 1'b1;
                        operands[1] = frs1;
                        operands[2] = frs2;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b0001000, 7'b0001001: begin
                        operation = fpnew_pkg::MUL;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b0001100, 7'b0001101: begin
                        operation = fpnew_pkg::DIV;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b0101100, 7'b0101101: begin
                        operation = fpnew_pkg::SQRT;
                        if (rs2 != 0) illegal = 1'b1;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b0010000, 7'b0010001: begin
                        operation = fpnew_pkg::SGNJ;
                        case (funct3)
                            3'b000: round_mode = fpnew_pkg::RNE;
                            3'b001: round_mode = fpnew_pkg::RTZ;
                            3'b010: round_mode = fpnew_pkg::RDN;
                            default: illegal = 1'b1;
                        endcase
                    end
                    7'b0010100, 7'b0010101: begin
                        operation = fpnew_pkg::MINMAX;
                        case (funct3)
                            3'b000: round_mode = fpnew_pkg::RNE;
                            3'b001: round_mode = fpnew_pkg::RTZ;
                            default: illegal = 1'b1;
                        endcase
                    end
                    7'b1010000, 7'b1010001: begin
                        operation = fpnew_pkg::CMP;
                        decoded_to_int = 1'b1;
                        decoded_write_fp = 1'b0;
                        case (funct3)
                            3'b000: round_mode = fpnew_pkg::RNE;
                            3'b001: round_mode = fpnew_pkg::RTZ;
                            3'b010: round_mode = fpnew_pkg::RDN;
                            default: illegal = 1'b1;
                        endcase
                    end
                    7'b1100000, 7'b1100001: begin
                        operation = fpnew_pkg::F2I;
                        decoded_to_int = 1'b1;
                        decoded_write_fp = 1'b0;
                        operation_modifier = rs2[0];
                        if (rs2 > 1) illegal = 1'b1;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b1101000, 7'b1101001: begin
                        operation = fpnew_pkg::I2F;
                        operands[0] = {32'b0, rs1_int};
                        operation_modifier = rs2[0];
                        if (rs2 > 1) illegal = 1'b1;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b0100000: begin
                        operation = fpnew_pkg::F2F;
                        src_format = fpnew_pkg::FP64;
                        dst_format = fpnew_pkg::FP32;
                        if (rs2 != 1) illegal = 1'b1;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b0100001: begin
                        operation = fpnew_pkg::F2F;
                        src_format = fpnew_pkg::FP32;
                        dst_format = fpnew_pkg::FP64;
                        if (rs2 != 0) illegal = 1'b1;
                        round_mode = fpnew_pkg::roundmode_e'(standard_rounding[2:0]);
                        if (standard_rounding[3]) illegal = 1'b1;
                    end
                    7'b1110000: begin
                        decoded_to_int = 1'b1;
                        decoded_write_fp = 1'b0;
                        if (rs2 != 0) illegal = 1'b1;
                        if (funct3 == 3'b000) begin
                            bypass = 1'b1;
                            bypass_result = {32'b0, frs1[31:0]};
                        end else if (funct3 == 3'b001) begin
                            operation = fpnew_pkg::CLASSIFY;
                        end else begin
                            illegal = 1'b1;
                        end
                    end
                    7'b1110001: begin
                        decoded_to_int = 1'b1;
                        decoded_write_fp = 1'b0;
                        operation = fpnew_pkg::CLASSIFY;
                        if (rs2 != 0 || funct3 != 3'b001) illegal = 1'b1;
                    end
                    7'b1111000: begin
                        bypass = 1'b1;
                        bypass_result = {32'hffff_ffff, rs1_int};
                        if (rs2 != 0 || funct3 != 3'b000) illegal = 1'b1;
                    end
                    default: illegal = 1'b1;
                endcase
            end
            default: illegal = 1'b1;
        endcase
    end

    assign ready = !pending && !bypass_pending;
    assign busy = pending || bypass_pending || fp_busy;

    fpnew_top #(
        .Features       (fpnew_pkg::RV32D),
        .Implementation (RV32D_PIPE),
        .DivSqrtSel     (fpnew_pkg::THMULTI),
        .TagType        (logic [1:0])
    ) u_fpnew (
        .clk_i          (clk),
        .rst_ni         (rst_n),
        .operands_i     (operands),
        .rnd_mode_i     (round_mode),
        .op_i           (operation),
        .op_mod_i       (operation_modifier),
        .src_fmt_i      (src_format),
        .dst_fmt_i      (dst_format),
        .int_fmt_i      (int_format),
        .vectorial_op_i (1'b0),
        .tag_i          ({decoded_to_int, decoded_write_fp}),
        .simd_mask_i    ('1),
        .in_valid_i     (start && ready && !bypass && !illegal),
        .in_ready_o     (fp_in_ready),
        .flush_i        (flush),
        .result_o       (fp_result),
        .status_o       (fp_status),
        .tag_o          (fp_tag),
        .out_valid_o    (fp_out_valid),
        .out_ready_i    (1'b1),
        .busy_o         (fp_busy),
        .early_valid_o  ()
    );

    always_ff @(posedge clk) begin
        done <= 1'b0;
        if (!rst_n || flush) begin
            pending <= 1'b0;
            bypass_pending <= 1'b0;
            result <= 64'b0;
            flags <= 5'b0;
            result_to_int <= 1'b0;
            write_fp <= 1'b0;
        end else begin
            if (start && ready && !illegal) begin
                if (bypass) begin
                    bypass_pending <= 1'b1;
                    result <= bypass_result;
                    flags <= bypass_flags;
                    result_to_int <= decoded_to_int;
                    write_fp <= decoded_write_fp;
                end else if (fp_in_ready) begin
                    pending <= 1'b1;
                end
            end

            if (bypass_pending) begin
                bypass_pending <= 1'b0;
                done <= 1'b1;
            end

            if (fp_out_valid) begin
                pending <= 1'b0;
                result <= fp_result;
                flags <= {fp_status.NV, fp_status.DZ, fp_status.OF,
                          fp_status.UF, fp_status.NX};
                result_to_int <= fp_tag[1];
                write_fp <= fp_tag[0];
                done <= 1'b1;
            end
        end
    end
endmodule
