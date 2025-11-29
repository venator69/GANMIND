`timescale 1ns / 1ps

module layer1_discriminator_tb;

    // Inputs: 256 elements (from Generator layer 3 output)
    reg signed [15:0] inputs [0:255];
    reg signed [16*256-1:0] flat_input;
    reg clk;
    reg rst;
    reg start;

    // Outputs: 128 elements
    wire signed [16*128-1:0] flat_output;
    wire done;

    // Instantiate Unit Under Test (UUT)
    layer1_discriminator uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .flat_input_flat(flat_input),
        .flat_output_flat(flat_output),
        .done(done)
    );

    // Keep the flattened bus updated
    integer i_pack;
    always @(*) begin
        for (i_pack = 0; i_pack < 256; i_pack = i_pack + 1) begin
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

    integer k, m;

    // Clock generator: 10ns period (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("discriminator_layer1_test.vcd");
        $dumpvars(0, layer1_discriminator_tb);

        // Reset
        rst = 1;
        start = 0;
        #20;
        rst = 0;

        // Initialize inputs to zero
        for (k = 0; k < 256; k = k + 1) begin
            inputs[k] = 16'sd0;
        end

        $display("--------------------------------------------------");
        $display("   TESTING DISCRIMINATOR LAYER 1");
        $display("   256 inputs -> 128 neurons");
        $display("--------------------------------------------------");

        // Test Case 1: Zero inputs (output should be bias only)
        $display("\nTest Case 1: Zero Inputs");
        for (k = 0; k < 256; k = k + 1) begin
            inputs[k] = 16'sd0;
        end

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1);
        #1;

        $display("Layer 1 Output (first 20 values with zero input):");
        for (m = 0; m < 20; m = m + 1) begin
            $display("[%2d] = %f (hex: %h)", 
                     m, 
                     q8_8_to_real($signed(flat_output[(m+1)*16-1 -: 16])),
                     flat_output[(m+1)*16-1 -: 16]);
        end

        // Test Case 2: Small random inputs
        $display("\nTest Case 2: Random Inputs");
        for (k = 0; k < 256; k = k + 1) begin
            inputs[k] = $random % 256;
        end

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1);
        #1;

        $display("Layer 1 Output (first 20 values with random input):");
        for (m = 0; m < 20; m = m + 1) begin
            $display("[%2d] = %f (hex: %h)", 
                     m, 
                     q8_8_to_real($signed(flat_output[(m+1)*16-1 -: 16])),
                     flat_output[(m+1)*16-1 -: 16]);
        end

        $display("--------------------------------------------------");
        $display("Layer 1 Test Complete");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
