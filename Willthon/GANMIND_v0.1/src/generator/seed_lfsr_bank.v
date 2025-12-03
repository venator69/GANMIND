`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// seed_lfsr_bank
// -----------------------------------------------------------------------------
// Generates a deterministic bank of Q8.8 latent vectors using a 16-bit LFSR.
// A single start pulse captures SEED_COUNT samples over SEED_COUNT cycles to
// avoid wide combinational fanout.
// -----------------------------------------------------------------------------
module seed_lfsr_bank #(
    parameter integer SEED_COUNT = 64,
    parameter integer DATA_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         start,
    output reg  [DATA_WIDTH*SEED_COUNT-1:0] seed_flat,
    output reg                          done
);

    function integer calc_width;
        input integer value;
        integer i;
        begin
            calc_width = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                calc_width = calc_width + 1;
        end
    endfunction

    localparam integer INDEX_WIDTH = calc_width(SEED_COUNT);

    reg [DATA_WIDTH-1:0] lfsr;
    reg [INDEX_WIDTH:0] sample_idx;
    reg busy;

    wire feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr       <= 16'hACE1;
            sample_idx <= 0;
            seed_flat  <= {DATA_WIDTH*SEED_COUNT{1'b0}};
            busy       <= 1'b0;
            done       <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                busy       <= 1'b1;
                sample_idx <= 0;
                lfsr       <= 16'hACE1;
            end else if (busy) begin
                seed_flat[(sample_idx+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= lfsr;
                lfsr <= {lfsr[DATA_WIDTH-2:0], feedback};

                if (sample_idx == SEED_COUNT-1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    sample_idx <= sample_idx + 1'b1;
                end
            end
        end
    end

endmodule
