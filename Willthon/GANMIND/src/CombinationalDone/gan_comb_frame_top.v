`timescale 1ns / 1ps

// ----------------------------------------------------------------------------
// gan_comb_frame_top
// ----------------------------------------------------------------------------
// Variant of gan_comb_top that accepts an already flattened 28x28 sample frame
// instead of loading it from a mem file. This is useful for higher-level
// environments that generate their own fixtures but still want the convenience
// of an auto-driven GAN pipeline (no serialized pixel handshakes, just provide
// the frame, assert start, and wait for done).
// ----------------------------------------------------------------------------
module gan_comb_frame_top #(
    parameter integer PIXEL_COUNT   = 28 * 28,
    parameter bit     ENABLE_VERBOSE = 1'b0
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    // Application supplies the frame directly
    input  wire [16*PIXEL_COUNT-1:0] sample_flat,
    input  wire                      sample_valid,
    // Status / control
    output wire                      sample_ready,
    output wire                      busy,
    output wire                      done,
    // GAN outputs
    output wire                      disc_fake_is_real,
    output wire                      disc_real_is_real,
    output wire signed [15:0]        disc_fake_score,
    output wire signed [15:0]        disc_real_score,
    output wire [16*PIXEL_COUNT-1:0] generated_frame_flat,
    output wire                      generated_frame_valid,
    output wire [16*PIXEL_COUNT-1:0] latched_sample_flat,
    output wire                      latched_sample_valid
);
    // ---------------------------------------------------------------------
    // Local storage of the provided sample
    // ---------------------------------------------------------------------
    reg [16*PIXEL_COUNT-1:0] sample_buffer;
    reg                      sample_buffer_valid;

    assign latched_sample_flat  = sample_buffer;
    assign latched_sample_valid = sample_buffer_valid;

    function automatic [15:0] sample_word(input integer idx);
        sample_word = sample_buffer[(idx+1)*16-1 -: 16];
    endfunction

    // ---------------------------------------------------------------------
    // gan_serial_top instance (unchanged datapath)
    // ---------------------------------------------------------------------
    reg  pixel_bit;
    reg  pixel_valid;
    wire pixel_ready;
    reg  gan_start_pulse;

    wire gan_busy;
    wire gan_done;
    wire frame_ready;

    gan_serial_top u_gan_serial (
        .clk                  (clk),
        .rst                  (rst),
        .pixel_bit            (pixel_bit),
        .pixel_bit_valid      (pixel_valid),
        .pixel_bit_ready      (pixel_ready),
        .start                (gan_start_pulse),
        .busy                 (gan_busy),
        .done                 (gan_done),
        .disc_fake_is_real    (disc_fake_is_real),
        .disc_real_is_real    (disc_real_is_real),
        .disc_fake_score      (disc_fake_score),
        .disc_real_score      (disc_real_score),
        .generated_frame_flat (generated_frame_flat),
        .generated_frame_valid(generated_frame_valid),
        .frame_ready          (frame_ready)
    );

    // ---------------------------------------------------------------------
    // Controller: latch sample, stream pixels, trigger GAN
    // ---------------------------------------------------------------------
    localparam STATE_IDLE   = 3'd0;
    localparam STATE_STREAM = 3'd1;
    localparam STATE_WAIT   = 3'd2;
    localparam STATE_RUN    = 3'd3;

    reg [2:0] state;
    reg [9:0] pixel_idx;
    reg       verbose_logging;

    initial begin
        verbose_logging = ENABLE_VERBOSE;
        if ($test$plusargs("frame_debug")) begin
            verbose_logging = 1'b1;
            $display("[gan_comb_frame_top] Verbose logging enabled via +frame_debug");
        end
    end

    assign busy         = (state != STATE_IDLE) | gan_busy;
    assign done         = (state == STATE_RUN) & gan_done;
    assign sample_ready = (state == STATE_IDLE);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state               <= STATE_IDLE;
            pixel_idx           <= 0;
            pixel_bit           <= 1'b0;
            pixel_valid         <= 1'b0;
            gan_start_pulse     <= 1'b0;
            sample_buffer       <= {16*PIXEL_COUNT{1'b0}};
            sample_buffer_valid <= 1'b0;
        end else begin
            pixel_valid     <= 1'b0;
            gan_start_pulse <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    sample_buffer_valid <= 1'b0;
                    pixel_idx           <= 0;
                    if (start && sample_valid) begin
                        sample_buffer       <= sample_flat;
                        sample_buffer_valid <= 1'b1;
                        state               <= STATE_STREAM;
                        if (verbose_logging)
                            $display("[gan_comb_frame_top] Sample accepted, starting serialization @%0t", $time);
                    end
                end

                STATE_STREAM: begin
                    pixel_bit   <= |sample_word(pixel_idx);
                    pixel_valid <= 1'b1;
                    if (pixel_ready) begin
                        if (pixel_idx == PIXEL_COUNT-1) begin
                            state <= STATE_WAIT;
                            if (verbose_logging)
                                $display("[gan_comb_frame_top] Completed serialization of %0d pixels @%0t", PIXEL_COUNT, $time);
                        end else begin
                            pixel_idx <= pixel_idx + 1'b1;
                        end
                    end
                end

                STATE_WAIT: begin
                    if (frame_ready) begin
                        gan_start_pulse <= 1'b1;
                        state           <= STATE_RUN;
                        if (verbose_logging)
                            $display("[gan_comb_frame_top] Frame loader ready; launching GAN pipeline @%0t", $time);
                    end
                end

                STATE_RUN: begin
                    if (gan_done) begin
                        state <= STATE_IDLE;
                        if (verbose_logging)
                            $display("[gan_comb_frame_top] GAN pipeline done @%0t", $time);
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
