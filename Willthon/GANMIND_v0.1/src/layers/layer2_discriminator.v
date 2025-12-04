`ifndef HEX_DATA_ROOT
`define HEX_DATA_ROOT "src/layers/hex_data"
`endif

module layer2_discriminator (
    input wire clk,
    input wire rst,
    input wire start,
    // Flattened input bus: 128 elements * 16 bits = 2048 bits
    input wire signed [16*128-1:0] flat_input_flat,
    // Flattened output bus: 32 elements * 16 bits = 512 bits
    output reg signed [16*32-1:0] flat_output_flat,
    output reg done
);

    // ==========================================
    // Memory untuk Parameter (Weights & Biases)
    // ==========================================
    // Total weights: 32 neuron * 128 input = 4096
    reg signed [15:0] layer2_disc_weights [0:4095]; 
    reg signed [15:0] layer2_disc_bias  [0:31];

    initial begin
        // Load data hex dari hex_data directory (expanded format)
        $readmemh({`HEX_DATA_ROOT,"/Discriminator_Layer2_Weights_All.hex"}, layer2_disc_weights);
        $readmemh({`HEX_DATA_ROOT,"/Discriminator_Layer2_Biases_All.hex"}, layer2_disc_bias);
    end

    // ==========================================
    // Sequential MAC Pipeline State
    // ==========================================
    // Outer loop: neuron index (0..31)
    // Inner loop: input index (0..127)
    // For each neuron, compute dot product over 128 inputs, then advance to next neuron
    reg [5:0] neuron_idx;   // 0..31
    reg [7:0] input_idx;    // 0..127
    reg busy;
    reg signed [31:0] accumulator;
    reg signed [31:0] bias_shifted;

    // Combinational wires for current input and product
    wire signed [15:0] current_input;
    wire signed [31:0] current_product;
    wire signed [31:0] next_acc;

    assign current_input = $signed(flat_input_flat[(input_idx+1)*16-1 -: 16]);
    assign current_product = $signed(current_input) * $signed(layer2_disc_weights[neuron_idx*128 + input_idx]);
    assign next_acc = accumulator + current_product;

    // Sequential MAC pipeline: one MAC operation per clock cycle
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            neuron_idx <= 6'd0;
            input_idx <= 8'd0;
            accumulator <= 32'sd0;
            bias_shifted <= 32'sd0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            if (start && !busy) begin
                // Start a new computation: begin with neuron 0, input 0, load bias
                neuron_idx <= 6'd0;
                input_idx <= 8'd0;
                bias_shifted <= $signed(layer2_disc_bias[0]) <<< 8;
                accumulator <= $signed(layer2_disc_bias[0]) <<< 8;
                busy <= 1'b1;
                done <= 1'b0;
            end else if (busy) begin
                // Perform one MAC: accumulator += input[input_idx] * weight[neuron_idx*128 + input_idx]
                accumulator <= next_acc;

                if (input_idx == 8'd127) begin
                    // Finished all 128 inputs for this neuron; write output and advance neuron
                    flat_output_flat[(neuron_idx+1)*16-1 -: 16] <= next_acc[23:8]; // scale Q16.16 -> Q8.8
                    
                    if (neuron_idx == 6'd31) begin
                        // All 32 neurons done
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        // Advance to next neuron
                        neuron_idx <= neuron_idx + 1'b1;
                        bias_shifted <= $signed(layer2_disc_bias[neuron_idx + 1]) <<< 8;
                        accumulator <= $signed(layer2_disc_bias[neuron_idx + 1]) <<< 8;
                        input_idx <= 8'd0;
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
