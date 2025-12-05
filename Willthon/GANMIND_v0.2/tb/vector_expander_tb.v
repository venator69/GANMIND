`timescale 1ns / 1ps

module vector_expander_tb;
    localparam integer DATA_WIDTH   = 16;
    localparam integer INPUT_COUNT  = 8;
    localparam integer OUTPUT_COUNT = 16;

    reg clk;
    reg rst;
    reg start;
    reg [DATA_WIDTH*INPUT_COUNT-1:0] stimulus_vector;
    wire [DATA_WIDTH*OUTPUT_COUNT-1:0] expanded_vector;
    wire busy;
    wire done;

    integer error_count;

    vector_expander #(
        .INPUT_COUNT  (INPUT_COUNT),
        .OUTPUT_COUNT (OUTPUT_COUNT),
        .DATA_WIDTH   (DATA_WIDTH)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .vector_in (stimulus_vector),
        .vector_out(expanded_vector),
        .busy      (busy),
        .done      (done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("vcd/vector_expander_tb.vcd");
        $dumpvars(0, vector_expander_tb);
    end

    function automatic integer src_index(input integer out_idx);
        integer calc;
        begin
            calc = (out_idx * INPUT_COUNT) / OUTPUT_COUNT;
            if (calc >= INPUT_COUNT)
                calc = INPUT_COUNT - 1;
            src_index = calc;
        end
    endfunction

    task automatic load_pattern(input integer seed_offset);
        integer idx;
        begin
            for (idx = 0; idx < INPUT_COUNT; idx = idx + 1) begin
                stimulus_vector[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH] =
                    $signed((idx + seed_offset) * 16);
            end
        end
    endtask

    task automatic run_case(input integer offset);
        integer idx;
        reg signed [DATA_WIDTH-1:0] expected;
        reg signed [DATA_WIDTH-1:0] actual;
        begin
            load_pattern(offset);
            @(posedge clk); // allow stimulus_vector to settle before capture

            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            wait (done);

            for (idx = 0; idx < OUTPUT_COUNT; idx = idx + 1) begin
                expected = stimulus_vector[(src_index(idx)+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                actual   = expanded_vector[(idx+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                if (actual !== expected) begin
                    error_count = error_count + 1;
                    $display("Mismatch idx%0d: exp=%0d got=%0d", idx, expected, actual);
                end
            end
        end
    endtask

    initial begin
        error_count = 0;
        start       = 0;
        stimulus_vector = {DATA_WIDTH*INPUT_COUNT{1'b0}};

        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;

        run_case(0);
        run_case(3);

        if (error_count == 0)
            $display("\n=== vector_expander_tb PASSED ===");
        else begin
            $display("\n*** vector_expander_tb FAILED (%0d mismatches) ***", error_count);
            $fatal;
        end

        #50;
        $finish;
    end

endmodule
