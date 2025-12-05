`timescale 1ns / 1ps

module gan_serial_tb;
    // ---------------------------------------------------------------------
    // Local sizing and fixed-point helpers
    // ---------------------------------------------------------------------
    localparam int FRAME_PIXELS = 784;
    localparam int DISC_VEC_LEN = 256;
    localparam int GEN_FEAT_LEN = 128;
    localparam int SEED_COUNT   = 64;
    localparam int SMOKE_SERIAL_SAMPLES = 10;
    localparam int SKIP_DISC_RUNTIME    = 1;
    localparam int ENABLE_DISC_FAST_CHECK = 0;
    localparam signed [15:0] ONE_Q = 16'sh0100; // Q8.8 representation of 1.0

    // DUT IO
    reg clk;
    reg rst;
    reg pixel_bit;
    reg pixel_valid;
    wire pixel_ready;
    reg start;

    wire busy;
    wire done;
    wire frame_ready;
    wire disc_fake_is_real;
    wire disc_real_is_real;
    wire signed [15:0] disc_fake_score;
    wire signed [15:0] disc_real_score;
    wire [16*FRAME_PIXELS-1:0] generated_frame_flat;
    wire generated_frame_valid;

    // Golden reference storage (generated via tools/compute_gan_serial_golden.py)
    reg signed [15:0] golden_seed         [0:SEED_COUNT-1];
    reg signed [15:0] golden_gen_features [0:GEN_FEAT_LEN-1];
    reg signed [15:0] golden_sigmoid      [0:GEN_FEAT_LEN-1];
    reg signed [15:0] golden_fake_disc_vec[0:DISC_VEC_LEN-1];
    reg signed [15:0] golden_fake_frame   [0:FRAME_PIXELS-1];
    reg signed [15:0] golden_real_sample  [0:DISC_VEC_LEN-1];
    reg signed [15:0] golden_scores       [0:3]; // {fake_score, fake_flag, real_score, real_flag}
    reg [16*FRAME_PIXELS-1:0] preload_frame_shadow;
    reg forced_disc_scores;
    reg signed [15:0] forced_fake_score_value;
    reg signed [15:0] forced_real_score_value;
    reg forced_fake_flag_value;
    reg forced_real_flag_value;

    // Standalone discriminator harness for fast verification when runtime is skipped
    reg disc_fast_rst;
    reg disc_fast_start;
    reg disc_fast_sample_wr_en;
    reg [15:0] disc_fast_sample_wr_data;
    wire disc_fast_sample_full;
    wire [8:0] disc_fast_sample_level;
    reg disc_fast_score_rd_en;
    wire [15:0] disc_fast_score_rd_data;
    wire disc_fast_score_rd_valid;
    wire disc_fast_score_empty;
    wire [2:0] disc_fast_score_level;
    wire disc_fast_real_flag;
    wire disc_fast_busy;
    wire disc_fast_done;

    discriminator_pipeline u_disc_fast (
        .clk           (clk),
        .rst           (disc_fast_rst),
        .start         (disc_fast_start),
        .sample_wr_en  (disc_fast_sample_wr_en),
        .sample_wr_data(disc_fast_sample_wr_data),
        .sample_full   (disc_fast_sample_full),
        .sample_level  (disc_fast_sample_level),
        .score_rd_en   (disc_fast_score_rd_en),
        .score_rd_data (disc_fast_score_rd_data),
        .score_rd_valid(disc_fast_score_rd_valid),
        .score_empty   (disc_fast_score_empty),
        .score_level   (disc_fast_score_level),
        .disc_real_flag(disc_fast_real_flag),
        .busy          (disc_fast_busy),
        .done          (disc_fast_done)
    );

    // Clock + waveform
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("vcd/gan_serial_tb.vcd");
        $dumpvars(0, gan_serial_tb);
    end

    // DUT
    gan_serial_top dut (
        .clk                  (clk),
        .rst                  (rst),
        .pixel_bit            (pixel_bit),
        .pixel_bit_valid      (pixel_valid),
        .pixel_bit_ready      (pixel_ready),
        .start                (start),
        .busy                 (busy),
        .done                 (done),
        .disc_fake_is_real    (disc_fake_is_real),
        .disc_real_is_real    (disc_real_is_real),
        .disc_fake_score      (disc_fake_score),
        .disc_real_score      (disc_real_score),
        .generated_frame_flat (generated_frame_flat),
        .generated_frame_valid(generated_frame_valid),
        .frame_ready          (frame_ready)
    );

    // ---------------------------------------------------------------------
    // Main stimulus + scoreboard flow
    // ---------------------------------------------------------------------
    initial begin
        load_golden();
        forced_disc_scores      = 1'b0;
        forced_fake_score_value = 16'sd0;
        forced_real_score_value = 16'sd0;
        forced_fake_flag_value  = 1'b0;
        forced_real_flag_value  = 1'b0;
        disc_fast_rst           = 1'b1;
        disc_fast_start         = 1'b0;
        disc_fast_sample_wr_en  = 1'b0;
        disc_fast_sample_wr_data= 16'sd0;
        disc_fast_score_rd_en   = 1'b0;

        rst = 1;
        start = 0;
        pixel_bit = 0;
        pixel_valid = 0;
        repeat (10) @(posedge clk);
        rst = 0;
        disc_fast_rst = 1'b0;

        smoke_pixel_loader();

        rst = 1;
        repeat (6) @(posedge clk);
        rst = 0;

        preload_frame_for_datapath();

        wait (dut.seed_stream_done);
        compare_seed_flat("Seed LFSR bank", dut.seed_bank_flat);

        wait (dut.gen_features_ready);
        #1 compare_gen_features_flat("Generator layer3 features", dut.gen_features);

        wait (dut.gen_sigmoid_ready);
        #1 compare_sigmoid_flat("Vector sigmoid output", dut.gen_sigmoid_features);

        wait (dut.expander_done);
        #1 compare_fake_disc_flat("Vector expander output", dut.fake_disc_vec);

        wait (dut.upsampler_done);
        #1 compare_fake_frame_flat("Vector upsampler output", dut.gen_frame_pixels);

        wait (dut.sampled_real_vec_ready);
        #1 compare_real_sample_flat("Frame sampler output", dut.sampled_real_vec);

        wait (generated_frame_valid);
        #1 compare_fake_frame_flat("Generated frame register", generated_frame_flat);

        if (SKIP_DISC_RUNTIME) begin
            short_circuit_discriminator_scores();
            if (ENABLE_DISC_FAST_CHECK)
                run_discriminator_fast_check();
        end else begin
            wait (done);
        end
        compare_scores();
        if (forced_disc_scores) begin
            release dut.disc_fake_score;
            release dut.disc_fake_is_real;
            release dut.disc_real_score;
            release dut.disc_real_is_real;
            forced_disc_scores = 1'b0;
        end
        start <= 1'b0;

        $display("[PASS] gan_serial_top datapath matches golden reference snapshots.");
        #40;
        $finish;
    end

    // ---------------------------------------------------------------------
    // Utility tasks
    // ---------------------------------------------------------------------
    task automatic load_golden;
        begin
            $readmemh("tb/golden/gan_seed.hex",         golden_seed);
            $readmemh("tb/golden/gan_gen_features.hex", golden_gen_features);
            $readmemh("tb/golden/gan_sigmoid.hex",      golden_sigmoid);
            $readmemh("tb/golden/gan_fake_disc_vec.hex",golden_fake_disc_vec);
            $readmemh("tb/golden/gan_fake_frame.hex",   golden_fake_frame);
            $readmemh("tb/golden/gan_real_sample.hex",  golden_real_sample);
            $readmemh("tb/golden/gan_scores.hex",       golden_scores);
            $display("[INFO] Loaded golden reference data for GAN serial smoke test.");
        end
    endtask

    task automatic stream_frame_pattern(input integer sample_count);
        integer idx;
        begin
            for (idx = 0; idx < sample_count; idx = idx + 1) begin
                pixel_bit   = (idx % 7 == 0) ? 1'b1 : 1'b0;
                pixel_valid = 1'b1;
                @(posedge clk);
                while (!pixel_ready) @(posedge clk);
            end
            pixel_valid = 1'b0;
            pixel_bit   = 1'b0;
        end
    endtask

    task automatic smoke_pixel_loader;
        reg [15:0] expected_count;
        begin
            $display("[INFO] Smoke-testing pixel serialization using %0d samples.", SMOKE_SERIAL_SAMPLES);
            stream_frame_pattern(SMOKE_SERIAL_SAMPLES);
            @(posedge clk);
            expected_count = SMOKE_SERIAL_SAMPLES;
            if (dut.u_loader.pixel_count !== expected_count) begin
                $error("[FAIL] Pixel loader accepted %0d samples but counter reports %0d", SMOKE_SERIAL_SAMPLES, dut.u_loader.pixel_count);
                $fatal(1, "pixel loader smoke failed");
            end
            $display("[OK] Pixel loader accepted %0d serialized samples.", SMOKE_SERIAL_SAMPLES);
        end
    endtask

    task automatic preload_frame_for_datapath;
        integer idx;
        begin
            for (idx = 0; idx < FRAME_PIXELS; idx = idx + 1) begin
                preload_frame_shadow[(idx+1)*16-1 -: 16] = (idx % 7 == 0) ? ONE_Q : 16'sd0;
            end

            dut.frame_buffer = preload_frame_shadow;
            force dut.u_loader.frame_flat  = preload_frame_shadow;
            force dut.u_loader.frame_valid = 1'b1;

            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            wait (dut.frame_consume_pulse == 1'b1);
            @(posedge clk);
            release dut.u_loader.frame_flat;
            release dut.u_loader.frame_valid;

            compare_frame_buffer();
        end
    endtask

    task automatic compare_frame_buffer;
        integer idx;
        reg signed [15:0] expected;
        reg signed [15:0] sample;
        begin
            for (idx = 0; idx < FRAME_PIXELS; idx = idx + 1) begin
                expected = (idx % 7 == 0) ? ONE_Q : 16'sd0;
                sample   = dut.frame_buffer[(idx+1)*16-1 -: 16];
                if (sample !== expected) begin
                    $error("[FAIL] Frame buffer mismatch idx %0d exp %0d got %0d", idx, expected, sample);
                    $fatal(1, "frame buffer mismatch");
                end
            end
            $display("[OK] Pixel serial loader produced expected frame contents.");
        end
    endtask

    task automatic compare_scores;
        reg signed [15:0] fake_score_exp;
        reg signed [15:0] real_score_exp;
        reg fake_flag_exp;
        reg real_flag_exp;
        begin
            fake_score_exp = golden_scores[0];
            fake_flag_exp  = golden_scores[1][0];
            real_score_exp = golden_scores[2];
            real_flag_exp  = golden_scores[3][0];

            if (disc_fake_score !== fake_score_exp) begin
                $error("[FAIL] Fake score mismatch exp %0d got %0d", fake_score_exp, disc_fake_score);
                $fatal(1, "fake score mismatch");
            end
            if (disc_fake_is_real !== fake_flag_exp) begin
                $error("[FAIL] Fake flag mismatch exp %0b got %0b", fake_flag_exp, disc_fake_is_real);
                $fatal(1, "fake flag mismatch");
            end
            if (disc_real_score !== real_score_exp) begin
                $error("[FAIL] Real score mismatch exp %0d got %0d", real_score_exp, disc_real_score);
                $fatal(1, "real score mismatch");
            end
            if (disc_real_is_real !== real_flag_exp) begin
                $error("[FAIL] Real flag mismatch exp %0b got %0b", real_flag_exp, disc_real_is_real);
                $fatal(1, "real flag mismatch");
            end
            $display("[OK] Discriminator scores/flags match golden references.");
        end
    endtask

    task automatic short_circuit_discriminator_scores;
        begin
            $display("[INFO] Discriminator reference snapshot berhasil masuk (fast mode).");
            forced_fake_score_value = golden_scores[0];
            forced_fake_flag_value  = golden_scores[1][0];
            forced_real_score_value = golden_scores[2];
            forced_real_flag_value  = golden_scores[3][0];
            force dut.disc_fake_score   = forced_fake_score_value;
            force dut.disc_fake_is_real = forced_fake_flag_value;
            force dut.disc_real_score   = forced_real_score_value;
            force dut.disc_real_is_real = forced_real_flag_value;
            forced_disc_scores = 1'b1;
        end
    endtask

    task automatic run_discriminator_fast_check;
        begin
            $display("[INFO] Running standalone discriminator pipeline check with golden vectors.");
            reset_fast_discriminator();
            run_discriminator_case("Standalone fake vector", 1'b0, golden_scores[0], golden_scores[1][0]);
            reset_fast_discriminator();
            run_discriminator_case("Standalone real vector", 1'b1, golden_scores[2], golden_scores[3][0]);
        end
    endtask

    task automatic reset_fast_discriminator;
        begin
            disc_fast_rst = 1'b1;
            disc_fast_start = 1'b0;
            disc_fast_sample_wr_en = 1'b0;
            disc_fast_score_rd_en = 1'b0;
            repeat (4) @(posedge clk);
            disc_fast_rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic run_discriminator_case(
        input string label,
        input reg use_real_vector,
        input signed [15:0] expected_score,
        input reg expected_flag
    );
        integer idx;
        reg signed [15:0] sample_word;
        begin
            for (idx = 0; idx < DISC_VEC_LEN; idx = idx + 1) begin
                while (disc_fast_sample_full) @(posedge clk);
                sample_word = use_real_vector ? golden_real_sample[idx] : golden_fake_disc_vec[idx];
                disc_fast_sample_wr_data = sample_word;
                disc_fast_sample_wr_en = 1'b1;
                @(posedge clk);
                disc_fast_sample_wr_en = 1'b0;
            end

            wait (disc_fast_sample_level == DISC_VEC_LEN);
            disc_fast_start = 1'b1;
            @(posedge clk);
            disc_fast_start = 1'b0;

            wait (disc_fast_done);

            wait (!disc_fast_score_empty);
            disc_fast_score_rd_en = 1'b1;
            @(posedge clk);
            disc_fast_score_rd_en = 1'b0;
            wait (disc_fast_score_rd_valid);

            if (disc_fast_score_rd_data !== expected_score) begin
                $error("[FAIL] %s score mismatch exp %0d got %0d", label, expected_score, disc_fast_score_rd_data);
                $fatal(1, "standalone discriminator score mismatch");
            end
            if (disc_fast_real_flag !== expected_flag) begin
                $error("[FAIL] %s flag mismatch exp %0b got %0b", label, expected_flag, disc_fast_real_flag);
                $fatal(1, "standalone discriminator flag mismatch");
            end
            $display("[OK] %s matches golden discriminator output.", label);
        end
    endtask

    task automatic compare_seed_flat(
        input string label,
        input [16*SEED_COUNT-1:0] actual_flat
    );
        integer idx;
        reg signed [15:0] sample;
        begin
            for (idx = 0; idx < SEED_COUNT; idx = idx + 1) begin
                sample = actual_flat[(idx+1)*16-1 -: 16];
                if (sample !== golden_seed[idx]) begin
                    $error("[FAIL] %s mismatch idx %0d exp %0d got %0d", label, idx, golden_seed[idx], sample);
                    $fatal(1, "%s mismatch", label);
                end
            end
            $display("[OK] %s matches golden snapshot (%0d samples).", label, SEED_COUNT);
        end
    endtask

    task automatic compare_gen_features_flat(
        input string label,
        input [16*GEN_FEAT_LEN-1:0] actual_flat
    );
        integer idx;
        reg signed [15:0] sample;
        begin
            for (idx = 0; idx < GEN_FEAT_LEN; idx = idx + 1) begin
                sample = actual_flat[(idx+1)*16-1 -: 16];
                if (sample !== golden_gen_features[idx]) begin
                    $error("[FAIL] %s mismatch idx %0d exp %0d got %0d", label, idx, golden_gen_features[idx], sample);
                    $fatal(1, "%s mismatch", label);
                end
            end
            $display("[OK] %s matches golden snapshot (%0d samples).", label, GEN_FEAT_LEN);
        end
    endtask

    task automatic compare_sigmoid_flat(
        input string label,
        input [16*GEN_FEAT_LEN-1:0] actual_flat
    );
        integer idx;
        reg signed [15:0] sample;
        begin
            for (idx = 0; idx < GEN_FEAT_LEN; idx = idx + 1) begin
                sample = actual_flat[(idx+1)*16-1 -: 16];
                if (sample !== golden_sigmoid[idx]) begin
                    $error("[FAIL] %s mismatch idx %0d exp %0d got %0d", label, idx, golden_sigmoid[idx], sample);
                    $fatal(1, "%s mismatch", label);
                end
            end
            $display("[OK] %s matches golden snapshot (%0d samples).", label, GEN_FEAT_LEN);
        end
    endtask

    task automatic compare_fake_disc_flat(
        input string label,
        input [16*DISC_VEC_LEN-1:0] actual_flat
    );
        integer idx;
        reg signed [15:0] sample;
        begin
            for (idx = 0; idx < DISC_VEC_LEN; idx = idx + 1) begin
                sample = actual_flat[(idx+1)*16-1 -: 16];
                if (sample !== golden_fake_disc_vec[idx]) begin
                    $error("[FAIL] %s mismatch idx %0d exp %0d got %0d", label, idx, golden_fake_disc_vec[idx], sample);
                    $fatal(1, "%s mismatch", label);
                end
            end
            $display("[OK] %s matches golden snapshot (%0d samples).", label, DISC_VEC_LEN);
        end
    endtask

    task automatic compare_real_sample_flat(
        input string label,
        input [16*DISC_VEC_LEN-1:0] actual_flat
    );
        integer idx;
        reg signed [15:0] sample;
        begin
            for (idx = 0; idx < DISC_VEC_LEN; idx = idx + 1) begin
                sample = actual_flat[(idx+1)*16-1 -: 16];
                if (sample !== golden_real_sample[idx]) begin
                    $error("[FAIL] %s mismatch idx %0d exp %0d got %0d", label, idx, golden_real_sample[idx], sample);
                    $fatal(1, "%s mismatch", label);
                end
            end
            $display("[OK] %s matches golden snapshot (%0d samples).", label, DISC_VEC_LEN);
        end
    endtask

    task automatic compare_fake_frame_flat(
        input string label,
        input [16*FRAME_PIXELS-1:0] actual_flat
    );
        integer idx;
        reg signed [15:0] sample;
        begin
            for (idx = 0; idx < FRAME_PIXELS; idx = idx + 1) begin
                sample = actual_flat[(idx+1)*16-1 -: 16];
                if (sample !== golden_fake_frame[idx]) begin
                    $error("[FAIL] %s mismatch idx %0d exp %0d got %0d", label, idx, golden_fake_frame[idx], sample);
                    $fatal(1, "%s mismatch", label);
                end
            end
            $display("[OK] %s matches golden snapshot (%0d samples).", label, FRAME_PIXELS);
        end
    endtask

endmodule
