`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// generator_pipeline
// -----------------------------------------------------------------------------
// Chained controller that pulses the previously verified generator layers in
// sequence. Each layer reuses the heavy MAC engines, so only a light-weight
// FSM is required here.
// -----------------------------------------------------------------------------
module generator_pipeline (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      start,
    input  wire                      seed_wr_en,
    input  wire [15:0]               seed_wr_data,
    output wire                      seed_full,
    output wire [6:0]                seed_level,
    input  wire                      feature_rd_en,
    output wire [15:0]               feature_rd_data,
    output wire                      feature_rd_valid,
    output wire                      feature_empty,
    output wire [7:0]                feature_level,
    output reg                       busy,
    output reg                       done
);

    localparam integer SEED_COUNT    = 64;
    localparam integer FEATURE_COUNT = 128;

    localparam IDLE   = 3'd0;
    localparam LOAD   = 3'd1;
    localparam L1     = 3'd2;
    localparam L2     = 3'd3;
    localparam L3     = 3'd4;
    localparam OUTPUT = 3'd5;
    localparam FIN    = 3'd6;

    reg [2:0] state;
    reg start_l1,
        start_l2,
        start_l3;

    wire [16*256-1:0] layer1_out;
    wire               layer1_done;
    wire [16*256-1:0] layer2_out;
    wire               layer2_done;
    wire [16*128-1:0] layer3_out;
    wire               layer3_done;

    // ---------------------------------------------------------------------
    // FIFO plumbing so the interface only exposes 16-bit lanes instead of
    // large flattened vectors.
    // ---------------------------------------------------------------------
    reg [16*SEED_COUNT-1:0] seed_buffer;
    reg [6:0]               seed_load_idx;
    reg [7:0]               feature_store_idx;

    wire [15:0] seed_fifo_rd_data;
    wire        seed_fifo_rd_valid;
    reg         seed_fifo_rd_en;
    wire        seed_fifo_empty;
    wire        seed_fifo_full;
    wire [6:0]  seed_fifo_level_int;

    wire [15:0] feature_fifo_rd_data;
    wire        feature_fifo_rd_valid;
    wire        feature_fifo_empty;
    wire        feature_fifo_full;
    wire [7:0]  feature_fifo_level_int;
    reg  [15:0] feature_fifo_wr_data;
    reg         feature_fifo_wr_en;

    assign seed_full   = seed_fifo_full;
    assign seed_level  = seed_fifo_level_int;
    assign feature_rd_data  = feature_fifo_rd_data;
    assign feature_rd_valid = feature_fifo_rd_valid;
    assign feature_empty    = feature_fifo_empty;
    assign feature_level    = feature_fifo_level_int;

    sync_fifo #(
        .DATA_WIDTH (16),
        .DEPTH      (SEED_COUNT),
        .ADDR_WIDTH (6)
    ) u_seed_fifo (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (seed_wr_en),
        .rd_en    (seed_fifo_rd_en),
        .wr_data  (seed_wr_data),
        .rd_data  (seed_fifo_rd_data),
        .rd_valid (seed_fifo_rd_valid),
        .full     (seed_fifo_full),
        .empty    (seed_fifo_empty),
        .level    (seed_fifo_level_int)
    );

    sync_fifo #(
        .DATA_WIDTH (16),
        .DEPTH      (FEATURE_COUNT),
        .ADDR_WIDTH (7)
    ) u_feature_fifo (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (feature_fifo_wr_en),
        .rd_en    (feature_rd_en),
        .wr_data  (feature_fifo_wr_data),
        .rd_data  (feature_fifo_rd_data),
        .rd_valid (feature_fifo_rd_valid),
        .full     (feature_fifo_full),
        .empty    (feature_fifo_empty),
        .level    (feature_fifo_level_int)
    );

    layer1_generator u_l1 (
        .clk            (clk),
        .rst            (rst),
        .start          (start_l1),
        .flat_input_flat(seed_buffer),
        .flat_output_flat(layer1_out),
        .done           (layer1_done)
    );

    layer2_generator u_l2 (
        .clk            (clk),
        .rst            (rst),
        .start          (start_l2),
        .flat_input_flat(layer1_out),
        .flat_output_flat(layer2_out),
        .done           (layer2_done)
    );

    layer3_generator u_l3 (
        .clk            (clk),
        .rst            (rst),
        .start          (start_l3),
        .flat_input_flat(layer2_out),
        .flat_output_flat(layer3_out),
        .done           (layer3_done)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= IDLE;
            start_l1          <= 1'b0;
            start_l2          <= 1'b0;
            start_l3          <= 1'b0;
            busy              <= 1'b0;
            done              <= 1'b0;
            seed_fifo_rd_en   <= 1'b0;
            feature_fifo_wr_en<= 1'b0;
            seed_load_idx     <= 0;
            feature_store_idx <= 0;
            seed_buffer       <= {16*SEED_COUNT{1'b0}};
        end else begin
            start_l1          <= 1'b0;
            start_l2          <= 1'b0;
            start_l3          <= 1'b0;
            seed_fifo_rd_en   <= 1'b0;
            feature_fifo_wr_en<= 1'b0;
            done              <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start && (seed_fifo_level_int >= SEED_COUNT) && feature_fifo_empty) begin
                        busy          <= 1'b1;
                        seed_load_idx <= 0;
                        state         <= LOAD;
                    end
                end

                LOAD: begin
                    busy <= 1'b1;
                    if (!seed_fifo_empty && seed_load_idx < SEED_COUNT) begin
                        seed_fifo_rd_en <= 1'b1;
                    end
                    if (seed_fifo_rd_valid) begin
                        seed_buffer[(seed_load_idx+1)*16-1 -: 16] <= seed_fifo_rd_data;
                        if (seed_load_idx == SEED_COUNT-1) begin
                            start_l1 <= 1'b1;
                            state    <= L1;
                        end else begin
                            seed_load_idx <= seed_load_idx + 1'b1;
                        end
                    end
                end

                L1: begin
                    busy <= 1'b1;
                    if (layer1_done) begin
                        start_l2 <= 1'b1;
                        state    <= L2;
                    end
                end

                L2: begin
                    busy <= 1'b1;
                    if (layer2_done) begin
                        start_l3 <= 1'b1;
                        state    <= L3;
                    end
                end

                L3: begin
                    busy <= 1'b1;
                    if (layer3_done) begin
                        feature_store_idx <= 0;
                        state             <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    busy <= 1'b1;
                    if (!feature_fifo_full) begin
                        feature_fifo_wr_en   <= 1'b1;
                        feature_fifo_wr_data <= layer3_out[(feature_store_idx+1)*16-1 -: 16];
                        if (feature_store_idx == FEATURE_COUNT-1) begin
                            state <= FIN;
                        end else begin
                            feature_store_idx <= feature_store_idx + 1'b1;
                        end
                    end
                end

                FIN: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    busy  <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
