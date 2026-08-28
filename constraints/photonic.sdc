create_clock -name optical_clk -period 0.010 [get_ports clk]
set_clock_uncertainty 0.001 [get_clocks optical_clk]

# External ROM/RAM is synchronous to the optical clock. Vendor extracted
# interface delays replace these zero placeholders before release.
set_input_delay 0.000 -clock optical_clk [get_ports {
    imem_req_ready imem_rsp_valid imem_rsp_rdata imem_rsp_error
    dmem_req_ready dmem_rsp_valid dmem_rsp_rdata dmem_rsp_error
}]
set_output_delay 0.000 -clock optical_clk [get_ports {
    imem_req_valid imem_req_addr imem_rsp_ready
    dmem_req_valid dmem_req_write dmem_req_addr dmem_req_wdata dmem_req_be
    dmem_rsp_ready
}]
