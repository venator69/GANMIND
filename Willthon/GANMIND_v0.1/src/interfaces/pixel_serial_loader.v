`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// pixel_serial_loader
// -----------------------------------------------------------------------------
//  * Accepts serialized binary pixels (1 bit) coming from an external source.
//  * Uses a BRAM-based FIFO to store incoming samples so the design does not
//    rely on large register banks.
//  * When 28x28 = 784 pixels have been collected, it expands the data into a
//    flattened Q8.8 frame that downstream GAN blocks can consume.
//  * The consumer asserts frame_consume to release the buffer for the next
//    frame; buffering for multiple frames is supported through frame_slots.
// -----------------------------------------------------------------------------
module pixel_serial_loader #(
    parameter integer PIXEL_COUNT   = 784,
    parameter integer DATA_WIDTH    = 16,
    parameter integer PIXEL_SCALE   = 8,   // number of fractional bits (Q format)
    parameter integer FIFO_DEPTH    = 1024,
    parameter integer FIFO_ADDR_W   = 10,
    parameter integer FRAME_SLOT_W  = 4    // up to 2^FRAME_SLOT_W frames queued
) (
    input  wire                             clk,
    input  wire                             rst,
    input  wire                             pixel_bit,
    input  wire                             pixel_bit_valid,
    output wire                             pixel_bit_ready,
    input  wire                             frame_consume,
    output reg                              frame_valid,
    output reg  [DATA_WIDTH*PIXEL_COUNT-1:0] frame_flat
);

    // -------------------------------------------------------------------------
    // FIFO instantiation
    // -------------------------------------------------------------------------
    wire fifo_full;
    wire fifo_empty;
    wire fifo_rd_valid;
    wire [DATA_WIDTH-1:0] fifo_rd_data;
    wire [FIFO_ADDR_W:0] fifo_level;
    wire fifo_rd_en;

    assign pixel_bit_ready = !fifo_full;
    wire pixel_accept = pixel_bit_valid && pixel_bit_ready;

    // Convert binary pixel into Q format (0.0 or 1.0)
    wire [DATA_WIDTH-1:0] fifo_din = pixel_bit ? ({{(DATA_WIDTH-PIXEL_SCALE-1){1'b0}}, 1'b1, {PIXEL_SCALE{1'b0}}})
                                              : {DATA_WIDTH{1'b0}};

    sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH),
        .ADDR_WIDTH (FIFO_ADDR_W)
    ) u_pixel_fifo (
        .clk      (clk),
        .rst      (rst),
        .wr_en    (pixel_accept),
        .rd_en    (fifo_rd_en),
        .wr_data  (fifo_din),
        .rd_data  (fifo_rd_data),
        .rd_valid (fifo_rd_valid),
        .full     (fifo_full),
        .empty    (fifo_empty),
        .level    (fifo_level)
    );

    // -------------------------------------------------------------------------
    // Frame bookkeeping: number of pixels collected per frame and how many
    // complete frames currently reside inside the FIFO.
    // -------------------------------------------------------------------------
    reg [15:0] pixel_count;
    reg [FRAME_SLOT_W:0] frame_slots;
    reg frame_dequeue_flag;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_count <= 0;
            frame_slots <= 0;
        end else begin

            if (pixel_accept) begin
                if (pixel_count == PIXEL_COUNT-1) begin
                    pixel_count <= 0;
                    frame_slots <= frame_slots + 1'b1;
                end else begin
                    pixel_count <= pixel_count + 1'b1;
                end
            end

            if (frame_dequeue_flag && frame_slots != 0)
                frame_slots <= frame_slots - 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Loader FSM: pulls PIXEL_COUNT samples out of the FIFO and expands them
    // into a flattened frame buffer.
    // -------------------------------------------------------------------------
    localparam COLLECT  = 2'd0;
    localparam LOAD_REQ = 2'd1;
    localparam LOAD_CAP = 2'd2;
    localparam READY    = 2'd3;

    reg [1:0] state;
    reg [15:0] load_idx;
    reg fifo_rd_en_r;

    assign fifo_rd_en = fifo_rd_en_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state         <= COLLECT;
            load_idx      <= 0;
            fifo_rd_en_r  <= 1'b0;
            frame_valid   <= 1'b0;
            frame_flat    <= {DATA_WIDTH*PIXEL_COUNT{1'b0}};
            frame_dequeue_flag <= 1'b0;
        end else begin
            frame_dequeue_flag <= 1'b0;
            fifo_rd_en_r <= 1'b0;

            case (state)
                COLLECT: begin
                    frame_valid <= 1'b0;
                    if (frame_slots != 0)
                        state <= LOAD_REQ;
                end

                LOAD_REQ: begin
                    if (!fifo_empty) begin
                        fifo_rd_en_r <= 1'b1;
                        state <= LOAD_CAP;
                    end
                end

                LOAD_CAP: begin
                    if (fifo_rd_valid) begin
                        frame_flat[(load_idx+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= fifo_rd_data;
                        if (load_idx == PIXEL_COUNT-1) begin
                            state <= READY;
                            frame_valid <= 1'b1;
                            load_idx <= 0;
                            frame_dequeue_flag <= 1'b1;
                        end else begin
                            load_idx <= load_idx + 1'b1;
                            state <= LOAD_REQ;
                        end
                    end
                end

                READY: begin
                    if (frame_consume) begin
                        frame_valid <= 1'b0;
                        state <= (frame_slots != 0) ? LOAD_REQ : COLLECT;
                    end
                end

                default: state <= COLLECT;
            endcase
        end
    end

endmodule
