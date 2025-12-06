`timescale 1ns / 1ps

// ----------------------------------------------------------------------------
// gan_comb_top
// ----------------------------------------------------------------------------
// Wrapper yang mengotomatiskan penyediaan piksel ter-serialisasi untuk
// `gan_serial_top` menggunakan blok ROM kombinational. Cukup berikan pulsa
// `start`, modul ini akan:
//   1. Mengambil seluruh 784 sampel dari `digit_identifier_sample.mem`
//   2. Men-streaming-kan bit serial (1 jika nilai Q8.8 tidak nol)
//   3. Menunggu loader siap, lalu men-trigger pipeline GAN hingga selesai
// Tanpa perlu stimulus testbench manual.
// ----------------------------------------------------------------------------
module gan_comb_top #(
    parameter integer PIXEL_COUNT = 28 * 28
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    output wire busy,
    output wire done,
    output wire disc_fake_is_real,
    output wire disc_real_is_real,
    output wire signed [15:0] disc_fake_score,
    output wire signed [15:0] disc_real_score,
    output wire [16*PIXEL_COUNT-1:0] generated_frame_flat,
    output wire                     generated_frame_valid,
    output wire [16*PIXEL_COUNT-1:0] sample_flat
);
    // ---------------------------------------------------------------------
    // Sample ROM (combinational)
    // ---------------------------------------------------------------------
    wire [16*PIXEL_COUNT-1:0] comb_sample_flat;
    wire [16*PIXEL_COUNT-1:0] comb_expected_flat_unused;
    wire                      comb_has_expected_unused;
    wire                      comb_data_valid;

    combinational_done_block #(
        .PIXEL_COUNT    (PIXEL_COUNT),
        .SAMPLE_MEM_PATH("src/DigitIdentificationTest/digit_identifier_sample.mem"),
        .EXPECTED_MEM_PATH("src/DigitIdentificationTest/digit_identifier_expected.mem")
    ) u_comb_block (
        .sample_flat   (comb_sample_flat),
        .expected_flat (comb_expected_flat_unused),
        .has_expected  (comb_has_expected_unused),
        .data_valid    (comb_data_valid)
    );

    assign sample_flat = comb_sample_flat;

    function automatic [15:0] sample_word(input integer idx);
        sample_word = comb_sample_flat[(idx+1)*16-1 -: 16];
    endfunction

    // ---------------------------------------------------------------------
    // gan_serial_top instance
    // ---------------------------------------------------------------------
    reg pixel_bit;
    reg pixel_valid;
    wire pixel_ready;
    reg gan_start_pulse;

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
    // Simple controller to serialize pixels and trigger GAN run
    // ---------------------------------------------------------------------
    localparam STATE_IDLE   = 3'd0;
    localparam STATE_STREAM = 3'd1;
    localparam STATE_WAIT   = 3'd2;
    localparam STATE_RUN    = 3'd3;

    reg [2:0] state;
    reg [9:0] pixel_idx; // 0..783

    assign busy = (state != STATE_IDLE) | gan_busy;
    assign done = (state == STATE_RUN) & gan_done;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= STATE_IDLE;
            pixel_idx       <= 0;
            pixel_bit       <= 1'b0;
            pixel_valid     <= 1'b0;
            gan_start_pulse <= 1'b0;
        end else begin
            pixel_valid     <= 1'b0;
            gan_start_pulse <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    pixel_idx <= 0;
                    if (start && comb_data_valid) begin
                        state <= STATE_STREAM;
                    end
                end

                STATE_STREAM: begin
                    pixel_bit   <= |sample_word(pixel_idx);
                    pixel_valid <= 1'b1;
                    if (pixel_ready) begin
                        if (pixel_idx == PIXEL_COUNT-1) begin
                            state <= STATE_WAIT;
                        end else begin
                            pixel_idx <= pixel_idx + 1'b1;
                        end
                    end
                end

                STATE_WAIT: begin
                    if (frame_ready) begin
                        gan_start_pulse <= 1'b1;
                        state           <= STATE_RUN;
                    end
                end

                STATE_RUN: begin
                    if (gan_done) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
