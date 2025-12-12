`ifndef LAYER1_DISCRIMINATOR_V
`define LAYER1_DISCRIMINATOR_V

`ifndef HEX_DATA_ROOT
`define HEX_DATA_ROOT "D:/GANMIND/GANMIND/Willthon/GANMIND/src/layers/hex_data"
`endif

module layer1_discriminator (
    input wire clk,
    input wire rst,
    input wire start,
    // Flattened input bus: 256 elements * 16 bits = 4096 bits
    input wire signed [16*256-1:0] flat_input_flat,
    // Flattened output bus: 128 elements * 16 bits = 2048 bits
    output reg signed [16*128-1:0] flat_output_flat,
    output reg done
);

    // ==========================================
    // Memory untuk Parameter (Weights & Biases)
    // ==========================================
    // Total weights: 128 neuron * 256 input = 32768
    (* rom_style = "block" *) reg signed [15:0] layer1_disc_weights [0:32767]; 
    (* rom_style = "block" *) reg signed [15:0] layer1_disc_bias  [0:127];

    localparam integer TOTAL_NEURONS = 128;
    localparam integer TOTAL_INPUTS  = 256;
    localparam integer LAST_NEURON   = TOTAL_NEURONS - 1;
    localparam integer LAST_INPUT    = TOTAL_INPUTS - 1;
    localparam integer WEIGHT_ADDR_WIDTH = 15; // 2^15 = 32768

    localparam MAC_PHASE_ISSUE = 1'b0;
    localparam MAC_PHASE_ACCUM = 1'b1;

    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr;
    reg                         mac_phase;
    reg signed [15:0]           input_sample_reg;
    reg signed [15:0]           weight_data;
    reg signed [31:0]           mac_result;

    initial begin
        // Load data hex dari hex_data directory (expanded format)
        $readmemh({`HEX_DATA_ROOT,"/Discriminator_Layer1_Weights_All.hex"}, layer1_disc_weights);
        $readmemh({`HEX_DATA_ROOT,"/Discriminator_Layer1_Biases_All.hex"}, layer1_disc_bias);
    end

    // ==========================================
    // Sequential MAC Pipeline State
    // ==========================================
    reg [7:0] neuron_idx;   // 0..127
    reg [8:0] input_idx;    // 0..255
    reg busy;
    reg signed [31:0] accumulator;

    always @(posedge clk) begin
        if (rst) begin
            weight_data <= 16'sd0;
        end else begin
            weight_data <= layer1_disc_weights[weight_addr];
        end
    end

    // Sequential MAC pipeline: 2-phase issue/accumulate loop for BRAM weights
    always @(posedge clk) begin
        if (rst) begin
            neuron_idx       <= 8'd0;
            input_idx        <= 9'd0;
            accumulator      <= 32'sd0;
            busy             <= 1'b0;
            done             <= 1'b0;
            flat_output_flat <= {16*128{1'b0}};
            weight_addr      <= {WEIGHT_ADDR_WIDTH{1'b0}};
            mac_phase        <= MAC_PHASE_ISSUE;
            input_sample_reg <= 16'sd0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                neuron_idx  <= 8'd0;
                input_idx   <= 9'd0;
                accumulator <= $signed(layer1_disc_bias[0]) <<< 8;
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
                                input_idx   <= 9'd0;
                                accumulator <= $signed(layer1_disc_bias[neuron_idx + 1]) <<< 8;
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

`endif // LAYER1_DISCRIMINATOR_V
