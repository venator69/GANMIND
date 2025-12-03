`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// gan_circle_tb
// -----------------------------------------------------------------------------
//  * Drives gan_serial_top with the serialized bits that correspond to
//    src/test_input_image/test_circle.mem (Q8.8 flattened frame).
//  * Dumps the generated frame into a .mem file for software inspection and
//    optionally compares against a golden reference if available.
// -----------------------------------------------------------------------------
module gan_circle_tb;
    localparam integer PIXEL_COUNT = 784;
    localparam string  INPUT_MEM_PATH    = "src/test_input_image/test_circle.mem";
    localparam string  OUTPUT_MEM_PATH   = "src/test_input_image/test_circle_generated.mem";
    localparam string  EXPECTED_MEM_PATH = "src/test_input_image/test_circle_expected.mem";

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
    wire [16*PIXEL_COUNT-1:0] generated_frame_flat;
    wire generated_frame_valid;

    reg [15:0] input_pixels [0:PIXEL_COUNT-1];
    reg [15:0] expected_pixels [0:PIXEL_COUNT-1];
    integer expected_loaded;
    integer exp_fh;

    initial begin
        $dumpfile("vcd/gan_circle_tb.vcd");
        $dumpvars(0, gan_circle_tb);

        $display("[TB] Loading serialized input frame from %s", INPUT_MEM_PATH);
        $readmemh(INPUT_MEM_PATH, input_pixels);

        expected_loaded = 0;
        exp_fh = $fopen(EXPECTED_MEM_PATH, "r");
        if (exp_fh != 0) begin
            $fclose(exp_fh);
            $readmemh(EXPECTED_MEM_PATH, expected_pixels);
            expected_loaded = 1;
            $display("[TB] Loaded expected output from %s", EXPECTED_MEM_PATH);
        end else begin
            $display("[TB] Expected output %s not found. Run once to generate, then copy to this path for regression checks.", EXPECTED_MEM_PATH);
        end
    end

    // Clock generation
    initial clk = 1'b0;
    always #5 clk = ~clk;

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

    initial begin
        rst = 1'b1;
        start = 1'b0;
        pixel_bit = 1'b0;
        pixel_valid = 1'b0;
        repeat (10) @(posedge clk);
        rst = 1'b0;

        send_circle_frame();
        wait (frame_ready);
        @(posedge clk);

        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait (done);
        repeat (4) @(posedge clk);

        dump_generated_frame();
        compare_to_expected();

        $display("\n=== GAN Circle Test Complete ===");
        $display("D(G(z)) score = %0d | real? %0b", disc_fake_score, disc_fake_is_real);
        $display("D(x)    score = %0d | real? %0b", disc_real_score, disc_real_is_real);
        $display("Generated frame valid: %0b", generated_frame_valid);

        #100;
        $finish;
    end

    task send_circle_frame;
        integer idx;
        begin
            $display("[TB] Streaming serialized circle frame");
            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                pixel_bit   = (input_pixels[idx] != 16'd0);
                pixel_valid = 1'b1;
                @(posedge clk);
                while (!pixel_ready) begin
                    @(posedge clk);
                end
            end
            pixel_valid = 1'b0;
            pixel_bit   = 1'b0;
        end
    endtask

    task dump_generated_frame;
        integer fh;
        integer idx;
        reg [15:0] sample;
        begin
            fh = $fopen(OUTPUT_MEM_PATH, "w");
            if (fh == 0) begin
                $display("[TB] ERROR: unable to open %s for write", OUTPUT_MEM_PATH);
                disable dump_generated_frame;
            end

            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                sample = generated_frame_flat[(idx+1)*16-1 -: 16];
                $fdisplay(fh, "%04x", sample & 16'hffff);
            end
            $fclose(fh);
            $display("[TB] Dumped generated frame to %s", OUTPUT_MEM_PATH);
        end
    endtask

    task compare_to_expected;
        integer idx;
        integer mismatches;
        reg [15:0] sample;
        begin
            if (!expected_loaded) begin
                $display("[TB] Skipping comparison; no expected output present.");
                disable compare_to_expected;
            end

            mismatches = 0;
            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                sample = generated_frame_flat[(idx+1)*16-1 -: 16];
                if (sample !== expected_pixels[idx]) begin
                    mismatches = mismatches + 1;
                    if (mismatches <= 5)
                        $display("[TB] mismatch idx %0d: expected %04x got %04x", idx, expected_pixels[idx], sample);
                end
            end

            if (mismatches == 0)
                $display("[TB] PASS: generated frame matches expected");
            else
                $display("[TB] FAIL: %0d mismatches detected", mismatches);
        end
    endtask
endmodule
