`ifndef LAYER2_DISCRIMINATOR_V
`define LAYER2_DISCRIMINATOR_V

`ifndef HEX_DATA_ROOT
`define HEX_DATA_ROOT "D:/GANMIND/GANMIND/Willthon/GANMIND/src/layers/hex_data"
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
    (* rom_style = "block" *) reg signed [15:0] layer2_disc_weights [0:4095]; 
    (* rom_style = "block" *) reg signed [15:0] layer2_disc_bias  [0:31];

    localparam integer TOTAL_NEURONS = 32;
    localparam integer TOTAL_INPUTS  = 128;
    localparam integer LAST_NEURON   = TOTAL_NEURONS - 1;
    localparam integer LAST_INPUT    = TOTAL_INPUTS - 1;
    localparam integer WEIGHT_ADDR_WIDTH = 12; // 2^12 = 4096

    localparam MAC_PHASE_ISSUE = 1'b0;
    localparam MAC_PHASE_ACCUM = 1'b1;

    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg                         mac_phase;
    reg signed [15:0]           input_sample_reg;
    reg signed [15:0]           weight_data;
    reg signed [31:0]           mac_result;

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

    always @(posedge clk) begin
        if (rst) begin
            weight_data <= 16'sd0;
        end else begin
            weight_data <= layer2_disc_weights[weight_addr];
        end
    end

    // Sequential MAC pipeline: one MAC operation per clock cycle (accounting for BRAM read latency)
    always @(posedge clk) begin
        if (rst) begin
            neuron_idx       <= 6'd0;
            input_idx        <= 8'd0;
            accumulator      <= 32'sd0;
            busy             <= 1'b0;
            done             <= 1'b0;
            flat_output_flat <= {16*32{1'b0}};
            weight_addr      <= {WEIGHT_ADDR_WIDTH{1'b0}};
            mac_phase        <= MAC_PHASE_ISSUE;
            input_sample_reg <= 16'sd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                neuron_idx  <= 6'd0;
                input_idx   <= 8'd0;
                accumulator <= $signed(layer2_disc_bias[0]) <<< 8;
                busy        <= 1'b1;
                mac_phase   <= MAC_PHASE_ISSUE;
                weight_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};
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
                                input_idx   <= 8'd0;
                                accumulator <= $signed(layer2_disc_bias[neuron_idx + 1]) <<< 8;
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

`endif // LAYER2_DISCRIMINATOR_V
