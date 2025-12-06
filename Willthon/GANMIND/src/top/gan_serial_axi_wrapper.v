`timescale 1ns / 1ps

`ifndef GAN_SERIAL_AXI_WRAPPER_V
`define GAN_SERIAL_AXI_WRAPPER_V

`ifndef GAN_SERIAL_TOP_V
`include "gan_serial_top.v"
`endif

// -----------------------------------------------------------------------------
// gan_serial_axi_wrapper
// -----------------------------------------------------------------------------
// AXI4-Lite control plane + AXI-Stream data movers placed around gan_serial_top
// so the block can drop straight into a Zynq/PYNQ block design without exposing
// thousands of discrete I/O pins.
//
// Register map (32-bit words, little endian):
//   0x00 CTRL   [0] write 1 to launch a run (one-cycle start pulse)
//   0x04 STATUS [0] busy, [1] done(sticky), [2] frame_ready, [3] gen_frame_valid,
//                [4] disc_fake_is_real, [5] disc_real_is_real
//   0x08 FAKE_SCORE  signed 16-bit discriminator score for generated frame
//   0x0C REAL_SCORE  signed 16-bit discriminator score for sampled real data
//   0x10 FRAME_WORDS number of 16-bit words emitted on the frame AXI-Stream (784)
// Control/status live entirely in AXI-Lite; pixel ingress and frame egress use
// AXI-Stream interfaces so software can DMA bursts without touching per-bit pins.
// -----------------------------------------------------------------------------
module gan_serial_axi_wrapper #(
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer S_AXIS_TDATA_WIDTH = 16,
    parameter integer M_AXIS_TDATA_WIDTH = 16
) (
    input  wire                        axi_aclk,
    input  wire                        axi_aresetn,
    // AXI4-Lite slave
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                        s_axi_awvalid,
    output wire                        s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                        s_axi_wvalid,
    output wire                        s_axi_wready,
    output wire [1:0]                 s_axi_bresp,
    output wire                        s_axi_bvalid,
    input  wire                        s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                        s_axi_arvalid,
    output wire                        s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                 s_axi_rresp,
    output wire                        s_axi_rvalid,
    input  wire                        s_axi_rready,
    // AXI-Stream slave: serialized pixel ingress (LSB used)
    input  wire [S_AXIS_TDATA_WIDTH-1:0] s_axis_pixel_tdata,
    input  wire                        s_axis_pixel_tvalid,
    output wire                        s_axis_pixel_tready,
    input  wire                        s_axis_pixel_tlast,
    // AXI-Stream master: generated frame as 16-bit stream
    output wire [M_AXIS_TDATA_WIDTH-1:0] m_axis_frame_tdata,
    output wire                        m_axis_frame_tvalid,
    input  wire                        m_axis_frame_tready,
    output wire                        m_axis_frame_tlast
);

    // -------------------------------------------------------------------------
    // Parameter sanity
    // -------------------------------------------------------------------------
    function integer calc_clog2;
        input integer value;
        integer i;
        begin
            calc_clog2 = 0;
            for (i = value-1; i > 0; i = i >> 1)
                calc_clog2 = calc_clog2 + 1;
        end
    endfunction

    localparam integer PIXEL_WORD_WIDTH  = 16;
    localparam integer FRAME_WORD_COUNT  = 784;
    localparam integer FRAME_BUFFER_BITS = PIXEL_WORD_WIDTH * FRAME_WORD_COUNT;

`ifndef SYNTHESIS
    initial begin
        if (M_AXIS_TDATA_WIDTH != PIXEL_WORD_WIDTH)
            $error("gan_serial_axi_wrapper: M_AXIS_TDATA_WIDTH must be %0d", PIXEL_WORD_WIDTH);
        if (S_AXIS_TDATA_WIDTH <= 0)
            $error("gan_serial_axi_wrapper: S_AXIS_TDATA_WIDTH must be > 0");
        if (C_S_AXI_ADDR_WIDTH <= calc_clog2(C_S_AXI_DATA_WIDTH/8))
            $error("gan_serial_axi_wrapper: C_S_AXI_ADDR_WIDTH must exceed byte select bits");
    end
`endif

    // -------------------------------------------------------------------------
    // AXI4-Lite infrastructure (single-beat transactions)
    // -------------------------------------------------------------------------
    localparam integer ADDR_LSB = calc_clog2(C_S_AXI_DATA_WIDTH/8);
    localparam integer REG_ADDR_WIDTH = (C_S_AXI_ADDR_WIDTH > ADDR_LSB) ? (C_S_AXI_ADDR_WIDTH - ADDR_LSB) : 1;

    reg  axi_awready_int;
    reg  axi_wready_int;
    reg  [1:0] axi_bresp_int;
    reg  axi_bvalid_int;
    reg  axi_arready_int;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr_int;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr_int;
    reg  [C_S_AXI_DATA_WIDTH-1:0] axi_rdata_int;
    reg  [1:0] axi_rresp_int;
    reg  axi_rvalid_int;

    assign s_axi_awready = axi_awready_int;
    assign s_axi_wready  = axi_wready_int;
    assign s_axi_bresp   = axi_bresp_int;
    assign s_axi_bvalid  = axi_bvalid_int;
    assign s_axi_arready = axi_arready_int;
    assign s_axi_rdata   = axi_rdata_int;
    assign s_axi_rresp   = axi_rresp_int;
    assign s_axi_rvalid  = axi_rvalid_int;

    wire axi_reset = ~axi_aresetn;

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_awready_int <= 1'b0;
        end else begin
            if (!axi_awready_int && s_axi_awvalid && s_axi_wvalid)
                axi_awready_int <= 1'b1;
            else
                axi_awready_int <= 1'b0;
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_awaddr_int <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else if (!axi_awready_int && s_axi_awvalid && s_axi_wvalid) begin
            axi_awaddr_int <= s_axi_awaddr;
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_wready_int <= 1'b0;
        end else begin
            if (!axi_wready_int && s_axi_wvalid && s_axi_awvalid)
                axi_wready_int <= 1'b1;
            else
                axi_wready_int <= 1'b0;
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_bvalid_int <= 1'b0;
            axi_bresp_int  <= 2'b00;
        end else begin
            if (axi_awready_int && s_axi_awvalid && !axi_bvalid_int && axi_wready_int && s_axi_wvalid) begin
                axi_bvalid_int <= 1'b1;
                axi_bresp_int  <= 2'b00;
            end else if (axi_bvalid_int && s_axi_bready) begin
                axi_bvalid_int <= 1'b0;
            end
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_arready_int <= 1'b0;
            axi_araddr_int  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (!axi_arready_int && s_axi_arvalid) begin
                axi_arready_int <= 1'b1;
                axi_araddr_int  <= s_axi_araddr;
            end else begin
                axi_arready_int <= 1'b0;
            end
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_rvalid_int <= 1'b0;
            axi_rresp_int  <= 2'b00;
        end else begin
            if (axi_arready_int && s_axi_arvalid && !axi_rvalid_int) begin
                axi_rvalid_int <= 1'b1;
                axi_rresp_int  <= 2'b00;
            end else if (axi_rvalid_int && s_axi_rready) begin
                axi_rvalid_int <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Control/status registers
    // -------------------------------------------------------------------------
    localparam integer REG_CONTROL     = 0;
    localparam integer REG_STATUS      = 1;
    localparam integer REG_FAKE_SCORE  = 2;
    localparam integer REG_REAL_SCORE  = 3;
    localparam integer REG_FRAME_WORDS = 4;

    wire write_fire = axi_awready_int && s_axi_awvalid && s_axi_wvalid && axi_wready_int;
    wire read_fire  = axi_arready_int && s_axi_arvalid;

    wire [REG_ADDR_WIDTH-1:0] wr_addr_index = axi_awaddr_int[C_S_AXI_ADDR_WIDTH-1:ADDR_LSB];
    wire [REG_ADDR_WIDTH-1:0] rd_addr_index = axi_araddr_int[C_S_AXI_ADDR_WIDTH-1:ADDR_LSB];

    reg start_latch;
    reg start_pulse_reg;
    reg done_flag;
    reg frame_stream_consumed;

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            start_latch          <= 1'b0;
            start_pulse_reg      <= 1'b0;
            done_flag            <= 1'b0;
        end else begin
            start_pulse_reg <= 1'b0;

            if (write_fire && (wr_addr_index == REG_CONTROL)) begin
                if (s_axi_wstrb[0] && s_axi_wdata[0])
                    start_latch <= 1'b1;
            end

            if (start_latch) begin
                start_pulse_reg <= 1'b1;
                start_latch     <= 1'b0;
                done_flag       <= 1'b0;
            end

            if (gan_done)
                done_flag <= 1'b1;
        end
    end

    wire start_pulse = start_pulse_reg;

    // -------------------------------------------------------------------------
    // Connection to gan_serial_top
    // -------------------------------------------------------------------------
    wire pixel_bit      = s_axis_pixel_tdata[0];
    wire pixel_bit_valid= s_axis_pixel_tvalid;
    wire pixel_bit_ready;

    assign s_axis_pixel_tready = pixel_bit_ready;
    // tlast is unused internally; tie off to keep lint silent.
    wire unused_tlast;
    assign unused_tlast = s_axis_pixel_tlast;

    wire                   gan_busy;
    wire                   gan_done;
    wire                   gan_frame_ready;
    wire                   gan_generated_valid;
    wire [FRAME_BUFFER_BITS-1:0] gan_generated_frame_flat;
    wire                   disc_fake_is_real;
    wire                   disc_real_is_real;
    wire signed [15:0]     disc_fake_score;
    wire signed [15:0]     disc_real_score;

    gan_serial_top u_gan_serial_top (
        .clk                   (axi_aclk),
        .rst                   (axi_reset),
        .pixel_bit             (pixel_bit),
        .pixel_bit_valid       (pixel_bit_valid),
        .pixel_bit_ready       (pixel_bit_ready),
        .start                 (start_pulse),
        .busy                  (gan_busy),
        .done                  (gan_done),
        .disc_fake_is_real     (disc_fake_is_real),
        .disc_real_is_real     (disc_real_is_real),
        .disc_fake_score       (disc_fake_score),
        .disc_real_score       (disc_real_score),
        .generated_frame_flat  (gan_generated_frame_flat),
        .generated_frame_valid (gan_generated_valid),
        .frame_ready           (gan_frame_ready)
    );

    // -------------------------------------------------------------------------
    // AXI-Stream master: serialize generated_frame_flat into 16-bit samples
    // -------------------------------------------------------------------------
    localparam integer FRAME_INDEX_WIDTH = calc_clog2(FRAME_WORD_COUNT);

    reg [FRAME_BUFFER_BITS-1:0] frame_stream_buffer;
    reg                        frame_stream_active;
    reg [FRAME_INDEX_WIDTH-1:0] frame_stream_idx;

    wire frame_stream_idle = !frame_stream_active;

    always @(posedge axi_aclk) begin
        if (axi_reset || start_pulse) begin
            frame_stream_buffer  <= {FRAME_BUFFER_BITS{1'b0}};
            frame_stream_active  <= 1'b0;
            frame_stream_idx     <= {FRAME_INDEX_WIDTH{1'b0}};
            frame_stream_consumed<= 1'b0;
        end else begin
            if (frame_stream_idle && gan_generated_valid && !frame_stream_consumed) begin
                frame_stream_buffer  <= gan_generated_frame_flat;
                frame_stream_active  <= 1'b1;
                frame_stream_idx     <= {FRAME_INDEX_WIDTH{1'b0}};
                frame_stream_consumed<= 1'b1;
            end else if (frame_stream_active && m_axis_frame_tvalid && m_axis_frame_tready) begin
                if (frame_stream_idx == FRAME_WORD_COUNT-1) begin
                    frame_stream_active <= 1'b0;
                end else begin
                    frame_stream_idx <= frame_stream_idx + 1'b1;
                end
            end
        end
    end

    wire [PIXEL_WORD_WIDTH-1:0] current_frame_word = frame_stream_buffer[(frame_stream_idx+1)*PIXEL_WORD_WIDTH-1 -: PIXEL_WORD_WIDTH];

    assign m_axis_frame_tvalid = frame_stream_active;
    assign m_axis_frame_tdata  = frame_stream_active ? current_frame_word : {M_AXIS_TDATA_WIDTH{1'b0}};
    assign m_axis_frame_tlast  = frame_stream_active && (frame_stream_idx == FRAME_WORD_COUNT-1);

    // -------------------------------------------------------------------------
    // AXI-Lite readback multiplexor
    // -------------------------------------------------------------------------
    wire [31:0] status_word = {
        26'd0,
        disc_real_is_real,
        disc_fake_is_real,
        gan_generated_valid,
        gan_frame_ready,
        done_flag,
        gan_busy
    };

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_rdata_int <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end else if (read_fire) begin
            case (rd_addr_index)
                REG_CONTROL:     axi_rdata_int <= 32'd0;
                REG_STATUS:      axi_rdata_int <= status_word;
                REG_FAKE_SCORE:  axi_rdata_int <= {{16{disc_fake_score[15]}}, disc_fake_score};
                REG_REAL_SCORE:  axi_rdata_int <= {{16{disc_real_score[15]}}, disc_real_score};
                REG_FRAME_WORDS: axi_rdata_int <= FRAME_WORD_COUNT;
                default:         axi_rdata_int <= 32'hDEAD_BEEF;
            endcase
        end
    end

endmodule

`endif // GAN_SERIAL_AXI_WRAPPER_V
