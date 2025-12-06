`timescale 1ns / 1ps

`ifndef FRAME_SAMPLER_V
`define FRAME_SAMPLER_V

// -----------------------------------------------------------------------------
// frame_sampler
// -----------------------------------------------------------------------------
//  * Down-samples a flattened frame buffer to the feature width expected by the
//    first discriminator layer with compile-time constant mapping.
//  * Each output sample simply taps one of the input samples using evenly
//    spaced indices so no additional DSP resources are required.
// -----------------------------------------------------------------------------
module frame_sampler #(
    parameter integer INPUT_COUNT  = 784,
    parameter integer OUTPUT_COUNT = 256,
    parameter integer DATA_WIDTH   = 16
) (
    input  wire                             clk,
    input  wire                             rst,
    input  wire                             start,
    input  wire [DATA_WIDTH*INPUT_COUNT-1:0]  frame_flat,
    output reg  [DATA_WIDTH*OUTPUT_COUNT-1:0] sampled_flat,
    output reg                              busy,
    output reg                              done
);

    // Basic parameter guard to catch illegal configurations early (sim only).
`ifndef SYNTHESIS
    initial begin
        if (OUTPUT_COUNT == 0 || INPUT_COUNT == 0)
            $error("frame_sampler: INPUT_COUNT and OUTPUT_COUNT must be non-zero");
    end
`endif

    localparam integer BASE_STEP = (OUTPUT_COUNT == 0) ? 0 : (INPUT_COUNT / OUTPUT_COUNT);
    localparam integer STEP_REM  = (OUTPUT_COUNT == 0) ? 0 : (INPUT_COUNT % OUTPUT_COUNT);

    reg active;
    integer out_idx;
    integer src_index;
    integer rem_accum;
    integer tmp_src;
    integer tmp_rem;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active       <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
            out_idx      <= 0;
            src_index    <= 0;
            rem_accum    <= 0;
            sampled_flat <= {DATA_WIDTH*OUTPUT_COUNT{1'b0}};
        end else begin
            done <= 1'b0;

            if (start && !active) begin
                active    <= 1'b1;
                busy      <= 1'b1;
                out_idx   <= 0;
                src_index <= 0;
                rem_accum <= 0;
            end else if (active) begin
                sampled_flat[out_idx*DATA_WIDTH +: DATA_WIDTH] <=
                    frame_flat[src_index*DATA_WIDTH +: DATA_WIDTH];

                if (out_idx == OUTPUT_COUNT-1) begin
                    active <= 1'b0;
                    busy   <= 1'b0;
                    done   <= 1'b1;
                end else begin
                    out_idx <= out_idx + 1;

                    if (STEP_REM == 0) begin
                        tmp_src = src_index + BASE_STEP;
                        if (tmp_src >= INPUT_COUNT)
                            tmp_src = INPUT_COUNT-1;
                        src_index <= tmp_src;
                        rem_accum <= 0;
                    end else begin
                        tmp_rem = rem_accum + STEP_REM;
                        tmp_src = src_index + BASE_STEP;

                        if (tmp_rem >= OUTPUT_COUNT) begin
                            tmp_rem = tmp_rem - OUTPUT_COUNT;
                            tmp_src = tmp_src + 1;
                        end

                        if (tmp_src >= INPUT_COUNT)
                            tmp_src = INPUT_COUNT-1;

                        rem_accum <= tmp_rem;
                        src_index <= tmp_src;
                    end
                end
            end else begin
                busy <= 1'b0;
            end
        end
    end

endmodule

`endif // FRAME_SAMPLER_V
