`timescale 1ns / 1ps

module layer3_discriminator_tb;

    // Inputs: 32 elements (from Discriminator layer 2 output)
    reg signed [15:0] inputs [0:31];
    reg signed [16*32-1:0] flat_input;
    reg clk;
    reg rst;
    reg start;

    // Outputs: single decision + score
    wire signed [15:0] score_out;
    wire decision_real;
    wire done;

    // Instantiate Unit Under Test (UUT)
    layer3_discriminator uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .flat_input_flat(flat_input),
        .score_out(score_out),
        .decision_real(decision_real),
        .done(done)
    );

    // Keep the flattened bus updated
    integer i_pack;
    always @(*) begin
        for (i_pack = 0; i_pack < 32; i_pack = i_pack + 1) begin
            flat_input[(i_pack+1)*16-1 -: 16] = inputs[i_pack];
        end
    end

    // Helper to convert Q8.8 to real
    function real q8_8_to_real;
        input signed [15:0] val;
        begin
            q8_8_to_real = val / 256.0;
        end
    endfunction

    // Sigmoid activation function: 1 / (1 + exp(-x))
    function real sigmoid;
        input real x;
        real exp_neg_x;
        begin
            exp_neg_x = 2.718281828 ** (-x);
            sigmoid = 1.0 / (1.0 + exp_neg_x);
        end
    endfunction

    integer k;

    // Clock generator: 10ns period (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("discriminator_layer3_test.vcd");
        $dumpvars(0, layer3_discriminator_tb);

        // Reset
        rst = 1;
        start = 0;
        #20;
        rst = 0;

        // Initialize inputs to zero
        for (k = 0; k < 32; k = k + 1) begin
            inputs[k] = 16'sd0;
        end

        $display("--------------------------------------------------");
        $display("   TESTING DISCRIMINATOR LAYER 3 (FINAL)");
        $display("   256 inputs -> 1 output (after Sigmoid)");
        $display("--------------------------------------------------");

        // Test Case 1: Zero inputs (output should be bias only)
        $display("\nTest Case 1: Zero Inputs");
        for (k = 0; k < 32; k = k + 1) begin
            inputs[k] = 16'sd0;
        end

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1);
        #1;

        $display("Layer 3 Output (with zero input):");
        $display("[ 0] = %f (hex: 0x%h)", 
                 q8_8_to_real(score_out),
                 score_out);
        $display("With Sigmoid Activation: %f", sigmoid(q8_8_to_real(score_out)));

        // Test Case 2: Small random inputs
        $display("\nTest Case 2: Random Inputs");
        for (k = 0; k < 32; k = k + 1) begin
            inputs[k] = $random % 256;
        end

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1);
        #1;

        $display("Layer 3 Output (with random input):");
        $display("[ 0] = %f (hex: 0x%h)", 
                 q8_8_to_real(score_out),
                 score_out);
        $display("With Sigmoid Activation: %f", sigmoid(q8_8_to_real(score_out)));

        // Test Case 3: Positive bias (should favor REAL)
        $display("\nTest Case 3: Large Positive Inputs");
        for (k = 0; k < 32; k = k + 1) begin
            inputs[k] = 16'sd100; // 100/256 ≈ 0.39
        end

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1);
        #1;

        $display("Layer 3 Output (with large positive input):");
        $display("[ 0] = %f (hex: 0x%h)", 
                 q8_8_to_real(score_out),
                 score_out);
        $display("With Sigmoid Activation: %f", sigmoid(q8_8_to_real(score_out)));

        $display("--------------------------------------------------");
        $display("Layer 3 Test Complete");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
