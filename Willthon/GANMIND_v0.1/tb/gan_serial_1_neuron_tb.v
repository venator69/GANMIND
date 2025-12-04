`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// gan_serial_1_neuron_tb
// -----------------------------------------------------------------------------
//  * Lightweight sanity test for gan_serial_top.
//  * Streams a single serialized frame, triggers one inference cycle, and
//    prints discriminator results plus generator metadata.
// -----------------------------------------------------------------------------
module gan_serial_1_neuron_tb;
    localparam integer FRAME_BITS = 28*28; // serialized pixel count

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
        $dumpfile("vcd/gan_serial_1_neuron_tb.vcd");
        $dumpvars(0, gan_serial_1_neuron_tb);
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
        rst         = 1'b1;
        start       = 1'b0;
        pixel_bit   = 1'b0;
        pixel_valid = 1'b0;
        repeat (10) @(posedge clk);
        rst = 1'b0;

        send_frame_pattern(1'b0);
        wait (frame_ready);
        @(posedge clk);

        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait (done);
        repeat (4) @(posedge clk);

        $display("\n=== gan_serial_top Sanity ===");
        $display("busy=%0b done=%0b frame_ready=%0b", busy, done, frame_ready);
        $display("D(G(z)) score = %0d | real? %0b", disc_fake_score, disc_fake_is_real);
        $display("D(x)    score = %0d | real? %0b", disc_real_score, disc_real_is_real);
        $display("Generated frame valid: %0b", generated_frame_valid);

        #100;
        $finish;
    end

    task send_frame_pattern(input bit bias_bit);
        integer idx;
        begin
            for (idx = 0; idx < FRAME_BITS; idx = idx + 1) begin
                pixel_bit   = (idx[2:0] == 3'b000) ? ~bias_bit : bias_bit;
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

endmodule
