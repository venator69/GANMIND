`timescale 1ns / 1ps

module layer2_generator_tb;

    // Inputs (Array 256 x 16-bit)
    reg signed [15:0] inputs [0:255];
    
    // Outputs (Array 256 x 16-bit) - read from flattened bus
    reg signed [15:0] outputs [0:255];
    
    // Clock, reset, start, done signals
    reg clk;
    reg rst;
    reg start;
    wire done;

    // Flattened buses for sequential MAC generator
    reg signed [16*256-1:0] flat_input_flat;
    wire signed [16*256-1:0] flat_output_flat;

    // Pack input: always @(*) block to write inputs into flat_input_flat
    integer p;
    always @(*) begin
        for (p = 0; p < 256; p = p + 1) begin
            flat_input_flat[(p+1)*16-1 -: 16] = inputs[p];
        end
    end

    // Unpack output: separate always block to read flat_output_flat into outputs
    always @(*) begin
        for (p = 0; p < 256; p = p + 1) begin
            outputs[p] = flat_output_flat[(p+1)*16-1 -: 16];
        end
    end

    // Instantiate Unit Under Test (UUT)
    layer2_generator uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .flat_input_flat(flat_input_flat),
        .flat_output_flat(flat_output_flat),
        .done(done)
    );

    integer k;

    // Clock generator: 10 ns period
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Fungsi Helper untuk menampilkan Fixed Point Q8.8
    function real q8_8_to_real;
        input signed [15:0] val;
        begin
            q8_8_to_real = val / 256.0;
        end
    endfunction

    initial begin
        $dumpfile("vcd/layer2_test.vcd");
        $dumpvars(0, layer2_generator_tb);

        // Reset
        rst = 1;
        start = 0;
        #20;
        rst = 0;

        // 1. Inisialisasi Test Vector: Semua 0
        $display("Initializing Inputs to 0...");
        for (k = 0; k < 256; k = k + 1) begin
            inputs[k] = 16'd0; // 0.0 dalam Q8.8
        end

        // Wait a bit for combinational logic to settle, then pulse start
        #10;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done signal (computation takes ~256 * 256 = 65536 cycles)
        // With 10ns clock, that's ~655 microseconds. We'll timeout after a reasonable time.
        wait(done == 1);
        #5; // small delay for outputs to settle

        // 2. Tampilkan Hasil
        $display("--------------------------------------------------");
        $display("LAYER 2 GENERATOR TEST");
        $display("Test Vector: Zero Vector (Input = 0)");
        $display("Expecting Output = Bias");
        $display("--------------------------------------------------");
        
        // Menampilkan 20 neuron pertama sebagai sampel
        $display("Output Values (20 nilai pertama):");
        for (k = 0; k < 20; k = k + 1) begin
            $display("[%2d] = %0.8f (hex: 0x%04x)", k, q8_8_to_real(outputs[k]), outputs[k]);
        end
        
        $display("--------------------------------------------------");
        $display("Simulation Finished.");
        $finish;
    end

endmodule

