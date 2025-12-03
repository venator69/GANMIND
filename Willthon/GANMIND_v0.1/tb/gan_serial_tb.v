`timescale 1ns / 1ps

module gan_serial_tb;
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
    wire [16*784-1:0] generated_frame_flat;
    wire generated_frame_valid;

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("vcd/gan_serial_tb.vcd");
        $dumpvars(0, gan_serial_tb);
    end

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
        rst = 1;
        start = 0;
        pixel_bit = 0;
        pixel_valid = 0;
        repeat (10) @(posedge clk);
        rst = 0;

        // Send one serialized frame
        send_frame_pattern();

        wait (frame_ready);
        @(posedge clk);

        start = 1;
        wait (done);
        repeat (4) @(posedge clk); // allow score FIFO to drain before sampling results
        start = 0;

        $display("\n=== GAN Serial Test Complete ===");
        $display("D(G(z)) score = %0d | real? %0b", disc_fake_score, disc_fake_is_real);
        $display("D(x)    score = %0d | real? %0b", disc_real_score, disc_real_is_real);
        $display("Generated frame valid: %0b", generated_frame_valid);

        #100;
        $finish;
    end

    task send_frame_pattern;
        integer idx;
        begin
            for (idx = 0; idx < 784; idx = idx + 1) begin
                pixel_bit = (idx % 7 == 0) ? 1'b1 : 1'b0;
                pixel_valid = 1'b1;
                @(posedge clk);
                while (!pixel_ready) begin
                    @(posedge clk);
                end
            end
            pixel_valid = 1'b0;
        end
    endtask

endmodule
