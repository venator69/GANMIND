`timescale 1ns / 1ps

`ifndef GAN_MIND_TOP_V
`define GAN_MIND_TOP_V

`ifndef GAN_SERIAL_AXI_WRAPPER_V
`include "gan_serial_axi_wrapper.v"
`endif

// -----------------------------------------------------------------------------
// gan_mind
// -----------------------------------------------------------------------------
// Thin shell around gan_serial_axi_wrapper so the Vivado project can reference
// a single canonical top (helps when the wrapper is packaged as IP and also
// allows for future interconnect glue if needed).
// -----------------------------------------------------------------------------
module gan_mind (
    input  wire         axi_aclk,
    input  wire         axi_aresetn,
    // AXI4-Lite control slave
    input  wire [5:0]   s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [5:0]   s_axi_araddr,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,
    // AXI-Stream pixel ingress
    input  wire [15:0]  s_axis_pixel_tdata,
    input  wire         s_axis_pixel_tvalid,
    output wire         s_axis_pixel_tready,
    input  wire         s_axis_pixel_tlast,
    // AXI-Stream generated frame egress
    output wire [15:0]  m_axis_frame_tdata,
    output wire         m_axis_frame_tvalid,
    input  wire         m_axis_frame_tready,
    output wire         m_axis_frame_tlast
);

    gan_serial_axi_wrapper u_gan_serial_axi (
        .axi_aclk            (axi_aclk),
        .axi_aresetn         (axi_aresetn),
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),
        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),
        .s_axis_pixel_tdata  (s_axis_pixel_tdata),
        .s_axis_pixel_tvalid (s_axis_pixel_tvalid),
        .s_axis_pixel_tready (s_axis_pixel_tready),
        .s_axis_pixel_tlast  (s_axis_pixel_tlast),
        .m_axis_frame_tdata  (m_axis_frame_tdata),
        .m_axis_frame_tvalid (m_axis_frame_tvalid),
        .m_axis_frame_tready (m_axis_frame_tready),
        .m_axis_frame_tlast  (m_axis_frame_tlast)
    );

endmodule

`endif // GAN_MIND_TOP_V
