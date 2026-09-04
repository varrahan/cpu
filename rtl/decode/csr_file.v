module csr_file (
    input wire clk, input wire rst_n,
    input wire [11:0] read_addr, input wire read_write_intent,
    output reg [31:0] read_data, output reg [31:0] read_modify_data,
    output reg read_illegal,
    input wire commit_valid, input wire [11:0] commit_addr,
    input wire [31:0] commit_data, input wire retire,
    output wire [31:0] commit_visible_data,
    input wire fp_flags_valid, input wire [4:0] fp_flags,
    input wire fp_dirty,
    input wire [63:0] mtime,
    input wire irq_m_software, input wire irq_m_timer,
    input wire irq_m_external, input wire irq_s_software,
    input wire irq_s_timer, input wire irq_s_external, input wire nmi,
    input wire trap_enter, input wire [31:0] trap_pc,
    input wire [31:0] trap_cause, input wire [31:0] trap_tval,
    input wire mret, input wire sret,
    output reg [31:0] trap_vector,
    output wire [31:0] return_pc, output wire [31:0] sreturn_pc,
    output wire [2:0] frm_out, output wire fp_enabled,
    output reg interrupt_pending, output reg [31:0] interrupt_cause,
    output wire wfi_wake_pending,
    output wire [1:0] privilege,
    output wire [31:0] satp_out, output wire mstatus_mprv_out,
    output wire mstatus_sum_out, output wire mstatus_mxr_out,
    output wire [31:0] pmpcfg0_out, output wire [31:0] pmpaddr0_out,
    output wire [31:0] pmpaddr1_out, output wire [31:0] pmpaddr2_out,
    output wire [31:0] pmpaddr3_out,
    output wire [1:0] data_privilege,
    output wire mret_allowed, output wire sret_allowed,
    output wire sfence_allowed, output wire wfi_allowed
);
    localparam [1:0] PRIV_U = 0, PRIV_S = 1, PRIV_M = 3;

    reg [1:0] current_privilege;
    reg mstatus_mie, mstatus_mpie, mstatus_sie, mstatus_spie;
    reg mstatus_spp, mstatus_mprv, mstatus_sum, mstatus_mxr;
    reg mstatus_tvm, mstatus_tw, mstatus_tsr;
    reg [1:0] mstatus_mpp, mstatus_fs;
    reg [31:0] medeleg, mideleg, mie;
    reg mip_ssip, mip_stip, mip_seip;
    reg [31:0] mtvec, stvec, mscratch, sscratch;
    reg [31:0] mepc, sepc, mcause, scause, mtval, stval;
    reg [31:0] mcounteren, scounteren, satp;
    reg [2:0] mcountinhibit;
    reg menvcfgh_adue;
    reg [63:0] mcycle, minstret;
    reg [4:0] fflags;
    reg [2:0] frm;
    reg [31:0] pmpcfg0;
    reg [31:0] pmpaddr [0:3];
    reg csr_exists, csr_read_only, trap_to_s;
    reg [31:0] raw_read_data, visible_commit_data, mip_value;
    integer i;

    wire [1:0] visible_fs = fp_dirty || fp_flags_valid ? 2'b11 :
                            mstatus_fs;
    wire [63:0] visible_minstret = minstret + (retire ? 64'd1 : 64'd0);
    wire [31:0] mstatus_value =
        (visible_fs == 3 ? 32'h8000_0000 : 0) |
        (mstatus_tsr ? 32'h0040_0000 : 0) |
        (mstatus_tw ? 32'h0020_0000 : 0) |
        (mstatus_tvm ? 32'h0010_0000 : 0) |
        (mstatus_mxr ? 32'h0008_0000 : 0) |
        (mstatus_sum ? 32'h0004_0000 : 0) |
        (mstatus_mprv ? 32'h0002_0000 : 0) |
        ({30'b0, visible_fs} << 13) |
        ({30'b0, mstatus_mpp} << 11) |
        (mstatus_spp ? 32'h0000_0100 : 0) |
        (mstatus_mpie ? 32'h0000_0080 : 0) |
        (mstatus_spie ? 32'h0000_0020 : 0) |
        (mstatus_mie ? 32'h0000_0008 : 0) |
        (mstatus_sie ? 32'h0000_0002 : 0);
    wire [31:0] sstatus_value = mstatus_value & 32'h800d_e133;
    wire [31:0] platform_pending_value =
        {20'b0, irq_m_external, 1'b0, irq_s_external, 1'b0,
         irq_m_timer, 1'b0, irq_s_timer, 1'b0,
         irq_m_software, 1'b0, irq_s_software, 1'b0};
    wire [31:0] software_pending_value =
        (mip_seip ? 32'h0000_0200 : 0) |
        (mip_stip ? 32'h0000_0020 : 0) |
        (mip_ssip ? 32'h0000_0002 : 0);
    wire [31:0] pending_value = platform_pending_value |
                                software_pending_value;

    assign privilege = current_privilege;
    assign commit_visible_data = visible_commit_data;
    assign return_pc = {mepc[31:1], 1'b0};
    assign sreturn_pc = {sepc[31:1], 1'b0};
    assign frm_out = frm;
    assign fp_enabled = mstatus_fs != 0;
    assign satp_out = satp;
    assign mstatus_mprv_out = mstatus_mprv;
    assign mstatus_sum_out = mstatus_sum;
    assign mstatus_mxr_out = mstatus_mxr;
    assign pmpcfg0_out = pmpcfg0;
    assign pmpaddr0_out = pmpaddr[0];
    assign pmpaddr1_out = pmpaddr[1];
    assign pmpaddr2_out = pmpaddr[2];
    assign pmpaddr3_out = pmpaddr[3];
    assign data_privilege = current_privilege == PRIV_M && mstatus_mprv
                            ? mstatus_mpp : current_privilege;
    assign wfi_wake_pending = nmi || |(mie & pending_value);
    assign mret_allowed = current_privilege == PRIV_M;
    assign sret_allowed = current_privilege == PRIV_M ||
                          (current_privilege == PRIV_S && !mstatus_tsr);
    assign sfence_allowed = current_privilege == PRIV_M ||
                            (current_privilege == PRIV_S && !mstatus_tvm);
    assign wfi_allowed = current_privilege == PRIV_M ||
                         (current_privilege == PRIV_S && !mstatus_tw);

    function automatic [31:0] tvec_warl;
        input [31:0] value;
        begin tvec_warl = {value[31:2], value[1:0] == 1 ? 2'b01 : 2'b00}; end
    endfunction

    function automatic [31:0] pmpcfg_warl;
        input [31:0] value;
        input [31:0] current;
        integer entry;
        reg [7:0] candidate;
        begin
            pmpcfg_warl = current;
            for (entry = 0; entry < 4; entry = entry + 1)
                if (!current[entry*8 + 7]) begin
                    candidate = value[entry*8 +: 8] & 8'h9f;
                    if (!candidate[0]) candidate[1] = 0;
                    pmpcfg_warl[entry*8 +: 8] = candidate;
                end
        end
    endfunction

    wire machine_irq_enabled = current_privilege != PRIV_M || mstatus_mie;
    wire supervisor_irq_enabled = current_privilege == PRIV_U ||
        (current_privilege == PRIV_S && mstatus_sie);
    wire [5:0] active_irqs = {mie[11] & mip_value[11],
                              mie[3]  & mip_value[3],
                              mie[7]  & mip_value[7],
                              mie[9]  & mip_value[9],
                              mie[1]  & mip_value[1],
                              mie[5]  & mip_value[5]};
    wire [5:0] delegated_irqs = {mideleg[11], mideleg[3], mideleg[7],
                                 mideleg[9], mideleg[1], mideleg[5]};
    wire [5:0] machine_irqs = active_irqs & ~delegated_irqs &
                              {6{machine_irq_enabled}};
    wire [5:0] supervisor_irqs = active_irqs & delegated_irqs &
                                 {6{supervisor_irq_enabled}};

    always @(*) begin
        mip_value = pending_value;
        interrupt_pending = 0;
        interrupt_cause = 0;
        if (nmi) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_001f;
        end else if (machine_irqs[5]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_000b;
        end else if (machine_irqs[4]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0003;
        end else if (machine_irqs[3]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0007;
        end else if (machine_irqs[2]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0009;
        end else if (machine_irqs[1]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0001;
        end else if (machine_irqs[0]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0005;
        end else if (supervisor_irqs[5]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_000b;
        end else if (supervisor_irqs[4]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0003;
        end else if (supervisor_irqs[3]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0007;
        end else if (supervisor_irqs[2]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0009;
        end else if (supervisor_irqs[1]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0001;
        end else if (supervisor_irqs[0]) begin
            interrupt_pending = 1; interrupt_cause = 32'h8000_0005;
        end

        trap_to_s = current_privilege != PRIV_M && trap_cause[4:0] < 16 &&
                    (trap_cause[31] ? mideleg[trap_cause[4:0]]
                                    : medeleg[trap_cause[4:0]]) &&
                    trap_cause != 32'h8000_001f;
        trap_vector = trap_to_s
            ? ({stvec[31:2], 2'b0} +
               ((trap_cause[31] && stvec[1:0] == 1)
                ? {trap_cause[29:0], 2'b0} : 0))
            : ({mtvec[31:2], 2'b0} +
               ((trap_cause[31] && mtvec[1:0] == 1)
                ? {trap_cause[29:0], 2'b0} : 0));
    end

    always @(*) begin
        csr_exists = 1;
        csr_read_only = read_addr[11:10] == 2'b11;
        case (read_addr)
            12'h001: raw_read_data = {27'b0, fflags |
                                      (fp_flags_valid ? fp_flags : 5'b0)};
            12'h002: raw_read_data = {29'b0, frm};
            12'h003: raw_read_data = {24'b0, frm, fflags |
                                      (fp_flags_valid ? fp_flags : 5'b0)};
            12'h100: raw_read_data = sstatus_value;
            12'h104: raw_read_data = mie & mideleg;
            12'h105: raw_read_data = stvec;
            12'h106: raw_read_data = scounteren;
            12'h10a: raw_read_data = 0;
            12'h140: raw_read_data = sscratch;
            12'h141: raw_read_data = sepc;
            12'h142: raw_read_data = scause;
            12'h143: raw_read_data = stval;
            12'h144: raw_read_data = mip_value & mideleg;
            12'h180: raw_read_data = satp;
            12'h300: raw_read_data = mstatus_value;
            12'h301: raw_read_data = 32'h4014_112d;
            12'h302: raw_read_data = medeleg;
            12'h303: raw_read_data = mideleg;
            12'h304: raw_read_data = mie;
            12'h305: raw_read_data = mtvec;
            12'h306: raw_read_data = mcounteren;
            12'h30a, 12'h310: raw_read_data = 0;
            12'h31a: raw_read_data = menvcfgh_adue ? 32'h2000_0000 : 0;
            12'h320: raw_read_data = {29'b0, mcountinhibit};
            12'h340: raw_read_data = mscratch;
            12'h341: raw_read_data = mepc;
            12'h342: raw_read_data = mcause;
            12'h343: raw_read_data = mtval;
            12'h344: raw_read_data = mip_value;
            12'h3a0: raw_read_data = pmpcfg0;
            12'h3a1, 12'h3a2, 12'h3a3: raw_read_data = 0;
            12'h3b0: raw_read_data = pmpaddr[0];
            12'h3b1: raw_read_data = pmpaddr[1];
            12'h3b2: raw_read_data = pmpaddr[2];
            12'h3b3: raw_read_data = pmpaddr[3];
            12'hB00, 12'hC00: raw_read_data = mcycle[31:0];
            12'hC01: raw_read_data = mtime[31:0];
            12'hB02, 12'hC02: raw_read_data = visible_minstret[31:0];
            12'hB80, 12'hC80: raw_read_data = mcycle[63:32];
            12'hC81: raw_read_data = mtime[63:32];
            12'hB82, 12'hC82: raw_read_data = visible_minstret[63:32];
            12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'hF15:
                raw_read_data = 0;
            default: begin
                raw_read_data = 0;
                csr_exists = read_addr >= 12'h3b4 && read_addr <= 12'h3bf;
            end
        endcase

        case (commit_addr)
            12'h001: visible_commit_data = {27'b0, commit_data[4:0]};
            12'h002: visible_commit_data = {29'b0, commit_data[2:0]};
            12'h003: visible_commit_data = {24'b0, commit_data[7:0]};
            12'h105, 12'h305: visible_commit_data = tvec_warl(commit_data);
            12'h141, 12'h341: visible_commit_data = {commit_data[31:1], 1'b0};
            12'h301: visible_commit_data = 32'h4014_112d;
            12'h302: visible_commit_data = commit_data & 32'h0000_b3ff;
            12'h303: visible_commit_data = commit_data & 32'h0000_0222;
            12'h304: visible_commit_data = commit_data & 32'h0000_0aaa;
            12'h106, 12'h306: visible_commit_data = commit_data & 32'h7;
            12'h104: visible_commit_data = commit_data & mideleg & 32'h0000_0aaa;
            12'h320: visible_commit_data = {29'b0, commit_data[2], 1'b0,
                                             commit_data[0]};
            12'h10a, 12'h30a, 12'h310: visible_commit_data = 0;
            12'h31a: visible_commit_data = commit_data & 32'h2000_0000;
            12'h144: visible_commit_data = commit_data & mideleg & 32'h2;
            12'h180: visible_commit_data = commit_data & 32'hffcfffff;
            12'h344: visible_commit_data = commit_data & 32'h0000_0222;
            12'h3a0: visible_commit_data = pmpcfg_warl(commit_data, pmpcfg0);
            12'h3a1, 12'h3a2, 12'h3a3: visible_commit_data = 0;
            12'h3b0: visible_commit_data = pmpcfg0[7] ||
                (pmpcfg0[15] && pmpcfg0[12:11] == 1)
                ? pmpaddr[0] : commit_data & 32'h3fff_ffff;
            12'h3b1: visible_commit_data = pmpcfg0[15] ||
                (pmpcfg0[23] && pmpcfg0[20:19] == 1)
                ? pmpaddr[1] : commit_data & 32'h3fff_ffff;
            12'h3b2: visible_commit_data = pmpcfg0[23] ||
                (pmpcfg0[31] && pmpcfg0[28:27] == 1)
                ? pmpaddr[2] : commit_data & 32'h3fff_ffff;
            12'h3b3: visible_commit_data = pmpcfg0[31]
                ? pmpaddr[3] : commit_data & 32'h3fff_ffff;
            12'h3b4, 12'h3b5, 12'h3b6, 12'h3b7,
            12'h3b8, 12'h3b9, 12'h3ba, 12'h3bb,
            12'h3bc, 12'h3bd, 12'h3be, 12'h3bf:
                visible_commit_data = 0;
            default: visible_commit_data = commit_data;
        endcase
        read_data = raw_read_data;
        read_modify_data = raw_read_data;
        if (read_addr == 12'h344)
            read_modify_data = software_pending_value;
        else if (read_addr == 12'h144)
            read_modify_data = mip_ssip && mideleg[1] ? 32'h2 : 0;
        read_illegal = !csr_exists || read_addr[9:8] > current_privilege ||
                       (read_write_intent && csr_read_only) ||
                       ((read_addr == 1 || read_addr == 2 || read_addr == 3) &&
                        mstatus_fs == 0) ||
                       (current_privilege == PRIV_S && read_addr == 12'h180 &&
                        mstatus_tvm) ||
                       (current_privilege != PRIV_M && read_addr[11:8] == 4'hc &&
                        !((read_addr[1:0] == 0 && mcounteren[0] &&
                           (current_privilege == PRIV_S || scounteren[0])) ||
                          (read_addr[1:0] == 1 && mcounteren[1] &&
                           (current_privilege == PRIV_S || scounteren[1])) ||
                          (read_addr[1:0] == 2 && mcounteren[2] &&
                           (current_privilege == PRIV_S || scounteren[2]))));
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            current_privilege <= PRIV_M;
            mstatus_mie <= 0; mstatus_mpie <= 0;
            mstatus_sie <= 0; mstatus_spie <= 0;
            mstatus_spp <= 0; mstatus_mpp <= PRIV_M;
            mstatus_mprv <= 0; mstatus_sum <= 0; mstatus_mxr <= 0;
            mstatus_tvm <= 0; mstatus_tw <= 0; mstatus_tsr <= 0;
            mstatus_fs <= 1;
            medeleg <= 0; mideleg <= 0; mie <= 0;
            mip_ssip <= 0; mip_stip <= 0; mip_seip <= 0;
            mtvec <= 0; stvec <= 0; mscratch <= 0; sscratch <= 0;
            mepc <= 0; sepc <= 0; mcause <= 0; scause <= 0;
            mtval <= 0; stval <= 0;
            mcounteren <= 0; scounteren <= 0; satp <= 0;
            mcountinhibit <= 0; mcycle <= 0; minstret <= 0;
            menvcfgh_adue <= 0;
            fflags <= 0; frm <= 0; pmpcfg0 <= 0;
            for (i = 0; i < 4; i = i + 1) pmpaddr[i] <= 0;
        end else begin
            if (!mcountinhibit[0]) mcycle <= mcycle + 1;
            if (retire && !mcountinhibit[2]) minstret <= minstret + 1;
            if (commit_valid) begin
                case (commit_addr)
                    12'h001: begin fflags <= commit_data[4:0]; mstatus_fs <= 3; end
                    12'h002: begin frm <= commit_data[2:0]; mstatus_fs <= 3; end
                    12'h003: begin fflags <= commit_data[4:0];
                        frm <= commit_data[7:5]; mstatus_fs <= 3; end
                    12'h100: begin
                        mstatus_sie <= commit_data[1];
                        mstatus_spie <= commit_data[5];
                        mstatus_spp <= commit_data[8];
                        mstatus_fs <= commit_data[14:13];
                        mstatus_sum <= commit_data[18];
                        mstatus_mxr <= commit_data[19];
                    end
                    12'h104: mie <= (mie & ~mideleg) |
                                      (commit_data & mideleg & 32'h0000_0aaa);
                    12'h105: stvec <= tvec_warl(commit_data);
                    12'h106: scounteren <= commit_data & 32'h7;
                    12'h140: sscratch <= commit_data;
                    12'h141: sepc <= {commit_data[31:1], 1'b0};
                    12'h142: scause <= commit_data;
                    12'h143: stval <= commit_data;
                    12'h144: mip_ssip <= commit_data[1] && mideleg[1];
                    12'h180: satp <= commit_data & 32'hffcfffff;
                    12'h300: begin
                        mstatus_sie <= commit_data[1];
                        mstatus_mie <= commit_data[3];
                        mstatus_spie <= commit_data[5];
                        mstatus_mpie <= commit_data[7];
                        mstatus_spp <= commit_data[8];
                        mstatus_mpp <= commit_data[12:11] == 2
                                       ? PRIV_U : commit_data[12:11];
                        mstatus_fs <= commit_data[14:13];
                        mstatus_mprv <= commit_data[17];
                        mstatus_sum <= commit_data[18];
                        mstatus_mxr <= commit_data[19];
                        mstatus_tvm <= commit_data[20];
                        mstatus_tw <= commit_data[21];
                        mstatus_tsr <= commit_data[22];
                    end
                    12'h302: medeleg <= commit_data & 32'h0000_b3ff;
                    12'h303: mideleg <= commit_data & 32'h0000_0222;
                    12'h304: mie <= commit_data & 32'h0000_0aaa;
                    12'h305: mtvec <= tvec_warl(commit_data);
                    12'h306: mcounteren <= commit_data & 32'h7;
                    12'h320: mcountinhibit <= {commit_data[2], 1'b0,
                                               commit_data[0]};
                    12'h31a: menvcfgh_adue <= commit_data[29];
                    12'h340: mscratch <= commit_data;
                    12'h341: mepc <= {commit_data[31:1], 1'b0};
                    12'h342: mcause <= commit_data;
                    12'h343: mtval <= commit_data;
                    12'h344: begin
                        mip_ssip <= commit_data[1];
                        mip_stip <= commit_data[5];
                        mip_seip <= commit_data[9];
                    end
                    12'h3a0: pmpcfg0 <= pmpcfg_warl(commit_data, pmpcfg0);
                    12'h3b0: if (!pmpcfg0[7] &&
                                   !(pmpcfg0[15] && pmpcfg0[12:11] == 1))
                                  pmpaddr[0] <= commit_data & 32'h3fff_ffff;
                    12'h3b1: if (!pmpcfg0[15] &&
                                   !(pmpcfg0[23] && pmpcfg0[20:19] == 1))
                                  pmpaddr[1] <= commit_data & 32'h3fff_ffff;
                    12'h3b2: if (!pmpcfg0[23] &&
                                   !(pmpcfg0[31] && pmpcfg0[28:27] == 1))
                                  pmpaddr[2] <= commit_data & 32'h3fff_ffff;
                    12'h3b3: if (!pmpcfg0[31])
                                  pmpaddr[3] <= commit_data & 32'h3fff_ffff;
                    12'hB00: mcycle[31:0] <= commit_data;
                    12'hB02: minstret[31:0] <= commit_data;
                    12'hB80: mcycle[63:32] <= commit_data;
                    12'hB82: minstret[63:32] <= commit_data;
                    default: ;
                endcase
            end
            if (fp_flags_valid) fflags <= fflags | fp_flags;
            if (fp_dirty || fp_flags_valid) mstatus_fs <= 3;
            if (trap_enter) begin
                if (trap_to_s) begin
                    sepc <= {trap_pc[31:1], 1'b0};
                    scause <= trap_cause; stval <= trap_tval;
                    mstatus_spp <= current_privilege == PRIV_S;
                    mstatus_spie <= mstatus_sie; mstatus_sie <= 0;
                    current_privilege <= PRIV_S;
                end else begin
                    mepc <= {trap_pc[31:1], 1'b0};
                    mcause <= trap_cause; mtval <= trap_tval;
                    mstatus_mpp <= current_privilege;
                    mstatus_mpie <= mstatus_mie; mstatus_mie <= 0;
                    current_privilege <= PRIV_M;
                end
            end else if (mret) begin
                current_privilege <= mstatus_mpp;
                mstatus_mie <= mstatus_mpie; mstatus_mpie <= 1;
                mstatus_mpp <= PRIV_U;
                if (mstatus_mpp != PRIV_M) mstatus_mprv <= 0;
            end else if (sret) begin
                current_privilege <= mstatus_spp ? PRIV_S : PRIV_U;
                mstatus_sie <= mstatus_spie; mstatus_spie <= 1;
                mstatus_spp <= 0; mstatus_mprv <= 0;
            end
        end
    end
endmodule
