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

    reg  [1:0] axi_bresp_int;
    reg  axi_bvalid_int;
    reg  [C_S_AXI_DATA_WIDTH-1:0] axi_rdata_int;
    reg  [1:0] axi_rresp_int;
    reg  axi_rvalid_int;

    reg  write_buf_valid;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] write_buf_addr;
    reg  [C_S_AXI_DATA_WIDTH-1:0] write_buf_data;
    reg  [C_S_AXI_DATA_WIDTH/8-1:0] write_buf_strb;

    reg  read_buf_valid;
    reg  [C_S_AXI_ADDR_WIDTH-1:0] read_buf_addr;

    assign s_axi_awready = (!write_buf_valid && s_axi_wvalid);
    assign s_axi_wready  = (!write_buf_valid && s_axi_awvalid);
    assign s_axi_bresp   = axi_bresp_int;
    assign s_axi_bvalid  = axi_bvalid_int;
    assign s_axi_arready = !read_buf_valid;
    assign s_axi_rdata   = axi_rdata_int;
    assign s_axi_rresp   = axi_rresp_int;
    assign s_axi_rvalid  = axi_rvalid_int;

    wire axi_reset = ~axi_aresetn;

    localparam integer AXIS_COUNTER_WIDTH_INT = calc_clog2(S_AXIS_TDATA_WIDTH + 1);
    localparam integer AXIS_COUNTER_WIDTH = (AXIS_COUNTER_WIDTH_INT == 0) ? 1 : AXIS_COUNTER_WIDTH_INT;
    localparam [AXIS_COUNTER_WIDTH-1:0] AXIS_WORD_SIZE = S_AXIS_TDATA_WIDTH;

    reg [S_AXIS_TDATA_WIDTH-1:0] axis_shift_reg;
    reg [AXIS_COUNTER_WIDTH-1:0] axis_shift_count;
    reg                          axis_tlast_pending;
    reg                          axis_ingress_toggle;

    wire [AXIS_COUNTER_WIDTH-1:0] axis_count_one = {{(AXIS_COUNTER_WIDTH-1){1'b0}}, 1'b1};
    wire axis_shift_empty = (axis_shift_count == {AXIS_COUNTER_WIDTH{1'b0}});

    wire write_buf_push = (!write_buf_valid && s_axi_awvalid && s_axi_wvalid);
    wire write_fire     = write_buf_valid;

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            write_buf_valid <= 1'b0;
            write_buf_addr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            write_buf_data  <= {C_S_AXI_DATA_WIDTH{1'b0}};
            write_buf_strb  <= {C_S_AXI_DATA_WIDTH/8{1'b0}};
        end else begin
            if (write_buf_push) begin
                write_buf_valid <= 1'b1;
                write_buf_addr  <= s_axi_awaddr;
                write_buf_data  <= s_axi_wdata;
                write_buf_strb  <= s_axi_wstrb;
            end else if (write_fire) begin
                write_buf_valid <= 1'b0;
            end
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_bvalid_int <= 1'b0;
            axi_bresp_int  <= 2'b00;
        end else begin
            if (write_fire && !axi_bvalid_int) begin
                axi_bvalid_int <= 1'b1;
                axi_bresp_int  <= 2'b00;
            end else if (axi_bvalid_int && s_axi_bready) begin
                axi_bvalid_int <= 1'b0;
            end
        end
    end

    wire read_buf_push = (!read_buf_valid && s_axi_arvalid);
    wire read_fire     = read_buf_valid && !axi_rvalid_int;

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            read_buf_valid <= 1'b0;
            read_buf_addr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (read_buf_push) begin
                read_buf_valid <= 1'b1;
                read_buf_addr  <= s_axi_araddr;
            end else if (read_fire) begin
                read_buf_valid <= 1'b0;
            end
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axi_rvalid_int <= 1'b0;
            axi_rresp_int  <= 2'b00;
        end else begin
            if (read_fire) begin
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

    wire [REG_ADDR_WIDTH-1:0] wr_addr_index = write_buf_addr[C_S_AXI_ADDR_WIDTH-1:ADDR_LSB];
    wire [REG_ADDR_WIDTH-1:0] rd_addr_index = read_buf_addr[C_S_AXI_ADDR_WIDTH-1:ADDR_LSB];

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
                if (write_buf_strb[0] && write_buf_data[0])
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
    wire pixel_bit;
    wire pixel_bit_valid;
    wire pixel_bit_ready;

    wire axis_last_bit = (axis_shift_count == axis_count_one);
    assign pixel_bit       = axis_shift_reg[0];
    assign pixel_bit_valid = !axis_shift_empty;

    wire bit_fire        = pixel_bit_valid && pixel_bit_ready;
    assign s_axis_pixel_tready = axis_shift_empty || (axis_last_bit && pixel_bit_ready);
    wire axis_word_accept = s_axis_pixel_tvalid && s_axis_pixel_tready;
    wire axis_tlast_fire  = axis_tlast_pending && bit_fire && axis_last_bit;

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axis_shift_reg     <= {S_AXIS_TDATA_WIDTH{1'b0}};
            axis_shift_count   <= {AXIS_COUNTER_WIDTH{1'b0}};
            axis_tlast_pending <= 1'b0;
        end else begin
            if (axis_word_accept) begin
                axis_shift_reg     <= s_axis_pixel_tdata;
                axis_shift_count   <= AXIS_WORD_SIZE;
                axis_tlast_pending <= s_axis_pixel_tlast;
            end else if (bit_fire && !axis_shift_empty) begin
                axis_shift_reg     <= axis_shift_reg >> 1;
                axis_shift_count   <= axis_shift_count - axis_count_one;
                if (axis_last_bit)
                    axis_tlast_pending <= 1'b0;
            end
        end
    end

    always @(posedge axi_aclk) begin
        if (axi_reset) begin
            axis_ingress_toggle <= 1'b0;
        end else if (axis_tlast_fire) begin
            axis_ingress_toggle <= ~axis_ingress_toggle;
        end
    end

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
    reg [FRAME_INDEX_WIDTH-1:0] frame_stream_next_idx;
    reg [FRAME_INDEX_WIDTH-1:0] frame_word_stage_idx;
    reg [PIXEL_WORD_WIDTH-1:0]  frame_word_stage;
    reg                        frame_word_stage_valid;

    wire frame_stream_idle = !frame_stream_active;
    wire frame_output_advance = frame_word_stage_valid && m_axis_frame_tready;

    always @(posedge axi_aclk) begin
        if (axi_reset || start_pulse) begin
            frame_stream_buffer     <= {FRAME_BUFFER_BITS{1'b0}};
            frame_stream_active     <= 1'b0;
            frame_stream_next_idx   <= {FRAME_INDEX_WIDTH{1'b0}};
            frame_word_stage        <= {PIXEL_WORD_WIDTH{1'b0}};
            frame_word_stage_idx    <= {FRAME_INDEX_WIDTH{1'b0}};
            frame_word_stage_valid  <= 1'b0;
            frame_stream_consumed   <= 1'b0;
        end else begin
            if (frame_stream_idle && gan_generated_valid && !frame_stream_consumed) begin
                frame_stream_buffer     <= gan_generated_frame_flat;
                frame_stream_active     <= 1'b1;
                frame_stream_next_idx   <= {FRAME_INDEX_WIDTH{1'b0}};
                frame_word_stage_valid  <= 1'b0;
                frame_stream_consumed   <= 1'b1;
            end

            if (frame_stream_active && !frame_word_stage_valid) begin
                frame_word_stage       <= frame_stream_buffer[(frame_stream_next_idx+1)*PIXEL_WORD_WIDTH-1 -: PIXEL_WORD_WIDTH];
                frame_word_stage_idx   <= frame_stream_next_idx;
                frame_word_stage_valid <= 1'b1;
                if (frame_stream_next_idx != FRAME_WORD_COUNT-1)
                    frame_stream_next_idx <= frame_stream_next_idx + 1'b1;
            end

            if (frame_output_advance) begin
                frame_word_stage_valid <= 1'b0;
                if (frame_word_stage_idx == FRAME_WORD_COUNT-1)
                    frame_stream_active <= 1'b0;
            end

            if (!frame_stream_active && !frame_word_stage_valid)
                frame_stream_next_idx <= {FRAME_INDEX_WIDTH{1'b0}};
        end
    end

    assign m_axis_frame_tvalid = frame_stream_active && frame_word_stage_valid;
    assign m_axis_frame_tdata  = frame_word_stage_valid ? frame_word_stage : {M_AXIS_TDATA_WIDTH{1'b0}};
    assign m_axis_frame_tlast  = frame_stream_active && frame_word_stage_valid && (frame_word_stage_idx == FRAME_WORD_COUNT-1);

    // -------------------------------------------------------------------------
    // AXI-Lite readback multiplexor
    // -------------------------------------------------------------------------
    wire [31:0] status_word = {
        25'd0,
        axis_ingress_toggle,
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