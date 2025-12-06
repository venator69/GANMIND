`timescale 1ns / 1ps

`ifndef DISCRIMINATOR_PIPELINE_V
`define DISCRIMINATOR_PIPELINE_V

// -----------------------------------------------------------------------------
// Guarded local includes so synthesizing this file in isolation automatically
// pulls in its dependencies without creating duplicate-definition conflicts
// when higher levels already provide them.
// -----------------------------------------------------------------------------
`ifndef DISCRIMINATOR_PIPELINE_SYNC_FIFO_INCLUDED
`define DISCRIMINATOR_PIPELINE_SYNC_FIFO_INCLUDED
`include "../fifo/sync_fifo.v"
`endif

`ifndef DISCRIMINATOR_PIPELINE_LAYER1_INCLUDED
`define DISCRIMINATOR_PIPELINE_LAYER1_INCLUDED
`include "../layers/layer1_discriminator.v"
`endif

`ifndef DISCRIMINATOR_PIPELINE_LAYER2_INCLUDED
`define DISCRIMINATOR_PIPELINE_LAYER2_INCLUDED
`include "../layers/layer2_discriminator.v"
`endif

`ifndef DISCRIMINATOR_PIPELINE_LAYER3_INCLUDED
`define DISCRIMINATOR_PIPELINE_LAYER3_INCLUDED
`include "../layers/layer3_discriminator.v"
`endif

// -----------------------------------------------------------------------------
// discriminator_pipeline
// -----------------------------------------------------------------------------
// Sequential controller for discriminator layer stack. The block captures the
// final score and decision bit so the top level can serialize requests.
// -----------------------------------------------------------------------------
module discriminator_pipeline (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    start,
    input  wire                    sample_wr_en,
    input  wire [15:0]             sample_wr_data,
    output wire                    sample_full,
    output wire [8:0]              sample_level,
    input  wire                    score_rd_en,
    output wire [15:0]             score_rd_data,
    output wire                    score_rd_valid,
    output wire                    score_empty,
    output wire [2:0]              score_level,
    output reg                     disc_real_flag,
    output reg                     busy,
    output reg                     done
);

    localparam integer SAMPLE_COUNT = 256;

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

    wire [16*128-1:0] l1_out;
    wire l1_done;
    wire [16*32-1:0]  l2_out;
    wire l2_done;
    wire signed [15:0] l3_score;
    wire l3_decision;
    wire l3_done;

    reg [16*SAMPLE_COUNT-1:0] sample_buffer;
    reg [8:0]                 sample_load_idx;

    wire [15:0] sample_fifo_rd_data;
    wire        sample_fifo_rd_valid;
    reg         sample_fifo_rd_en;
    wire        sample_fifo_empty;
    wire        sample_fifo_full;
    wire [8:0]  sample_fifo_level_int;

    wire [15:0] score_fifo_rd_data;
    wire        score_fifo_rd_valid;
    wire        score_fifo_empty;
    wire        score_fifo_full;
    wire [2:0]  score_fifo_level_int;
    reg  [15:0] score_fifo_wr_data;
    reg         score_fifo_wr_en;

    assign sample_full  = sample_fifo_full;
    assign sample_level = sample_fifo_level_int;
    assign score_rd_data  = score_fifo_rd_data;
    assign score_rd_valid = score_fifo_rd_valid;
    assign score_empty    = score_fifo_empty;
    assign score_level    = score_fifo_level_int;

    sync_fifo #(
        .DATA_WIDTH (16),
        .DEPTH      (SAMPLE_COUNT),
        .ADDR_WIDTH (8)
    ) u_sample_fifo (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (sample_wr_en),
        .rd_en    (sample_fifo_rd_en),
        .wr_data  (sample_wr_data),
        .rd_data  (sample_fifo_rd_data),
        .rd_valid (sample_fifo_rd_valid),
        .full     (sample_fifo_full),
        .empty    (sample_fifo_empty),
        .level    (sample_fifo_level_int)
    );

    sync_fifo #(
        .DATA_WIDTH (16),
        .DEPTH      (4),
        .ADDR_WIDTH (2)
    ) u_score_fifo (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (score_fifo_wr_en),
        .rd_en    (score_rd_en),
        .wr_data  (score_fifo_wr_data),
        .rd_data  (score_fifo_rd_data),
        .rd_valid (score_fifo_rd_valid),
        .full     (score_fifo_full),
        .empty    (score_fifo_empty),
        .level    (score_fifo_level_int)
    );

    layer1_discriminator u_l1 (
        .clk             (clk),
        .rst             (rst),
        .start           (start_l1),
        .flat_input_flat (sample_buffer),
        .flat_output_flat(l1_out),
        .done            (l1_done)
    );

    layer2_discriminator u_l2 (
        .clk             (clk),
        .rst             (rst),
        .start           (start_l2),
        .flat_input_flat (l1_out),
        .flat_output_flat(l2_out),
        .done            (l2_done)
    );

    layer3_discriminator u_l3 (
        .clk        (clk),
        .rst        (rst),
        .start      (start_l3),
        .flat_input_flat(l2_out),
        .score_out  (l3_score),
        .decision_real(l3_decision),
        .done       (l3_done)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state             <= IDLE;
            start_l1          <= 1'b0;
            start_l2          <= 1'b0;
            start_l3          <= 1'b0;
            disc_real_flag    <= 1'b0;
            busy              <= 1'b0;
            done              <= 1'b0;
            sample_fifo_rd_en <= 1'b0;
            sample_load_idx   <= 0;
            sample_buffer     <= {16*SAMPLE_COUNT{1'b0}};
            score_fifo_wr_en  <= 1'b0;
            score_fifo_wr_data<= 16'sd0;
        end else begin
            start_l1          <= 1'b0;
            start_l2          <= 1'b0;
            start_l3          <= 1'b0;
            sample_fifo_rd_en <= 1'b0;
            score_fifo_wr_en  <= 1'b0;
            done              <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start && (sample_fifo_level_int >= SAMPLE_COUNT) && !score_fifo_full) begin
                        busy            <= 1'b1;
                        sample_load_idx <= 0;
                        state           <= LOAD;
                    end
                end

                LOAD: begin
                    busy <= 1'b1;
                    if (!sample_fifo_empty && sample_load_idx < SAMPLE_COUNT) begin
                        sample_fifo_rd_en <= 1'b1;
                    end
                    if (sample_fifo_rd_valid) begin
                        sample_buffer[(sample_load_idx+1)*16-1 -: 16] <= sample_fifo_rd_data;
                        if (sample_load_idx == SAMPLE_COUNT-1) begin
                            start_l1 <= 1'b1;
                            state    <= L1;
                        end else begin
                            sample_load_idx <= sample_load_idx + 1'b1;
                        end
                    end
                end

                L1: begin
                    busy <= 1'b1;
                    if (l1_done) begin
                        start_l2 <= 1'b1;
                        state    <= L2;
                    end
                end

                L2: begin
                    busy <= 1'b1;
                    if (l2_done) begin
                        start_l3 <= 1'b1;
                        state    <= L3;
                    end
                end

                L3: begin
                    busy <= 1'b1;
                    if (l3_done) begin
                        disc_real_flag   <= l3_decision;
                        score_fifo_wr_data <= l3_score;
                        state            <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    busy <= 1'b1;
                    if (!score_fifo_full) begin
                        score_fifo_wr_en <= 1'b1;
                        state            <= FIN;
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

`endif // DISCRIMINATOR_PIPELINE_V
