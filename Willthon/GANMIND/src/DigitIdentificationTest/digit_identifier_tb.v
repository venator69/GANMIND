`timescale 1ns / 1ps

`ifndef COMBINATIONAL_DONE_BLOCK_V
`define COMBINATIONAL_DONE_BLOCK_V
`include "../CombinationalDone/combinational_done_block.v"
`endif

`ifndef GAN_COMB_TOP_V
`define GAN_COMB_TOP_V
`include "../CombinationalDone/gan_comb_top.v"
`endif

// ============================================================================
// Fast Debug Stub - bypass GAN pipeline entirely
// ============================================================================
module gan_comb_top_stub #(
    parameter integer PIXEL_COUNT = 28 * 28
)(
    input  wire clk,
    input  wire rst,
    input  wire start,
    output reg  busy,
    output reg  done,
    output reg  disc_fake_is_real,
    output reg  disc_real_is_real,
    output reg  signed [15:0] disc_fake_score,
    output reg  signed [15:0] disc_real_score,
    output reg  [16*PIXEL_COUNT-1:0] generated_frame_flat,
    output reg                       generated_frame_valid,
    output reg  [16*PIXEL_COUNT-1:0] sample_flat
);
    reg [2:0] state;
    reg [3:0] countdown;
    reg [16*PIXEL_COUNT-1:0] sample_buf;

    initial begin
        state = 3'd0;
        busy = 1'b0;
        done = 1'b0;
        disc_fake_is_real = 1'b0;
        disc_real_is_real = 1'b1;
        disc_fake_score = 16'sd0;
        disc_real_score = 16'sd256;
        generated_frame_flat = {16*PIXEL_COUNT{1'b0}};
        generated_frame_valid = 1'b0;
        sample_flat = {16*PIXEL_COUNT{1'b0}};
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 3'd0;
            busy <= 1'b0;
            done <= 1'b0;
            generated_frame_valid <= 1'b0;
        end else begin
            done <= 1'b0;
            generated_frame_valid <= 1'b0;

            case (state)
                3'd0: begin
                    if (start) begin
                        sample_buf <= sample_flat;
                        busy <= 1'b1;
                        countdown <= 4'd3;
                        state <= 3'd1;
                    end
                end

                3'd1: begin
                    if (countdown == 0) begin
                        generated_frame_flat <= sample_buf;
                        generated_frame_valid <= 1'b1;
                        done <= 1'b1;
                        busy <= 1'b0;
                        state <= 3'd0;
                    end else begin
                        countdown <= countdown - 1'b1;
                    end
                end

                default: state <= 3'd0;
            endcase
        end
    end
endmodule

// ============================================================================
// Digit Identification Integration Testbench
// ============================================================================
// * Streams a 28x28 frame derived from Willthon/GANMIND/samples/real_images.png
//   into gan_serial_top via the new digit_identifier_sample.mem fixture.
// * Waits for the GAN pipeline to finish, writes the generated frame back to
//   disk, and produces simple similarity metrics so the sample can be inspected
//   by downstream digit identifier pipelines.
// ============================================================================
module digit_identifier_tb;
    localparam integer PIXEL_COUNT        = 28 * 28;
    localparam integer MAX_WAIT_CYCLES    = 1200000000;
    localparam bit     FAST_DEBUG         = 1'b0;
    localparam string  SAMPLE_MEM_PATH    = "src/DigitIdentificationTest/digit_identifier_sample.mem";
    localparam string  EXPECTED_MEM_PATH  = "src/DigitIdentificationTest/digit_identifier_expected.mem";
    localparam string  OUTPUT_MEM_PATH    = "src/DigitIdentificationTest/digit_identifier_generated.mem";
    localparam string  METRICS_LOG_PATH   = "src/DigitIdentificationTest/digit_identifier_metrics.log";
    localparam bit     ENABLE_VCD_DEFAULT = 1'b0;

    reg clk;
    reg rst;
    reg start;

    wire busy;
    wire done;
    wire disc_fake_is_real;
    wire disc_real_is_real;
    wire signed [15:0] disc_fake_score;
    wire signed [15:0] disc_real_score;
    wire [16*PIXEL_COUNT-1:0] generated_frame_flat;
    wire generated_frame_valid;
    wire [16*PIXEL_COUNT-1:0] gan_sample_flat;

    reg [15:0] captured_pixels [0:PIXEL_COUNT-1];

    integer similarity_avg_abs;
    integer similarity_max_abs;
    integer expected_mismatches;

    wire [16*PIXEL_COUNT-1:0] comb_expected_flat;
    wire                      comb_has_expected;
    wire                      comb_data_valid;
    wire [16*PIXEL_COUNT-1:0] comb_sample_unused;

    combinational_done_block #(
        .PIXEL_COUNT    (PIXEL_COUNT),
        .SAMPLE_MEM_PATH("src/DigitIdentificationTest/digit_identifier_sample.mem"),
        .EXPECTED_MEM_PATH("src/DigitIdentificationTest/digit_identifier_expected.mem")
    ) u_comb_done (
        .sample_flat   (comb_sample_unused),
        .expected_flat (comb_expected_flat),
        .has_expected  (comb_has_expected),
        .data_valid    (comb_data_valid)
    );

    // DUT: choose between full GAN or fast stub -----------------------
    generate
        if (!FAST_DEBUG) begin : GEN_FULL_PIPELINE
            gan_comb_top dut (
                .clk                  (clk),
                .rst                  (rst),
                .start                (start),
                .busy                 (busy),
                .done                 (done),
                .disc_fake_is_real    (disc_fake_is_real),
                .disc_real_is_real    (disc_real_is_real),
                .disc_fake_score      (disc_fake_score),
                .disc_real_score      (disc_real_score),
                .generated_frame_flat (generated_frame_flat),
                .generated_frame_valid(generated_frame_valid),
                .sample_flat          (gan_sample_flat)
            );
        end else begin : GEN_FAST_STUB
            initial $display("[TB] FAST_DEBUG enabled – using gan_comb_top_stub");
            gan_comb_top_stub dut (
                .clk                  (clk),
                .rst                  (rst),
                .start                (start),
                .busy                 (busy),
                .done                 (done),
                .disc_fake_is_real    (disc_fake_is_real),
                .disc_real_is_real    (disc_real_is_real),
                .disc_fake_score      (disc_fake_score),
                .disc_real_score      (disc_real_score),
                .generated_frame_flat (generated_frame_flat),
                .generated_frame_valid(generated_frame_valid),
                .sample_flat          (gan_sample_flat)
            );
        end
    endgenerate

    function automatic [15:0] sample_word(input integer idx);
        sample_word = gan_sample_flat[(idx+1)*16-1 -: 16];
    endfunction

    function automatic [15:0] expected_word(input integer idx);
        expected_word = comb_expected_flat[(idx+1)*16-1 -: 16];
    endfunction

    // Clock + dump -----------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        if (ENABLE_VCD_DEFAULT || $test$plusargs("dumpvcd")) begin
            $display("[TB] Wave dump ENABLED -> vcd/digit_identifier_tb.vcd");
            $dumpfile("vcd/digit_identifier_tb.vcd");
            $dumpvars(0, digit_identifier_tb);
        end else begin
            $display("[TB] Wave dump DISABLED (set ENABLE_VCD_DEFAULT=1 or pass +dumpvcd to enable)");
        end

        wait (comb_data_valid);
        if (FAST_DEBUG)
            $display("[TB] FAST_DEBUG mode: quick test using stub");
        else
            $display("[TB] FULL PIPELINE mode: running real generator/discriminator");
        $display("[TB] Combinational sample ready (expected available = %0b)", comb_has_expected);
    end

    // Stimulus ----------------------------------------------------------------
    initial begin
        rst = 1'b1;
        start = 1'b0;
        similarity_avg_abs = 0;
        similarity_max_abs = 0;

        repeat (10) @(posedge clk);
        rst = 1'b0;

        wait (comb_data_valid);
        $display("[TB] Sample latched; issuing start pulse next cycle");
        @(posedge clk);

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        if (FAST_DEBUG)
            $display("[TB] Start pulse issued. Fast stub will complete in ~3 cycles.");
        else
            $display("[TB] Start pulse issued. Monitoring full GAN pipeline (limit=%0d cycles)...", MAX_WAIT_CYCLES);

        wait_for_done(MAX_WAIT_CYCLES);
        $display("[TB] gan_comb_top.done observed. Waiting for generated_frame_valid...");
        wait (generated_frame_valid);
        $display("[TB] generated_frame_valid asserted. Capturing artifacts.");
        capture_generated_pixels();
        dump_generated_mem();
        maybe_write_expected_snapshot();
        compute_similarity();
        validate_against_expected();
        write_metrics();

        if (!disc_real_is_real) begin
            $error("[TB] Discriminator flagged the real sample as fake. Score=%0d", disc_real_score);
            $fatal(1, "Digit identifier test failed on real sample");
        end

        $display("\n=== Digit Identifier Summary ===");
        $display("D(fake) score=%0d flag=%0b", disc_fake_score, disc_fake_is_real);
        $display("D(real) score=%0d flag=%0b", disc_real_score, disc_real_is_real);
        $display("avg|diff| (Q8.8) = %0d | max|diff| (Q8.8) = %0d", similarity_avg_abs, similarity_max_abs);
        $display("Artifacts: %s (frame), %s (metrics)", OUTPUT_MEM_PATH, METRICS_LOG_PATH);

        #50;
        $finish;
    end

    // Tasks ------------------------------------------------------------------
    task wait_for_done(input integer max_cycles);
        integer cycles;
        begin
            cycles = 0;
            while (!done) begin
                @(posedge clk);
                cycles = cycles + 1;
                if ((cycles & 32'h00FF_FFFF) == 0 && cycles > 0) begin
                    $display("[TB]   ... still processing (cycles=%0d busy=%0b)", cycles, busy);
                end
                if (cycles > max_cycles) begin
                    $fatal(1, "[TB] Timeout waiting for done signal (limit=%0d cycles, reached %0d)", max_cycles, cycles);
                end
            end
            $display("[TB] done asserted after %0d cycles", cycles);
        end
    endtask

    task capture_generated_pixels;
        integer idx;
        begin
            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                captured_pixels[idx] = generated_frame_flat[(idx+1)*16-1 -: 16];
            end
            $display("[TB] Captured generated frame into local buffer");
        end
    endtask

    task dump_generated_mem;
        integer fh;
        integer idx;
        begin
            fh = $fopen(OUTPUT_MEM_PATH, "w");
            if (fh == 0) begin
                $error("[TB] Unable to open %s for write", OUTPUT_MEM_PATH);
                $fatal(1, "Failed to create generated frame mem file");
            end
            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                $fdisplay(fh, "%04x", captured_pixels[idx] & 16'hffff);
            end
            $fclose(fh);
            $display("[TB] Dumped generated frame to %s", OUTPUT_MEM_PATH);
        end
    endtask

    task compute_similarity;
        integer idx;
        integer abs_sum;
        integer diff;
        begin
            abs_sum = 0;
            similarity_max_abs = 0;
            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                diff = sample_word(idx) - captured_pixels[idx];
                if (diff < 0)
                    diff = -diff;
                abs_sum = abs_sum + diff;
                if (diff > similarity_max_abs)
                    similarity_max_abs = diff;
            end
            similarity_avg_abs = abs_sum / PIXEL_COUNT;
            $display("[TB] avg|diff|=%0d max|diff|=%0d (Q8.8 domain)", similarity_avg_abs, similarity_max_abs);
        end
    endtask

    task maybe_write_expected_snapshot;
        integer fh;
        integer idx;
        begin
            if (!comb_has_expected) begin
                fh = $fopen(EXPECTED_MEM_PATH, "w");
                if (fh == 0) begin
                    $error("[TB] Unable to create %s for expected snapshot", EXPECTED_MEM_PATH);
                end else begin
                    for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                        $fdisplay(fh, "%04x", captured_pixels[idx] & 16'hffff);
                    end
                    $fclose(fh);
                    $display("[TB] Seeded new expected snapshot at %s (effective next run)", EXPECTED_MEM_PATH);
                end
            end
        end
    endtask

    task validate_against_expected;
        integer idx;
        begin
            expected_mismatches = 0;
            if (!comb_has_expected) begin
                $display("[TB] No expected snapshot present; skipping combinational validation block.");
            end else begin
                for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                    if (captured_pixels[idx] !== expected_word(idx)) begin
                        expected_mismatches = expected_mismatches + 1;
                        if (expected_mismatches <= 5)
                            $display("[TB] expected mismatch idx %0d exp %04x got %04x", idx, expected_word(idx), captured_pixels[idx]);
                    end
                end

                if (expected_mismatches == 0) begin
                    $display("[TB] PASS: generated frame matches combinational reference snapshot.");
                end else begin
                    $fatal(1, "[TB] %0d mismatches vs combinational reference", expected_mismatches);
                end
            end
        end
    endtask

    task write_metrics;
        integer fh;
        begin
            fh = $fopen(METRICS_LOG_PATH, "w");
            if (fh == 0) begin
                $error("[TB] Unable to write metrics log %s", METRICS_LOG_PATH);
            end else begin
                $fdisplay(fh, "disc_fake_score=%0d", disc_fake_score);
                $fdisplay(fh, "disc_fake_flag=%0b", disc_fake_is_real);
                $fdisplay(fh, "disc_real_score=%0d", disc_real_score);
                $fdisplay(fh, "disc_real_flag=%0b", disc_real_is_real);
                $fdisplay(fh, "avg_abs_diff_q8_8=%0d", similarity_avg_abs);
                $fdisplay(fh, "max_abs_diff_q8_8=%0d", similarity_max_abs);
                $fdisplay(fh, "combinational_expected=%0b", comb_has_expected);
                $fdisplay(fh, "expected_mismatches=%0d", comb_has_expected ? expected_mismatches : -1);
                $fclose(fh);
            end
        end
    endtask
endmodule
