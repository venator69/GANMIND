`timescale 1ns / 1ps

`include "CombinationalDone/combinational_done_block.v"
`include "CombinationalDone/gan_comb_top.v"
`include "CombinationalDone/gan_comb_frame_top.v"

// -----------------------------------------------------------------------------
// Lightweight stub for gan_serial_top so CombinationalDone blocks can be
// unit-tested without pulling in the full GAN pipeline. The stub tracks the
// serialized pixel stream and emulates the ready/done handshakes.
// -----------------------------------------------------------------------------
module gan_serial_top (
    input  wire clk,
    input  wire rst,
    input  wire pixel_bit,
    input  wire pixel_bit_valid,
    output wire pixel_bit_ready,
    input  wire start,
    output reg  busy,
    output reg  done,
    output reg  disc_fake_is_real,
    output reg  disc_real_is_real,
    output reg  signed [15:0] disc_fake_score,
    output reg  signed [15:0] disc_real_score,
    output reg  [16*28*28-1:0] generated_frame_flat,
    output reg                 generated_frame_valid,
    output reg                 frame_ready
);
    localparam integer PIXEL_COUNT = 28 * 28;
    localparam integer FLAT_WIDTH  = 16 * PIXEL_COUNT;

    reg pixel_ready_reg;
    reg [9:0] stream_count;
    reg        run_active;
    reg [3:0]  run_counter;

    reg [PIXEL_COUNT-1:0] pixel_log;
    reg                   pixel_log_valid;
    integer               stream_events;
    integer               start_events;
    integer               done_events;

    assign pixel_bit_ready = pixel_ready_reg;

    initial begin
        pixel_ready_reg       = 1'b1;
        stream_count          = 0;
        run_active            = 1'b0;
        run_counter           = 0;
        busy                  = 1'b0;
        done                  = 1'b0;
        disc_fake_is_real     = 1'b0;
        disc_real_is_real     = 1'b1;
        disc_fake_score       = 16'sd0;
        disc_real_score       = 16'sd0;
        generated_frame_flat  = {FLAT_WIDTH{1'b0}};
        generated_frame_valid = 1'b0;
        frame_ready           = 1'b0;
        pixel_log             = {PIXEL_COUNT{1'b0}};
        pixel_log_valid       = 1'b0;
        stream_events         = 0;
        start_events          = 0;
        done_events           = 0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_ready_reg       <= 1'b1;
            stream_count          <= 0;
            run_active            <= 1'b0;
            run_counter           <= 0;
            busy                  <= 1'b0;
            done                  <= 1'b0;
            generated_frame_valid <= 1'b0;
            frame_ready           <= 1'b0;
            pixel_log_valid       <= 1'b0;
        end else begin
            done                  <= 1'b0;
            generated_frame_valid <= 1'b0;

            if (pixel_bit_valid && pixel_ready_reg) begin
                pixel_log[stream_count] <= pixel_bit;
                stream_count            <= stream_count + 1'b1;
                stream_events           <= stream_events + 1;
                if (stream_count == PIXEL_COUNT-1) begin
                    frame_ready     <= 1'b1;
                    pixel_ready_reg <= 1'b0;
                    pixel_log_valid <= 1'b1;
                end
            end

            if (start) begin
                start_events <= start_events + 1;
                if (!frame_ready)
                    $fatal(1, "[gan_serial_top_stub] start asserted before frame_ready");
                busy            <= 1'b1;
                run_active      <= 1'b1;
                run_counter     <= 4'd3;
                frame_ready     <= 1'b0;
                pixel_ready_reg <= 1'b1;
                stream_count    <= 0;
            end

            if (run_active) begin
                if (run_counter == 0) begin
                    run_active            <= 1'b0;
                    busy                  <= 1'b0;
                    done                  <= 1'b1;
                    done_events           <= done_events + 1;
                    generated_frame_valid <= 1'b1;
                end else begin
                    run_counter <= run_counter - 1'b1;
                end
            end
        end
    end
endmodule

// -----------------------------------------------------------------------------
// Testbench exercising combinational_done_block, gan_comb_top, and
// gan_comb_frame_top using the stub above.
// -----------------------------------------------------------------------------
module combinational_done_tb;
    localparam integer PIXEL_COUNT           = 28 * 28;
    localparam integer MINI_COUNT            = 4;
    localparam string  SAMPLE_MEM_PATH       = "src/DigitIdentificationTest/digit_identifier_sample.mem";
    localparam string  EXPECTED_MEM_PATH     = "src/DigitIdentificationTest/digit_identifier_expected.mem";

    reg clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Reference fixtures ----------------------------------------------------
    reg [15:0] canonical_sample   [0:PIXEL_COUNT-1];
    reg [PIXEL_COUNT-1:0] expected_stream_bits;
    reg [16*PIXEL_COUNT-1:0] canonical_sample_flat;

    reg [15:0] mini_sample_mem   [0:MINI_COUNT-1];
    reg [15:0] mini_expected_mem [0:MINI_COUNT-1];
    reg [16*MINI_COUNT-1:0] mini_sample_flat_golden;
    reg [16*MINI_COUNT-1:0] mini_expected_flat_golden;

    reg ref_data_ready;

    integer idx;
    initial begin : init_reference_data
        ref_data_ready = 1'b0;
        $readmemh(SAMPLE_MEM_PATH, canonical_sample);
        for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
            canonical_sample_flat[(idx+1)*16-1 -: 16] = canonical_sample[idx];
            expected_stream_bits[idx] = |canonical_sample[idx];
        end

        $readmemh("src/CombinationalDone/testdata/simple_sample.mem", mini_sample_mem);
        $readmemh("src/CombinationalDone/testdata/simple_expected.mem", mini_expected_mem);
        for (idx = 0; idx < MINI_COUNT; idx = idx + 1) begin
            mini_sample_flat_golden[(idx+1)*16-1 -: 16]   = mini_sample_mem[idx];
            mini_expected_flat_golden[(idx+1)*16-1 -: 16] = mini_expected_mem[idx];
        end
        ref_data_ready = 1'b1;
    end

    // Small combinational block instance -----------------------------------
    wire [16*MINI_COUNT-1:0] mini_sample_flat;
    wire [16*MINI_COUNT-1:0] mini_expected_flat;
    wire                     mini_has_expected;
    wire                     mini_data_valid;

    combinational_done_block #(
        .PIXEL_COUNT    (MINI_COUNT),
        .SAMPLE_MEM_PATH("src/CombinationalDone/testdata/simple_sample.mem"),
        .EXPECTED_MEM_PATH("src/CombinationalDone/testdata/simple_expected.mem")
    ) u_comb_small (
        .sample_flat (mini_sample_flat),
        .expected_flat(mini_expected_flat),
        .has_expected(mini_has_expected),
        .data_valid  (mini_data_valid)
    );

    // gan_comb_top instance -------------------------------------------------
    reg  rst_comb_top;
    reg  start_comb_top;
    wire comb_top_busy;
    wire comb_top_done;
    wire comb_top_disc_fake_is_real;
    wire comb_top_disc_real_is_real;
    wire signed [15:0] comb_top_disc_fake_score;
    wire signed [15:0] comb_top_disc_real_score;
    wire [16*PIXEL_COUNT-1:0] comb_top_generated_flat;
    wire                      comb_top_generated_valid;
    wire [16*PIXEL_COUNT-1:0] comb_top_sample_flat;

    gan_comb_top u_gan_comb_top (
        .clk                  (clk),
        .rst                  (rst_comb_top),
        .start                (start_comb_top),
        .busy                 (comb_top_busy),
        .done                 (comb_top_done),
        .disc_fake_is_real    (comb_top_disc_fake_is_real),
        .disc_real_is_real    (comb_top_disc_real_is_real),
        .disc_fake_score      (comb_top_disc_fake_score),
        .disc_real_score      (comb_top_disc_real_score),
        .generated_frame_flat (comb_top_generated_flat),
        .generated_frame_valid(comb_top_generated_valid),
        .sample_flat          (comb_top_sample_flat)
    );

    // gan_comb_frame_top instance ------------------------------------------
    reg  rst_frame_top;
    reg  start_frame_top;
    reg  frame_sample_valid;
    wire frame_sample_ready;
    reg [16*PIXEL_COUNT-1:0] frame_sample_flat;
    wire frame_busy;
    wire frame_done;
    wire frame_disc_fake_is_real;
    wire frame_disc_real_is_real;
    wire signed [15:0] frame_disc_fake_score;
    wire signed [15:0] frame_disc_real_score;
    wire [16*PIXEL_COUNT-1:0] frame_generated_flat;
    wire                      frame_generated_valid;
    wire [16*PIXEL_COUNT-1:0] frame_latched_sample_flat;
    wire                      frame_latched_sample_valid;

    gan_comb_frame_top u_gan_comb_frame_top (
        .clk                  (clk),
        .rst                  (rst_frame_top),
        .start                (start_frame_top),
        .sample_flat          (frame_sample_flat),
        .sample_valid         (frame_sample_valid),
        .sample_ready         (frame_sample_ready),
        .busy                 (frame_busy),
        .done                 (frame_done),
        .disc_fake_is_real    (frame_disc_fake_is_real),
        .disc_real_is_real    (frame_disc_real_is_real),
        .disc_fake_score      (frame_disc_fake_score),
        .disc_real_score      (frame_disc_real_score),
        .generated_frame_flat (frame_generated_flat),
        .generated_frame_valid(frame_generated_valid),
        .latched_sample_flat  (frame_latched_sample_flat),
        .latched_sample_valid (frame_latched_sample_valid)
    );

    // Test sequencing -------------------------------------------------------
    initial begin
        rst_comb_top       = 1'b1;
        rst_frame_top      = 1'b1;
        start_comb_top     = 1'b0;
        start_frame_top    = 1'b0;
        frame_sample_valid = 1'b0;
        frame_sample_flat  = {16*PIXEL_COUNT{1'b0}};

        wait (ref_data_ready);
        frame_sample_flat = canonical_sample_flat;

        test_combinational_done_block();
        test_gan_comb_top_stream();
        test_gan_comb_frame_top_path();

        $display("[TB] All CombinationalDone block tests PASSED");
        #20;
        $finish;
    end

    // Tasks ----------------------------------------------------------------
    task test_combinational_done_block;
        integer idx_local;
        begin
            wait (mini_data_valid);
            if (!mini_has_expected)
                $fatal(1, "[TB] Mini combinational block failed to detect expected snapshot");
            for (idx_local = 0; idx_local < MINI_COUNT; idx_local = idx_local + 1) begin
                if (mini_sample_flat[(idx_local+1)*16-1 -: 16] !== mini_sample_flat_golden[(idx_local+1)*16-1 -: 16])
                    $fatal(1, "[TB] Mini sample mismatch at idx %0d", idx_local);
                if (mini_expected_flat[(idx_local+1)*16-1 -: 16] !== mini_expected_flat_golden[(idx_local+1)*16-1 -: 16])
                    $fatal(1, "[TB] Mini expected mismatch at idx %0d", idx_local);
            end
            $display("[TB] combinational_done_block mini ROM test passed");
        end
    endtask

    task test_gan_comb_top_stream;
        integer idx_local;
        integer mismatches;
        reg [PIXEL_COUNT-1:0] observed_bits;
        begin
            rst_comb_top   = 1'b1;
            start_comb_top = 1'b0;
            repeat (5) @(posedge clk);
            rst_comb_top = 1'b0;
            repeat (5) @(posedge clk);
            start_comb_top = 1'b1;
            @(posedge clk);
            start_comb_top = 1'b0;

            wait (u_gan_comb_top.u_gan_serial.pixel_log_valid);
            observed_bits = u_gan_comb_top.u_gan_serial.pixel_log;
            mismatches = 0;
            for (idx_local = 0; idx_local < PIXEL_COUNT; idx_local = idx_local + 1) begin
                if (observed_bits[idx_local] !== expected_stream_bits[idx_local])
                    mismatches = mismatches + 1;
            end
            if (mismatches != 0)
                $fatal(1, "[TB] gan_comb_top serialized %0d mismatched bits", mismatches);

            wait (comb_top_done);
            if (u_gan_comb_top.u_gan_serial.stream_events != PIXEL_COUNT)
                $fatal(1, "[TB] gan_comb_top streamed %0d pixels (expected %0d)", u_gan_comb_top.u_gan_serial.stream_events, PIXEL_COUNT);
            if (u_gan_comb_top.u_gan_serial.start_events != 1)
                $fatal(1, "[TB] gan_comb_top issued %0d start events", u_gan_comb_top.u_gan_serial.start_events);
            if (u_gan_comb_top.u_gan_serial.done_events != 1)
                $fatal(1, "[TB] gan_comb_top saw %0d done events", u_gan_comb_top.u_gan_serial.done_events);
            $display("[TB] gan_comb_top stream/handshake test passed");
        end
    endtask

    task test_gan_comb_frame_top_path;
        integer idx_local;
        integer mismatches;
        reg [PIXEL_COUNT-1:0] observed_bits;
        begin
            rst_frame_top      = 1'b1;
            start_frame_top    = 1'b0;
            frame_sample_valid = 1'b0;
            repeat (5) @(posedge clk);
            rst_frame_top = 1'b0;
            wait (frame_sample_ready);
            frame_sample_valid = 1'b1;
            start_frame_top    = 1'b1;
            @(posedge clk);
            frame_sample_valid = 1'b0;
            start_frame_top    = 1'b0;

            wait (u_gan_comb_frame_top.u_gan_serial.pixel_log_valid);
            observed_bits = u_gan_comb_frame_top.u_gan_serial.pixel_log;
            mismatches = 0;
            for (idx_local = 0; idx_local < PIXEL_COUNT; idx_local = idx_local + 1) begin
                if (observed_bits[idx_local] !== expected_stream_bits[idx_local])
                    mismatches = mismatches + 1;
            end
            if (mismatches != 0)
                $fatal(1, "[TB] gan_comb_frame_top serialized %0d mismatched bits", mismatches);

            wait (frame_done);
            if (frame_latched_sample_flat !== canonical_sample_flat)
                $fatal(1, "[TB] gan_comb_frame_top failed to latch the provided frame");
            if (!frame_generated_valid)
                $fatal(1, "[TB] gan_comb_frame_top never asserted generated_frame_valid");
            $display("[TB] gan_comb_frame_top frame-path test passed");
        end
    endtask
endmodule
