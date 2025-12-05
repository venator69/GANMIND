`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Guarded includes so synthesizing this top in isolation auto-imports all
// dependent RTL while preventing duplicate definitions when higher-level
// scripts already read them.
// -----------------------------------------------------------------------------
`ifndef GAN_TOP_PIXEL_LOADER_INCLUDED
`define GAN_TOP_PIXEL_LOADER_INCLUDED
`include "../interfaces/pixel_serial_loader.v"
`endif

`ifndef GAN_TOP_FRAME_SAMPLER_INCLUDED
`define GAN_TOP_FRAME_SAMPLER_INCLUDED
`include "../interfaces/frame_sampler.v"
`endif

`ifndef GAN_TOP_VECTOR_EXPANDER_INCLUDED
`define GAN_TOP_VECTOR_EXPANDER_INCLUDED
`include "../interfaces/vector_expander.v"
`endif

`ifndef GAN_TOP_VECTOR_SIGMOID_INCLUDED
`define GAN_TOP_VECTOR_SIGMOID_INCLUDED
`include "../interfaces/vector_sigmoid.v"
`endif

`ifndef GAN_TOP_SIGMOID_APPROX_INCLUDED
`define GAN_TOP_SIGMOID_APPROX_INCLUDED
`include "../interfaces/sigmoid_approx.v"
`endif

`ifndef GAN_TOP_VECTOR_UPSAMPLER_INCLUDED
`define GAN_TOP_VECTOR_UPSAMPLER_INCLUDED
`include "../interfaces/vector_upsampler.v"
`endif

`ifndef GAN_TOP_SEED_LFSR_INCLUDED
`define GAN_TOP_SEED_LFSR_INCLUDED
`include "../generator/seed_lfsr_bank.v"
`endif

`ifndef GAN_TOP_GENERATOR_PIPELINE_INCLUDED
`define GAN_TOP_GENERATOR_PIPELINE_INCLUDED
`include "../generator/generator_pipeline.v"
`endif

`ifndef GAN_TOP_DISCRIMINATOR_PIPELINE_INCLUDED
`define GAN_TOP_DISCRIMINATOR_PIPELINE_INCLUDED
`include "../discriminator/discriminator_pipeline.v"
`endif

// -----------------------------------------------------------------------------
// gan_serial_top
// -----------------------------------------------------------------------------
// Glue logic that connects the existing generator/discriminator RTL to a
// serialized 28x28 pixel stream. All heavy arithmetic remains inside the
// pre-verified layers; this module focuses on control flow and data marshaling.
// -----------------------------------------------------------------------------
module gan_serial_top (
    input  wire clk,
    input  wire rst,
    // Serialized pixel ingress (1 bit per cycle)
    input  wire pixel_bit,
    input  wire pixel_bit_valid,
    output wire pixel_bit_ready,
    // Command interface
    input  wire start,
    output reg  busy,
    output reg  done,
    // Discriminator results
    output reg  disc_fake_is_real,
    output reg  disc_real_is_real,
    output reg  signed [15:0] disc_fake_score,
    output reg  signed [15:0] disc_real_score,
    // Generated frame for visualization
    output reg  [16*784-1:0] generated_frame_flat,
    output reg               generated_frame_valid,
    // Status to host
    output wire frame_ready
);

    // -------------------------------------------------------------------------
    // Serialized pixel loader
    // -------------------------------------------------------------------------
    wire loader_frame_valid;
    reg  frame_consume_pulse;
    wire [16*784-1:0] loader_frame_flat;

    pixel_serial_loader u_loader (
        .clk            (clk),
        .rst            (rst),
        .pixel_bit      (pixel_bit),
        .pixel_bit_valid(pixel_bit_valid),
        .pixel_bit_ready(pixel_bit_ready),
        .frame_consume  (frame_consume_pulse),
        .frame_valid    (loader_frame_valid),
        .frame_flat     (loader_frame_flat)
    );

    assign frame_ready = loader_frame_valid;

    // Buffer the latest frame so it can be reused while the loader keeps
    // capturing the next serialized image.
    reg [16*784-1:0] frame_buffer;

    wire [16*256-1:0] sampled_real_vec;
    reg  frame_sample_start_pulse;
    reg  sampled_real_vec_ready;
    wire frame_sample_done;
    frame_sampler u_frame_sampler (
        .clk         (clk),
        .rst         (rst),
        .start       (frame_sample_start_pulse),
        .frame_flat  (frame_buffer),
        .sampled_flat(sampled_real_vec),
        .busy        (),
        .done        (frame_sample_done)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sampled_real_vec_ready <= 1'b0;
        end else begin
            if (frame_sample_start_pulse)
                sampled_real_vec_ready <= 1'b0;
            if (frame_sample_done)
                sampled_real_vec_ready <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Generator path
    // -------------------------------------------------------------------------
    wire [16*64-1:0] seed_bank_flat;
    reg  seed_start_pulse;
    wire seed_ready;

    seed_lfsr_bank u_seed_bank (
        .clk       (clk),
        .rst       (rst),
        .start     (seed_start_pulse),
        .seed_flat (seed_bank_flat),
        .done      (seed_ready)
    );

    reg        gen_start_pulse;
    reg        gen_seed_wr_en;
    reg [15:0] gen_seed_wr_data;
    wire       gen_seed_full;
    wire [6:0] gen_seed_level;
    reg        gen_feature_rd_en;
    wire [15:0] gen_feature_rd_data;
    wire       gen_feature_rd_valid;
    wire       gen_feature_empty;
    wire [7:0] gen_feature_level;
    wire       gen_busy;
    wire       gen_done;

    generator_pipeline u_generator (
        .clk             (clk),
        .rst             (rst),
        .start           (gen_start_pulse),
        .seed_wr_en      (gen_seed_wr_en),
        .seed_wr_data    (gen_seed_wr_data),
        .seed_full       (gen_seed_full),
        .seed_level      (gen_seed_level),
        .feature_rd_en   (gen_feature_rd_en),
        .feature_rd_data (gen_feature_rd_data),
        .feature_rd_valid(gen_feature_rd_valid),
        .feature_empty   (gen_feature_empty),
        .feature_level   (gen_feature_level),
        .busy            (gen_busy),
        .done            (gen_done)
    );

    reg  [16*128-1:0] gen_features;
    reg               gen_features_ready;
    reg               clear_gen_features_ready;
    reg               gen_feature_collect_active;
    reg  [7:0]        gen_feature_collect_idx;
    reg               seed_stream_active;
    reg               seed_stream_done;
    reg  [6:0]        seed_stream_idx;

    wire [16*128-1:0] gen_sigmoid_features;
    reg  gen_sigmoid_start_pulse;
    reg  gen_sigmoid_ready;
    reg  sigmoid_run_active;
    wire gen_sigmoid_busy;
    wire gen_sigmoid_done;
    vector_sigmoid u_vector_sigmoid (
        .clk      (clk),
        .rst      (rst),
        .start    (gen_sigmoid_start_pulse),
        .data_in  (gen_features),
        .data_out (gen_sigmoid_features),
        .busy     (gen_sigmoid_busy),
        .done     (gen_sigmoid_done)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gen_sigmoid_start_pulse <= 1'b0;
            gen_sigmoid_ready       <= 1'b0;
            sigmoid_run_active      <= 1'b0;
        end else begin
            gen_sigmoid_start_pulse <= 1'b0;

            if (gen_features_ready && !sigmoid_run_active) begin
                if (!gen_sigmoid_busy) begin
                    gen_sigmoid_start_pulse <= 1'b1;
                    sigmoid_run_active      <= 1'b1;
                end
            end

            if (gen_sigmoid_done)
                gen_sigmoid_ready <= 1'b1;

            if (clear_gen_features_ready) begin
                gen_sigmoid_ready  <= 1'b0;
                sigmoid_run_active <= 1'b0;
            end
        end
    end

    wire [16*256-1:0] fake_disc_vec;
    reg  expander_start_pulse;
    wire expander_busy;
    wire expander_done;
    vector_expander u_vector_expander (
        .clk       (clk),
        .rst       (rst),
        .start     (expander_start_pulse),
        .vector_in (gen_sigmoid_features),
        .vector_out(fake_disc_vec),
        .busy      (expander_busy),
        .done      (expander_done)
    );

    wire [16*784-1:0] gen_frame_pixels;
    reg  upsampler_start_pulse;
    wire upsampler_busy;
    wire upsampler_done;
    vector_upsampler u_vector_upsampler (
        .clk       (clk),
        .rst       (rst),
        .start     (upsampler_start_pulse),
        .vector_in (gen_sigmoid_features),
        .vector_out(gen_frame_pixels),
        .busy      (upsampler_busy),
        .done      (upsampler_done)
    );

    reg expander_job_launched;
    reg upsampler_job_launched;

    // -------------------------------------------------------------------------
    // FIFO helper logic (generator path)
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gen_seed_wr_en     <= 1'b0;
            gen_seed_wr_data   <= 16'd0;
            seed_stream_active <= 1'b0;
            seed_stream_done   <= 1'b0;
            seed_stream_idx    <= 0;
        end else begin
            gen_seed_wr_en <= 1'b0;

            if (seed_ready) begin
                seed_stream_active <= 1'b1;
                seed_stream_done   <= 1'b0;
                seed_stream_idx    <= 0;
            end else if (seed_stream_active) begin
                if (!gen_seed_full) begin
                    gen_seed_wr_en   <= 1'b1;
                    gen_seed_wr_data <= seed_bank_flat[(seed_stream_idx+1)*16-1 -: 16];
                    if (seed_stream_idx == 6'd63) begin
                        seed_stream_active <= 1'b0;
                        seed_stream_done   <= 1'b1;
                    end else begin
                        seed_stream_idx <= seed_stream_idx + 1'b1;
                    end
                end
            end else if (gen_start_pulse) begin
                seed_stream_done <= 1'b0;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            gen_feature_rd_en           <= 1'b0;
            gen_feature_collect_active  <= 1'b0;
            gen_feature_collect_idx     <= 0;
            gen_features                <= {16*128{1'b0}};
            gen_features_ready          <= 1'b0;
        end else begin
            gen_feature_rd_en <= 1'b0;

            if (gen_done) begin
                gen_feature_collect_active <= 1'b1;
                gen_feature_collect_idx   <= 0;
                gen_features_ready        <= 1'b0;
            end

            if (gen_feature_collect_active && !gen_feature_empty) begin
                gen_feature_rd_en <= 1'b1;
            end

            if (gen_feature_rd_valid) begin
                gen_features[(gen_feature_collect_idx+1)*16-1 -: 16] <= gen_feature_rd_data;
                if (gen_feature_collect_idx == 8'd127) begin
                    gen_feature_collect_active <= 1'b0;
                    gen_features_ready        <= 1'b1;
                end else begin
                    gen_feature_collect_idx <= gen_feature_collect_idx + 1'b1;
                end
            end

            if (clear_gen_features_ready)
                gen_features_ready <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Discriminator path (shared instance for fake/real checks)
    // -------------------------------------------------------------------------
    reg  disc_start_pulse;
    reg  disc_sample_wr_en;
    reg  [15:0] disc_sample_wr_data;
    wire disc_sample_full;
    wire [8:0] disc_sample_level;
    reg  disc_score_rd_en;
    wire [15:0] disc_score_rd_data;
    wire disc_score_rd_valid;
    wire disc_score_empty;
    wire [2:0] disc_score_level;
    wire disc_real_flag;
    wire disc_busy;
    wire disc_done;

    reg disc_stream_start_fake;
    reg disc_stream_start_real;
    reg disc_stream_active;
    reg disc_stream_mode_real;
    reg [8:0] disc_stream_idx;
    reg disc_stream_done;
    reg disc_run_is_real;
    reg disc_score_fetch_active;
    reg disc_result_is_real;
    reg pending_disc_flag;

    discriminator_pipeline u_discriminator (
        .clk           (clk),
        .rst           (rst),
        .start         (disc_start_pulse),
        .sample_wr_en  (disc_sample_wr_en),
        .sample_wr_data(disc_sample_wr_data),
        .sample_full   (disc_sample_full),
        .sample_level  (disc_sample_level),
        .score_rd_en   (disc_score_rd_en),
        .score_rd_data (disc_score_rd_data),
        .score_rd_valid(disc_score_rd_valid),
        .score_empty   (disc_score_empty),
        .score_level   (disc_score_level),
        .disc_real_flag(disc_real_flag),
        .busy          (disc_busy),
        .done          (disc_done)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            disc_sample_wr_en   <= 1'b0;
            disc_sample_wr_data <= 16'd0;
            disc_stream_active  <= 1'b0;
            disc_stream_mode_real <= 1'b0;
            disc_stream_idx     <= 0;
            disc_stream_done    <= 1'b0;
        end else begin
            disc_sample_wr_en <= 1'b0;

            if (disc_stream_start_fake) begin
                disc_stream_active    <= 1'b1;
                disc_stream_mode_real <= 1'b0;
                disc_stream_idx       <= 0;
                disc_stream_done      <= 1'b0;
            end else if (disc_stream_start_real) begin
                disc_stream_active    <= 1'b1;
                disc_stream_mode_real <= 1'b1;
                disc_stream_idx       <= 0;
                disc_stream_done      <= 1'b0;
            end else if (disc_stream_active) begin
                if (!disc_sample_full) begin
                    disc_sample_wr_en   <= 1'b1;
                    disc_sample_wr_data <= disc_stream_mode_real
                        ? sampled_real_vec[(disc_stream_idx+1)*16-1 -: 16]
                        : fake_disc_vec[(disc_stream_idx+1)*16-1 -: 16];
                    if (disc_stream_idx == 9'd255) begin
                        disc_stream_active <= 1'b0;
                        disc_stream_done   <= 1'b1;
                    end else begin
                        disc_stream_idx <= disc_stream_idx + 1'b1;
                    end
                end
            end else if (disc_stream_done && disc_start_pulse) begin
                disc_stream_done <= 1'b0;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            disc_score_rd_en        <= 1'b0;
            disc_score_fetch_active <= 1'b0;
            disc_result_is_real     <= 1'b0;
            pending_disc_flag       <= 1'b0;
        end else begin
            disc_score_rd_en <= 1'b0;

            if (disc_done) begin
                pending_disc_flag       <= disc_real_flag;
                disc_result_is_real     <= disc_run_is_real;
                disc_score_fetch_active <= 1'b1;
            end

            if (disc_score_fetch_active && !disc_score_empty) begin
                disc_score_rd_en <= 1'b1;
            end

            if (disc_score_rd_valid) begin
                if (disc_result_is_real) begin
                    disc_real_score   <= disc_score_rd_data;
                    disc_real_is_real <= pending_disc_flag;
                end else begin
                    disc_fake_score   <= disc_score_rd_data;
                    disc_fake_is_real <= pending_disc_flag;
                end
                disc_score_fetch_active <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Control FSM
    // -------------------------------------------------------------------------
    localparam S_IDLE       = 3'd0;
    localparam S_SEED       = 3'd1;
    localparam S_GEN        = 3'd2;
    localparam S_FAKE_LOAD  = 3'd3;
    localparam S_DISC_FAKE  = 3'd4;
    localparam S_REAL_LOAD  = 3'd5;
    localparam S_DISC_REAL  = 3'd6;
    localparam S_DONE       = 3'd7;

    reg [2:0] state;
    reg       real_stream_start_sent;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state                  <= S_IDLE;
            frame_buffer           <= {16*784{1'b0}};
            frame_consume_pulse    <= 1'b0;
            seed_start_pulse       <= 1'b0;
            gen_start_pulse        <= 1'b0;
            disc_start_pulse       <= 1'b0;
            disc_run_is_real       <= 1'b0;
            disc_fake_score        <= 16'sd0;
            disc_real_score        <= 16'sd0;
            disc_fake_is_real      <= 1'b0;
            disc_real_is_real      <= 1'b0;
            generated_frame_flat   <= {16*784{1'b0}};
            generated_frame_valid  <= 1'b0;
            busy                   <= 1'b0;
            done                   <= 1'b0;
            clear_gen_features_ready <= 1'b0;
            disc_stream_start_fake   <= 1'b0;
            disc_stream_start_real   <= 1'b0;
            frame_sample_start_pulse  <= 1'b0;
            real_stream_start_sent    <= 1'b0;
            upsampler_start_pulse     <= 1'b0;
            expander_start_pulse      <= 1'b0;
            expander_job_launched     <= 1'b0;
            upsampler_job_launched    <= 1'b0;
        end else begin
            // Default deassertions
            frame_consume_pulse      <= 1'b0;
            seed_start_pulse         <= 1'b0;
            gen_start_pulse          <= 1'b0;
            disc_start_pulse         <= 1'b0;
            clear_gen_features_ready <= 1'b0;
            disc_stream_start_fake   <= 1'b0;
            disc_stream_start_real   <= 1'b0;
            frame_sample_start_pulse  <= 1'b0;
            done                     <= 1'b0;
            upsampler_start_pulse    <= 1'b0;
            expander_start_pulse     <= 1'b0;

            if (upsampler_done) begin
                generated_frame_flat  <= gen_frame_pixels;
                generated_frame_valid <= 1'b1;
            end

            if (clear_gen_features_ready) begin
                expander_job_launched  <= 1'b0;
                upsampler_job_launched <= 1'b0;
            end

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start && loader_frame_valid) begin
                        busy                <= 1'b1;
                        frame_buffer        <= loader_frame_flat;
                        frame_consume_pulse <= 1'b1; // free loader for next frame
                        generated_frame_valid <= 1'b0;
                        seed_start_pulse    <= 1'b1;
                        frame_sample_start_pulse <= 1'b1;
                        real_stream_start_sent   <= 1'b0;
                        state               <= S_SEED;
                    end
                end

                S_SEED: begin
                    busy <= 1'b1;
                    if (seed_stream_done && (gen_seed_level >= 7'd64) && gen_feature_empty) begin
                        gen_start_pulse <= 1'b1;
                        state           <= S_GEN;
                    end
                end

                S_GEN: begin
                    busy <= 1'b1;
                    if (gen_sigmoid_ready) begin
                        if (!expander_job_launched && !expander_busy) begin
                            expander_start_pulse  <= 1'b1;
                            expander_job_launched <= 1'b1;
                        end
                        if (!upsampler_job_launched && !upsampler_busy) begin
                            upsampler_start_pulse   <= 1'b1;
                            upsampler_job_launched  <= 1'b1;
                        end
                        if (expander_done && upsampler_done) begin
                            disc_stream_start_fake   <= 1'b1;
                            clear_gen_features_ready <= 1'b1;
                            state                    <= S_FAKE_LOAD;
                        end
                    end
                end

                S_FAKE_LOAD: begin
                    busy <= 1'b1;
                    if (disc_stream_done && (disc_sample_level >= 9'd256)) begin
                        disc_start_pulse <= 1'b1;
                        disc_run_is_real <= 1'b0;
                        state            <= S_DISC_FAKE;
                    end
                end

                S_DISC_FAKE: begin
                    busy <= 1'b1;
                    if (disc_done) begin
                        real_stream_start_sent <= 1'b0;
                        state                  <= S_REAL_LOAD;
                    end
                end

                S_REAL_LOAD: begin
                    busy <= 1'b1;
                    if (!real_stream_start_sent && sampled_real_vec_ready) begin
                        disc_stream_start_real <= 1'b1;
                        real_stream_start_sent <= 1'b1;
                    end
                    if (real_stream_start_sent && disc_stream_done && (disc_sample_level >= 9'd256)) begin
                        disc_start_pulse <= 1'b1;
                        disc_run_is_real <= 1'b1;
                        state            <= S_DISC_REAL;
                    end
                end

                S_DISC_REAL: begin
                    busy <= 1'b1;
                    if (disc_done) begin
                        state             <= S_DONE;
                    end
                end

                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (!start)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
