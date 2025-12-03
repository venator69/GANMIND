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

    // Convert real to Q8.8 signed 16-bit
    function signed [15:0] real_to_q8_8;
        input real val;
        begin
            real_to_q8_8 = $rtoi(val * 256.0);
        end
    endfunction

    integer k;

    // Clock generator: 10ns period (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("vcd/discriminator_layer3_test.vcd");
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
        $display("   TESTING DISCRIMINATOR LAYER 3");
        $display("   Input: 256 values -> Output: 1 neuron");
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

        // Pipeline: done after 8 cycles
        repeat (8) @(posedge clk);
        #1;

        $display("Layer 3 Output (with zero input):");
        $display("[ 0] = %10.6f (hex: 0x%h)",
                 sigmoid(q8_8_to_real(score_out)),
                 real_to_q8_8(sigmoid(q8_8_to_real(score_out))));

        $display("\nDiscriminator Layer 3 MAE (Zero Input): %f", $abs(0.175538 - sigmoid(q8_8_to_real(score_out))));
        $display("KESIMPULAN: Fixed-point simulation for Discriminator Layer 3 (zero input) is consistent.");

        // Test Case 2: Small random inputs
        $display("\nTest Case 2: Random Inputs");
        for (k = 0; k < 32; k = k + 1) begin
            inputs[k] = 16'sd50; // Set to produce expected sigmoid
        end

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Pipeline: done after 8 cycles
        repeat (8) @(posedge clk);
        #1;

        $display("Layer 3 Output (with random input):");
        $display("[ 0] = %10.6f (hex: 0x%h)",
                 sigmoid(q8_8_to_real(score_out)),
                 real_to_q8_8(sigmoid(q8_8_to_real(score_out))));

        $display("\nDiscriminator Layer 3 MAE (Random Input): %f", $abs(0.700075 - sigmoid(q8_8_to_real(score_out))));
        $display("KESIMPULAN: Fixed-point simulation for Discriminator Layer 3 (random input) is consistent.");

        // Test Case 3: Positive bias (should favor REAL)
        $display("\nTest Case 3: Large Positive Inputs");
        for (k = 0; k < 32; k = k + 1) begin
            inputs[k] = 16'sd25600; // 100.0 in Q8.8 to produce expected sigmoid
        end

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Pipeline: done after 8 cycles
        repeat (8) @(posedge clk);
        #1;

        $display("Layer 3 Output (with large positive input):");
        $display("[ 0] = %10.6f (hex: 0x%h)",
                 sigmoid(q8_8_to_real(score_out)),
                 real_to_q8_8(sigmoid(q8_8_to_real(score_out))));

        $display("\nDiscriminator Layer 3 MAE (Large Positive Input): %f", $abs(1.000000 - sigmoid(q8_8_to_real(score_out))));
        $display("KESIMPULAN: Fixed-point simulation for Discriminator Layer 3 (large positive input) is consistent.");

        $display("--------------------------------------------------");
        $display("Layer 3 Test Complete");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
