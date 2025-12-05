`include "layer1_generator.v"

module layer1_tb;

    // Inputs (Array 64 x 16-bit)
    reg signed [15:0] inputs [0:63];
    
    // Outputs (Array 256 x 16-bit)
    wire signed [15:0] outputs [0:255];

    // Instantiate Unit Under Test (UUT)
    layer1_generator uut (
        .flat_input(inputs),
        .flat_output(outputs)
    );

    integer k;

    // Fungsi Helper untuk menampilkan Fixed Point Q8.8
    function real q8_8_to_real;
        input signed [15:0] val;
        begin
            q8_8_to_real = val / 256.0;
        end
    endfunction

    initial begin
        $dumpfile("layer1_test.vcd");
        $dumpvars(0, layer1_tb);

        // 1. Inisialisasi Test Vector: Semua 0
        $display("Initializing Inputs to 0...");
        for (k = 0; k < 64; k = k + 1) begin
            inputs[k] = 16'd0; // 0.0 dalam Q8.8
        end

        // Tunggu logic kombinasional stabil
        #10;

        // 2. Tampilkan Hasil
        $display("--------------------------------------------------");
        $display("Test Vector: Zero Vector (Input = 0)");
        $display("Expecting Output = Bias");
        $display("--------------------------------------------------");
        
        // Menampilkan 20 neuron pertama sebagai sampel
        $display("Nilai Output (20 nilai pertama):");
        $display("[%f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f %f]", 
                 q8_8_to_real(outputs[0]), q8_8_to_real(outputs[1]), q8_8_to_real(outputs[2]), q8_8_to_real(outputs[3]), 
                 q8_8_to_real(outputs[4]), q8_8_to_real(outputs[5]), q8_8_to_real(outputs[6]), q8_8_to_real(outputs[7]), 
                 q8_8_to_real(outputs[8]), q8_8_to_real(outputs[9]), q8_8_to_real(outputs[10]), q8_8_to_real(outputs[11]), 
                 q8_8_to_real(outputs[12]), q8_8_to_real(outputs[13]), q8_8_to_real(outputs[14]), q8_8_to_real(outputs[15]), 
                 q8_8_to_real(outputs[16]), q8_8_to_real(outputs[17]), q8_8_to_real(outputs[18]), q8_8_to_real(outputs[19]));
        
        $display("--------------------------------------------------");
        $display("Simulation Finished.");
        $finish;
    end

endmodule
