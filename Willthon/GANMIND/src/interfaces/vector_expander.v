`timescale 1ns / 1ps

`ifndef VECTOR_EXPANDER_V
`define VECTOR_EXPANDER_V

// -----------------------------------------------------------------------------
// vector_expander
// -----------------------------------------------------------------------------
//  * Maps a smaller latent vector produced by the generator to the input width
//    required by the discriminator without introducing additional math.
//  * Sequential shared-hardware mover compatible with the start/busy/done
//    control plane used across the pipeline.
// -----------------------------------------------------------------------------
module vector_expander #(
    parameter integer INPUT_COUNT  = 128,
    parameter integer OUTPUT_COUNT = 256,
    parameter integer DATA_WIDTH   = 16
) (
    input  wire                             clk,
    input  wire                             rst,
    input  wire                             start,
    input  wire [DATA_WIDTH*INPUT_COUNT-1:0]  vector_in,
    output reg  [DATA_WIDTH*OUTPUT_COUNT-1:0] vector_out,
    output reg                              busy,
    output reg                              done
);

`ifndef SYNTHESIS
    initial begin
        if (INPUT_COUNT <= 0 || OUTPUT_COUNT <= 0)
            $error("vector_expander: INPUT_COUNT/OUTPUT_COUNT must be > 0");
    end
`endif

    function integer calc_clog2;
        input integer value;
        integer i;
        begin
            calc_clog2 = 0;
            for (i = value-1; i > 0; i = i >> 1)
                calc_clog2 = calc_clog2 + 1;
        end
    endfunction

    localparam integer OUT_IDX_WIDTH = (calc_clog2(OUTPUT_COUNT) == 0) ? 1 : calc_clog2(OUTPUT_COUNT);
    localparam integer IN_IDX_WIDTH  = (calc_clog2(INPUT_COUNT)  == 0) ? 1 : calc_clog2(INPUT_COUNT);

    reg [IN_IDX_WIDTH-1:0] src_index_lut [0:OUTPUT_COUNT-1];
    integer lut_idx;
    initial begin
        for (lut_idx = 0; lut_idx < OUTPUT_COUNT; lut_idx = lut_idx + 1)
            src_index_lut[lut_idx] = (lut_idx * INPUT_COUNT) / OUTPUT_COUNT;
    end

    reg [OUT_IDX_WIDTH-1:0] out_idx;
    reg processing;
    reg [DATA_WIDTH*INPUT_COUNT-1:0] input_buffer;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            vector_out   <= {DATA_WIDTH*OUTPUT_COUNT{1'b0}};
            busy         <= 1'b0;
            done         <= 1'b0;
            processing   <= 1'b0;
            out_idx      <= {OUT_IDX_WIDTH{1'b0}};
            input_buffer <= {DATA_WIDTH*INPUT_COUNT{1'b0}};
        end else begin
            done <= 1'b0;

            if (start && !processing) begin
                processing   <= 1'b1;
                busy         <= 1'b1;
                out_idx      <= {OUT_IDX_WIDTH{1'b0}};
                input_buffer <= vector_in;
            end else if (processing) begin
                vector_out[(out_idx+1)*DATA_WIDTH-1 -: DATA_WIDTH] <=
                    input_buffer[(src_index_lut[out_idx]+1)*DATA_WIDTH-1 -: DATA_WIDTH];

                if (out_idx == OUTPUT_COUNT-1) begin
                    processing <= 1'b0;
                    busy       <= 1'b0;
                    done       <= 1'b1;
                end else begin
                    out_idx <= out_idx + 1'b1;
                end
            end else begin
                busy <= 1'b0;
            end
        end
    end

endmodule

`endif // VECTOR_EXPANDER_V