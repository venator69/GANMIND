`timescale 1ns / 1ps

module interfaces_integration_tb;
    localparam integer DATA_WIDTH       = 16;
    localparam integer PIXEL_COUNT      = 32;
    localparam integer SAMPLE_COUNT     = 8;
    localparam integer FEATURE_COUNT    = 8;
    localparam integer EXPANDED_COUNT   = 16;
    localparam integer UPSAMPLED_COUNT  = 32;
    localparam integer PIXEL_SCALE_BITS = 8;

    reg clk;
    reg rst;

    // Pixel serial loader signals
    reg pixel_bit;
    reg pixel_valid;
    wire pixel_ready;
    reg frame_consume;
    wire frame_valid;
    wire [DATA_WIDTH*PIXEL_COUNT-1:0] frame_flat;

    // Frame sampler signals
    reg sampler_start;
    wire sampler_busy;
    wire sampler_done;
    wire [DATA_WIDTH*SAMPLE_COUNT-1:0] sampled_flat;

    // Vector sigmoid signals
    reg vs_start;
    wire vs_busy;
    wire vs_done;
    reg  [DATA_WIDTH*FEATURE_COUNT-1:0] vs_data_in;
    wire [DATA_WIDTH*FEATURE_COUNT-1:0] vs_data_out;

    // Vector mapper / upsampler signals
    reg  exp_start;
    wire exp_busy;
    wire exp_done;
    wire [DATA_WIDTH*EXPANDED_COUNT-1:0] expanded_vec;
    reg  ups_start;
    wire ups_busy;
    wire ups_done;
    wire [DATA_WIDTH*UPSAMPLED_COUNT-1:0] upsampled_vec;

    integer error_count;

    // Clock generation (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("vcd/interfaces_integration_tb.vcd");
        $dumpvars(0, interfaces_integration_tb);
    end

    pixel_serial_loader #(
        .PIXEL_COUNT  (PIXEL_COUNT),
        .DATA_WIDTH   (DATA_WIDTH),
        .PIXEL_SCALE  (PIXEL_SCALE_BITS),
        .FIFO_DEPTH   (64),
        .FIFO_ADDR_W  (6),
        .FRAME_SLOT_W (2)
    ) u_loader (
        .clk           (clk),
        .rst           (rst),
        .pixel_bit     (pixel_bit),
        .pixel_bit_valid(pixel_valid),
        .pixel_bit_ready(pixel_ready),
        .frame_consume (frame_consume),
        .frame_valid   (frame_valid),
        .frame_flat    (frame_flat)
    );

    frame_sampler #(
        .INPUT_COUNT  (PIXEL_COUNT),
        .OUTPUT_COUNT (SAMPLE_COUNT),
        .DATA_WIDTH   (DATA_WIDTH)
    ) u_sampler (
        .clk         (clk),
        .rst         (rst),
        .start       (sampler_start),
        .frame_flat  (frame_flat),
        .sampled_flat(sampled_flat),
        .busy        (sampler_busy),
        .done        (sampler_done)
    );

    vector_sigmoid #(
        .ELEMENT_COUNT (FEATURE_COUNT),
        .DATA_WIDTH    (DATA_WIDTH),
        .Q_FRAC        (PIXEL_SCALE_BITS)
    ) u_vector_sigmoid (
        .clk     (clk),
        .rst     (rst),
        .start   (vs_start),
        .data_in (vs_data_in),
        .data_out(vs_data_out),
        .busy    (vs_busy),
        .done    (vs_done)
    );

    vector_expander #(
        .INPUT_COUNT  (FEATURE_COUNT),
        .OUTPUT_COUNT (EXPANDED_COUNT),
        .DATA_WIDTH   (DATA_WIDTH)
    ) u_vector_expander (
        .clk       (clk),
        .rst       (rst),
        .start     (exp_start),
        .vector_in (vs_data_out),
        .vector_out(expanded_vec),
        .busy      (exp_busy),
        .done      (exp_done)
    );

    vector_upsampler #(
        .INPUT_COUNT  (FEATURE_COUNT),
        .OUTPUT_COUNT (UPSAMPLED_COUNT),
        .DATA_WIDTH   (DATA_WIDTH)
    ) u_vector_upsampler (
        .clk       (clk),
        .rst       (rst),
        .start     (ups_start),
        .vector_in (vs_data_out),
        .vector_out(upsampled_vec),
        .busy      (ups_busy),
        .done      (ups_done)
    );

    // ------------------------------------------------------------------
    // Utility functions
    // ------------------------------------------------------------------
    function automatic bit pixel_pattern_bit(input integer idx);
        pixel_pattern_bit = ((idx % 5) == 0);
    endfunction

    function automatic [DATA_WIDTH-1:0] pixel_word(input integer idx);
        if (pixel_pattern_bit(idx))
            pixel_word = {{(DATA_WIDTH-PIXEL_SCALE_BITS-1){1'b0}}, 1'b1, {PIXEL_SCALE_BITS{1'b0}}};
        else
            pixel_word = {DATA_WIDTH{1'b0}};
    endfunction

    function automatic integer sampler_src_index(input integer out_idx);
        integer calc;
        begin
            calc = (out_idx * PIXEL_COUNT) / SAMPLE_COUNT;
            if (calc >= PIXEL_COUNT)
                calc = PIXEL_COUNT - 1;
            sampler_src_index = calc;
        end
    endfunction

    function automatic integer expander_src_index(input integer out_idx);
        integer calc;
        begin
            calc = (out_idx * FEATURE_COUNT) / EXPANDED_COUNT;
            if (calc >= FEATURE_COUNT)
                calc = FEATURE_COUNT - 1;
            expander_src_index = calc;
        end
    endfunction

    function automatic integer upsampler_src_index(input integer out_idx);
        integer calc;
        begin
            calc = (out_idx * FEATURE_COUNT) / UPSAMPLED_COUNT;
            if (calc >= FEATURE_COUNT)
                calc = FEATURE_COUNT - 1;
            upsampler_src_index = calc;
        end
    endfunction

    function automatic signed [DATA_WIDTH-1:0] sigmoid_model(input signed [DATA_WIDTH-1:0] val);
        localparam signed [DATA_WIDTH-1:0] ONE_Q  = (1 << PIXEL_SCALE_BITS);
        localparam signed [DATA_WIDTH-1:0] HALF_Q = (1 << (PIXEL_SCALE_BITS-1));
        localparam signed [DATA_WIDTH-1:0] SAT    = 1024;
        reg signed [DATA_WIDTH+1:0] scaled;
        reg signed [DATA_WIDTH+1:0] approx;
        begin
            if (val >= SAT)
                sigmoid_model = ONE_Q;
            else if (val <= -SAT)
                sigmoid_model = {DATA_WIDTH{1'b0}};
            else begin
                scaled = val >>> 2;
                approx = HALF_Q + scaled;
                if (approx < 0)
                    sigmoid_model = {DATA_WIDTH{1'b0}};
                else if (approx > ONE_Q)
                    sigmoid_model = ONE_Q;
                else
                    sigmoid_model = approx[DATA_WIDTH-1:0];
            end
        end
    endfunction

    // ------------------------------------------------------------------
    // Stimulus helpers
    // ------------------------------------------------------------------
    task automatic stream_serial_frame;
        integer idx;
        begin
            idx = 0;
            while (idx < PIXEL_COUNT) begin
                pixel_bit   <= pixel_pattern_bit(idx);
                pixel_valid <= 1'b1;
                @(posedge clk);
                if (pixel_ready)
                    idx = idx + 1;
            end
            pixel_valid <= 1'b0;
            pixel_bit   <= 1'b0;
        end
    endtask

    task automatic check_loader_and_sampler;
        integer idx;
        reg [DATA_WIDTH-1:0] expected;
        reg [DATA_WIDTH-1:0] actual;
        begin
            $display("[CHECK] Pixel loader + frame sampler");
            frame_consume  <= 1'b0;
            sampler_start  <= 1'b0;

            stream_serial_frame();

            wait (frame_valid);
            @(posedge clk);

            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                expected = pixel_word(idx);
                actual   = frame_flat[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                if (actual !== expected) begin
                    error_count = error_count + 1;
                    $display("Mismatch loader[%0d]: exp=%0h got=%0h", idx, expected, actual);
                end
            end

            sampler_start <= 1'b1;
            @(posedge clk);
            sampler_start <= 1'b0;
            wait (sampler_done);

            for (idx = 0; idx < SAMPLE_COUNT; idx = idx + 1) begin
                expected = pixel_word(sampler_src_index(idx));
                actual   = sampled_flat[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                if (actual !== expected) begin
                    error_count = error_count + 1;
                    $display("Mismatch sampler[%0d]: exp=%0h got=%0h", idx, expected, actual);
                end
            end

            frame_consume <= 1'b1;
            @(posedge clk);
            frame_consume <= 1'b0;
        end
    endtask

    task automatic check_vector_sigmoid_and_mappers;
        integer idx;
        reg signed [DATA_WIDTH-1:0] expected;
        reg signed [DATA_WIDTH-1:0] actual;
        begin
            $display("[CHECK] Vector sigmoid + expanders");

            for (idx = 0; idx < FEATURE_COUNT; idx = idx + 1) begin
                vs_data_in[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH] = $signed((idx - 4) * 256);
            end
            @(posedge clk);

            vs_start <= 1'b1;
            @(posedge clk);
            vs_start <= 1'b0;

            wait (vs_done);

            exp_start <= 1'b1;
            @(posedge clk);
            exp_start <= 1'b0;
            wait (exp_done);

            for (idx = 0; idx < FEATURE_COUNT; idx = idx + 1) begin
                expected = sigmoid_model($signed((idx - 4) * 256));
                actual   = vs_data_out[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                if (actual !== expected) begin
                    error_count = error_count + 1;
                    $display("Mismatch sigmoid[%0d]: exp=%0d got=%0d", idx, expected, actual);
                end
            end

            for (idx = 0; idx < EXPANDED_COUNT; idx = idx + 1) begin
                expected = sigmoid_model($signed((expander_src_index(idx) - 4) * 256));
                actual   = expanded_vec[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                if (actual !== expected) begin
                    error_count = error_count + 1;
                    $display("Mismatch expander[%0d]: exp=%0d got=%0d", idx, expected, actual);
                end
            end

            ups_start <= 1'b1;
            @(posedge clk);
            ups_start <= 1'b0;
            wait (ups_done);

            for (idx = 0; idx < UPSAMPLED_COUNT; idx = idx + 1) begin
                expected = sigmoid_model($signed((upsampler_src_index(idx) - 4) * 256));
                actual   = upsampled_vec[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                if (actual !== expected) begin
                    error_count = error_count + 1;
                    $display("Mismatch upsampler[%0d]: exp=%0d got=%0d", idx, expected, actual);
                end
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    initial begin
        error_count   = 0;
        pixel_bit     = 0;
        pixel_valid   = 0;
        frame_consume = 0;
        sampler_start = 0;
        vs_start      = 0;
        exp_start     = 0;
        ups_start     = 0;

        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;

        check_loader_and_sampler();
        check_vector_sigmoid_and_mappers();

        if (error_count == 0) begin
            $display("\n=== Interface integration test PASSED ===");
        end else begin
            $display("\n*** Interface integration test FAILED (%0d mismatches) ***", error_count);
            $fatal;
        end

        #50;
        $finish;
    end

endmodule
