
# gan_mind.xdc
# Assumes a single 100 MHz AXI fabric clock (axi_aclk) coming from PS or PLL.
create_clock -name axi_clk -period 10.000 [get_ports axi_aclk]

# Treat AXI reset as synchronous to axi_clk.
set_false_path -from [get_ports axi_aresetn]

# AXI4-Lite control interface delays (2.5 ns budget each way by default).
set_input_delay  -clock axi_clk 2.5 [get_ports { \
	s_axi_awaddr[*] s_axi_awvalid s_axi_wdata[*] s_axi_wstrb[*] \
	s_axi_wvalid s_axi_bready s_axi_araddr[*] s_axi_arvalid s_axi_rready \
	s_axis_pixel_tdata[*] s_axis_pixel_tvalid s_axis_pixel_tlast \
	m_axis_frame_tready \
}]

set_output_delay -clock axi_clk 2.5 [get_ports { \
	s_axi_awready s_axi_wready s_axi_bresp[*] s_axi_bvalid \
	s_axi_arready s_axi_rdata[*] s_axi_rresp[*] s_axi_rvalid \
	s_axis_pixel_tready m_axis_frame_tdata[*] m_axis_frame_tvalid \
	m_axis_frame_tlast \
}]
