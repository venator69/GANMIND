`ifndef LAYER1_GENERATOR_V
`define LAYER1_GENERATOR_V

`ifndef HEX_DATA_ROOT
`define HEX_DATA_ROOT "D:/GANMIND/GANMIND/Willthon/GANMIND/src/layers/hex_data"
`endif

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
    (* rom_style = "block" *) reg signed [15:0] layer1_gen_weights [0:16383]; 
    (* rom_style = "block" *) reg signed [15:0] layer1_gen_bias  [0:255];

    localparam integer TOTAL_NEURONS = 256;
    localparam integer TOTAL_INPUTS  = 64;
    localparam integer LAST_NEURON   = TOTAL_NEURONS - 1;
    localparam integer LAST_INPUT    = TOTAL_INPUTS - 1;
    localparam integer WEIGHT_ADDR_WIDTH = 14; // 2^14 = 16384

    localparam MAC_PHASE_ISSUE = 1'b0;
    localparam MAC_PHASE_ACCUM = 1'b1;

    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg                         mac_phase;
    reg signed [15:0]           input_sample_reg;
    reg signed [15:0]           weight_data;
    reg signed [31:0]           mac_result;

    initial begin
        // Load data hex dari Python
        $readmemh({`HEX_DATA_ROOT,"/layer1_gen_weights.hex"}, layer1_gen_weights);
        $readmemh({`HEX_DATA_ROOT,"/layer1_gen_bias.hex"}, layer1_gen_bias);
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

    always @(posedge clk) begin
        if (rst) begin
            weight_data <= 16'sd0;
        end else begin
            weight_data <= layer1_gen_weights[weight_addr];
        end
    end

    // Sequential MAC pipeline: one MAC operation per clock cycle
    // Protocol: assert `start` for one cycle to begin. Module then:
    // - Loads first neuron's bias
    // - Performs 64 MAC cycles (one per clock) for that neuron
    // - Writes output and advances to next neuron
    // - Repeats for all 256 neurons
    // When neuron_idx wraps past 255, asserts `done`.
    always @(posedge clk) begin
        if (rst) begin
            neuron_idx        <= 9'd0;
            input_idx         <= 7'd0;
            accumulator       <= 32'sd0;
            busy              <= 1'b0;
            done              <= 1'b0;
            flat_output_flat  <= {16*256{1'b0}};
            weight_addr       <= {WEIGHT_ADDR_WIDTH{1'b0}};
            mac_phase         <= MAC_PHASE_ISSUE;
            input_sample_reg  <= 16'sd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                neuron_idx       <= 9'd0;
                input_idx        <= 7'd0;
                accumulator      <= $signed(layer1_gen_bias[0]) <<< 8;
                busy             <= 1'b1;
                mac_phase        <= MAC_PHASE_ISSUE;
                weight_addr      <= {WEIGHT_ADDR_WIDTH{1'b0}};
            end else if (busy) begin
                case (mac_phase)
                    MAC_PHASE_ISSUE: begin
                        input_sample_reg <= flat_input_flat[(input_idx+1)*16-1 -: 16];
                        mac_phase        <= MAC_PHASE_ACCUM;
                    end

                    MAC_PHASE_ACCUM: begin
                        mac_result = accumulator + $signed(input_sample_reg) * $signed(weight_data);
                        mac_phase  <= MAC_PHASE_ISSUE;

                        if (input_idx == LAST_INPUT) begin
                            flat_output_flat[(neuron_idx+1)*16-1 -: 16] <= mac_result[23:8];

                            if (neuron_idx == LAST_NEURON) begin
                                busy <= 1'b0;
                                done <= 1'b1;
                            end else begin
                                neuron_idx  <= neuron_idx + 1'b1;
                                input_idx   <= 7'd0;
                                accumulator <= $signed(layer1_gen_bias[neuron_idx + 1]) <<< 8;
                            end
                        end else begin
                            input_idx   <= input_idx + 1'b1;
                            accumulator <= mac_result;
                        end

                        if (!(input_idx == LAST_INPUT && neuron_idx == LAST_NEURON))
                            weight_addr <= weight_addr + 1'b1;
                    end
                endcase
            end else begin
                mac_phase <= MAC_PHASE_ISSUE;
            end
        end
    end

endmodule

`endif // LAYER1_GENERATOR_V