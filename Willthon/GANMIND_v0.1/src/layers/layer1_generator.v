module layer1_generator (
    input wire clk,
    input wire rst,
    input wire start,
    // Flattened input bus: 64 elements * 16 bits = 1024 bits
    input wire signed [16*64-1:0] flat_input_flat, // MSB-first
    // Flattened output bus: 256 elements * 16 bits = 4096 bits
    output reg signed [16*256-1:0] flat_output_flat,
    output reg done
);

    // ==========================================
    // Memory untuk Parameter (Weights & Biases)
    // ==========================================
    // Total weights: 256 neuron * 64 input = 16384
    reg signed [15:0] layer1_gen_weights [0:16383]; 
    reg signed [15:0] layer1_gen_bias  [0:255];

    initial begin
        // Load data hex dari Python
        $readmemh("src/layers/hex_data/layer1_gen_weights.hex", layer1_gen_weights);
        $readmemh("src/layers/hex_data/layer1_gen_bias.hex", layer1_gen_bias);
    end

    // ==========================================
    // Sequential MAC Pipeline State
    // ==========================================
    // Outer loop: neuron index (0..255)
    // Inner loop: input index (0..63)
    // For each neuron, compute dot product over 64 inputs, then advance to next neuron
    reg [8:0] neuron_idx;  // 0..255
    reg [6:0] input_idx;   // 0..63
    reg busy;
    reg signed [31:0] accumulator;
    reg signed [31:0] bias_shifted;

    // Combinational wires for current input and product
    wire signed [15:0] current_input;
    wire signed [31:0] current_product;
    wire signed [31:0] next_acc;

    assign current_input = $signed(flat_input_flat[(input_idx+1)*16-1 -: 16]);
    assign current_product = $signed(current_input) * $signed(layer1_gen_weights[neuron_idx*64 + input_idx]);
    assign next_acc = accumulator + current_product;

    // Sequential MAC pipeline: one MAC operation per clock cycle
    // Protocol: assert `start` for one cycle to begin. Module then:
    // - Loads first neuron's bias
    // - Performs 64 MAC cycles (one per clock) for that neuron
    // - Writes output and advances to next neuron
    // - Repeats for all 256 neurons
    // When neuron_idx wraps past 255, asserts `done`.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            neuron_idx <= 9'd0;
            input_idx <= 7'd0;
            accumulator <= 32'sd0;
            bias_shifted <= 32'sd0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            if (start && !busy) begin
                // Start a new computation: begin with neuron 0, input 0, load bias
                neuron_idx <= 9'd0;
                input_idx <= 7'd0;
                bias_shifted <= $signed(layer1_gen_bias[0]) <<< 8;
                accumulator <= $signed(layer1_gen_bias[0]) <<< 8;
                busy <= 1'b1;
                done <= 1'b0;
            end else if (busy) begin
                // Perform one MAC: accumulator += input[input_idx] * weight[neuron_idx*64 + input_idx]
                accumulator <= next_acc;

                if (input_idx == 7'd63) begin
                    // Finished all 64 inputs for this neuron; write output and advance neuron
                    flat_output_flat[(neuron_idx+1)*16-1 -: 16] <= next_acc[23:8]; // scale Q16.16 -> Q8.8
                    
                    if (neuron_idx == 9'd255) begin
                        // All 256 neurons done
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        // Advance to next neuron
                        neuron_idx <= neuron_idx + 1'b1;
                        bias_shifted <= $signed(layer1_gen_bias[neuron_idx + 1]) <<< 8;
                        accumulator <= $signed(layer1_gen_bias[neuron_idx + 1]) <<< 8;
                        input_idx <= 7'd0;
                    end
                end else begin
                    // Continue with next input for same neuron
                    input_idx <= input_idx + 1'b1;
                end
            end else begin
                // idle: clear done after one cycle so user can pulse start again
                if (done)
                    done <= 1'b0;
            end
        end
    end

endmodule