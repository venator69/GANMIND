`timescale 1ns / 1ps

module frame_sampler_tb;
    localparam integer INPUT_COUNT  = 16;
    localparam integer OUTPUT_COUNT = 5;
    localparam integer DATA_WIDTH   = 16;

    reg clk;
    reg rst;
    reg start;
    reg [DATA_WIDTH*INPUT_COUNT-1:0] frame_flat;
    wire [DATA_WIDTH*OUTPUT_COUNT-1:0] sampled_flat;
    wire busy;
    wire done;

    frame_sampler #(
        .INPUT_COUNT  (INPUT_COUNT),
        .OUTPUT_COUNT (OUTPUT_COUNT),
        .DATA_WIDTH   (DATA_WIDTH)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .frame_flat  (frame_flat),
        .sampled_flat(sampled_flat),
        .busy        (busy),
        .done        (done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic set_frame_word(input integer index, input [DATA_WIDTH-1:0] value);
        begin
            frame_flat[(index+1)*DATA_WIDTH-1 -: DATA_WIDTH] = value;
        end
    endtask

    function automatic [DATA_WIDTH-1:0] get_sampled_word(input integer index);
        get_sampled_word = sampled_flat[(index+1)*DATA_WIDTH-1 -: DATA_WIDTH];
    endfunction

    integer idx;
    reg [DATA_WIDTH-1:0] expected [0:OUTPUT_COUNT-1];
    integer errors;

    initial begin
        $dumpfile("vcd/frame_sampler_tb.vcd");
        $dumpvars(0, frame_sampler_tb);
    end

    initial begin
        rst        = 1'b1;
        start      = 1'b0;
        frame_flat = {DATA_WIDTH*INPUT_COUNT{1'b0}};
        errors     = 0;

        for (idx = 0; idx < INPUT_COUNT; idx = idx + 1) begin
            set_frame_word(idx, idx);
        end

        repeat (2) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
            expected[idx] = (idx * INPUT_COUNT) / OUTPUT_COUNT;
        end

        $display("[TB] Starting frame_sampler test");
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait (done);
        @(posedge clk);

        for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
            if (get_sampled_word(idx) !== expected[idx]) begin
                $display("[TB] Mismatch at %0d: expected %0d, got %0d", idx, expected[idx], get_sampled_word(idx));
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("[TB] PASS: frame_sampler output matches reference");
        else begin
            $display("[TB] FAIL: %0d mismatches detected", errors);
            $fatal;
        end

        #20;
        $finish;
    end

endmodule
