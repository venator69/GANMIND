`timescale 1ns / 1ps

// Simple synchronous FIFO used to buffer serialized pixel stream data.
// The implementation is parameterized so it can be shared across blocks
// that need to trade logic for BRAM usage.
module sync_fifo #(
    parameter integer DATA_WIDTH = 16,
    parameter integer DEPTH = 1024,
    parameter integer ADDR_WIDTH = 10
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     wr_en,
    input  wire                     rd_en,
    input  wire [DATA_WIDTH-1:0]    wr_data,
    output reg  [DATA_WIDTH-1:0]    rd_data,
    output reg                      rd_valid,
    output reg                      full,
    output reg                      empty,
    output reg  [ADDR_WIDTH:0]      level
);

    // Basic parameter guard to help catch mismatch early (sim-only).
`ifndef SYNTHESIS
    initial begin
        if ((1 << ADDR_WIDTH) < DEPTH)
            $error("sync_fifo: ADDR_WIDTH (%0d) is too small for DEPTH %0d", ADDR_WIDTH, DEPTH);
    end
`endif

    // ------------------------------------------------------------
    // Storage elements
    // ------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;

    wire wr_do = wr_en && !full;
    wire rd_do = rd_en && !empty;

    reg [ADDR_WIDTH:0] count_next;

    always @(*) begin
        count_next = count;
        case ({wr_do, rd_do})
            2'b10: count_next = count + 1'b1;
            2'b01: count_next = count - 1'b1;
            default: count_next = count;
        endcase
    end

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_data  <= {DATA_WIDTH{1'b0}};
            rd_valid <= 1'b0;
            wr_ptr   <= {ADDR_WIDTH{1'b0}};
            rd_ptr   <= {ADDR_WIDTH{1'b0}};
            count    <= {ADDR_WIDTH+1{1'b0}};
            full     <= 1'b0;
            empty    <= 1'b1;
            level    <= {ADDR_WIDTH+1{1'b0}};
        end else begin
            rd_valid <= 1'b0;

            if (wr_do) begin
                mem[wr_ptr] <= wr_data;
                if (wr_ptr == DEPTH-1)
                    wr_ptr <= {ADDR_WIDTH{1'b0}};
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            if (rd_do) begin
                rd_data <= mem[rd_ptr];
                rd_valid <= 1'b1;
                if (rd_ptr == DEPTH-1)
                    rd_ptr <= {ADDR_WIDTH{1'b0}};
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            count <= count_next;
            level <= count_next;
            full  <= (count_next == DEPTH);
            empty <= (count_next == 0);
        end
    end

endmodule
