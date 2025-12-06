`timescale 1ns / 1ps

`ifndef VECTOR_SIGMOID_V
`define VECTOR_SIGMOID_V

// -----------------------------------------------------------------------------
// Guarded include to pull in sigmoid_approx when this module is synthesized in
// isolation while remaining compatible with higher-level builds.
// -----------------------------------------------------------------------------
`ifndef VECTOR_SIGMOID_SIGMOID_APPROX_INCLUDED
`define VECTOR_SIGMOID_SIGMOID_APPROX_INCLUDED
`include "sigmoid_approx.v"
`endif

// -----------------------------------------------------------------------------
// vector_sigmoid
// -----------------------------------------------------------------------------
// Applies the sigmoid approximation element-wise to a flattened vector using a
// single shared sigmoid_approx instance. The block streams one element per
// cycle, writes the results into an output buffer, and asserts done when all
// ELEMENT_COUNT samples are processed. This keeps the hardware small and fully
// synthesizable for FPGA/ASIC targets.
// -----------------------------------------------------------------------------
module vector_sigmoid #(
    parameter integer ELEMENT_COUNT = 128,
    parameter integer DATA_WIDTH    = 16,
    parameter integer Q_FRAC        = 8
) (
    input  wire                             clk,
    input  wire                             rst,
    input  wire                             start,
    input  wire [DATA_WIDTH*ELEMENT_COUNT-1:0] data_in,
    output reg  [DATA_WIDTH*ELEMENT_COUNT-1:0] data_out,
    output reg                              busy,
    output reg                              done
);

`ifndef SYNTHESIS
    initial begin
        if (ELEMENT_COUNT <= 0)
            $error("vector_sigmoid: ELEMENT_COUNT must be > 0");
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

    localparam integer INDEX_WIDTH = (calc_clog2(ELEMENT_COUNT) == 0) ? 1 : calc_clog2(ELEMENT_COUNT);

    reg processing;
    reg stage_valid;
    reg feed_pending;
    reg [INDEX_WIDTH:0] feed_idx;
    reg [INDEX_WIDTH:0] capture_idx;

    reg  signed [DATA_WIDTH-1:0] sigmoid_in;
    wire signed [DATA_WIDTH-1:0] sigmoid_out;

    sigmoid_approx #(
        .DATA_WIDTH (DATA_WIDTH),
        .Q_FRAC     (Q_FRAC)
    ) shared_sigmoid (
        .data_in  (sigmoid_in),
        .data_out (sigmoid_out)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy        <= 1'b0;
            done        <= 1'b0;
            processing  <= 1'b0;
            stage_valid <= 1'b0;
            feed_pending<= 1'b0;
            feed_idx    <= {INDEX_WIDTH+1{1'b0}};
            capture_idx <= {INDEX_WIDTH+1{1'b0}};
            sigmoid_in  <= {DATA_WIDTH{1'b0}};
            data_out    <= {DATA_WIDTH*ELEMENT_COUNT{1'b0}};
        end else begin
            done <= 1'b0;

            if (start && !processing) begin
                processing   <= 1'b1;
                busy         <= 1'b1;
                stage_valid  <= 1'b0;
                capture_idx  <= {INDEX_WIDTH+1{1'b0}};
                feed_idx     <= (ELEMENT_COUNT > 1) ? {{INDEX_WIDTH{1'b0}}, 1'b1} : {INDEX_WIDTH+1{1'b0}};
                feed_pending <= (ELEMENT_COUNT > 1);
                sigmoid_in   <= data_in[0*DATA_WIDTH +: DATA_WIDTH];
            end else if (processing) begin
                if (stage_valid) begin
                    data_out[capture_idx*DATA_WIDTH +: DATA_WIDTH] <= sigmoid_out;
                    if (capture_idx == ELEMENT_COUNT-1) begin
                        processing  <= 1'b0;
                        busy        <= 1'b0;
                        done        <= 1'b1;
                        stage_valid <= 1'b0;
                    end else begin
                        capture_idx <= capture_idx + 1'b1;
                    end
                end else begin
                    stage_valid <= 1'b1;
                end

                if (feed_pending && stage_valid) begin
                    sigmoid_in <= data_in[feed_idx*DATA_WIDTH +: DATA_WIDTH];
                    if (feed_idx == ELEMENT_COUNT-1) begin
                        feed_pending <= 1'b0;
                    end else begin
                        feed_idx <= feed_idx + 1'b1;
                    end
                end
            end else begin
                busy <= 1'b0;
            end
        end
    end

endmodule

`endif // VECTOR_SIGMOID_V
