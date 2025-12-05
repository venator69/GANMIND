`timescale 1ns / 1ps

`ifndef SIGMOID_APPROX_V
`define SIGMOID_APPROX_V

// -----------------------------------------------------------------------------
// sigmoid_approx
// -----------------------------------------------------------------------------
// Hardware-friendly approximation of the sigmoid activation. The block uses a
// simple affine mapping with saturation which is sufficient for fixed-point
// inference while avoiding expensive exponentials.
// -----------------------------------------------------------------------------
module sigmoid_approx #(
    parameter integer DATA_WIDTH = 16,
    parameter integer Q_FRAC     = 8,
    parameter integer SAT_LIMIT  = 1024 // ~4.0 in Q8.8
) (
    input  wire signed [DATA_WIDTH-1:0] data_in,
    output reg  signed [DATA_WIDTH-1:0] data_out
);

    localparam signed [DATA_WIDTH-1:0] ONE_Q  = (1 << Q_FRAC);
    localparam signed [DATA_WIDTH-1:0] HALF_Q = (1 << (Q_FRAC-1));

    wire signed [DATA_WIDTH+1:0] scaled = data_in >>> 2; // divide by 4
    wire signed [DATA_WIDTH+1:0] approx = HALF_Q + scaled;

    always @(*) begin
        if (data_in >= SAT_LIMIT)
            data_out = ONE_Q;
        else if (data_in <= -SAT_LIMIT)
            data_out = {DATA_WIDTH{1'b0}};
        else if (approx < 0)
            data_out = {DATA_WIDTH{1'b0}};
        else if (approx > ONE_Q)
            data_out = ONE_Q;
        else
            data_out = approx[DATA_WIDTH-1:0];
    end

endmodule

`endif // SIGMOID_APPROX_V
