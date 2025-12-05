`timescale 1ns / 1ps

module vector_sigmoid_tb;
    localparam integer ELEMENT_COUNT = 8;
    localparam integer DATA_WIDTH    = 16;
    localparam integer Q_FRAC        = 8;
    localparam integer SAT_LIMIT     = 1024;

    reg clk;
    reg rst;
    reg start;
    reg [DATA_WIDTH*ELEMENT_COUNT-1:0] data_in;
    wire [DATA_WIDTH*ELEMENT_COUNT-1:0] data_out;
    wire busy;
    wire done;

    vector_sigmoid #(
        .ELEMENT_COUNT (ELEMENT_COUNT),
        .DATA_WIDTH    (DATA_WIDTH),
        .Q_FRAC        (Q_FRAC)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .start   (start),
        .data_in (data_in),
        .data_out(data_out),
        .busy    (busy),
        .done    (done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic set_word(input integer index, input signed [DATA_WIDTH-1:0] value);
        begin
            data_in[index*DATA_WIDTH +: DATA_WIDTH] = value;
        end
    endtask

    function automatic signed [DATA_WIDTH-1:0] get_word(input integer index);
        get_word = data_out[index*DATA_WIDTH +: DATA_WIDTH];
    endfunction

    localparam signed [DATA_WIDTH-1:0] ONE_Q  = (1 << Q_FRAC);
    localparam signed [DATA_WIDTH-1:0] HALF_Q = (1 << (Q_FRAC-1));

    function automatic signed [DATA_WIDTH-1:0] sigmoid_ref;
        input signed [DATA_WIDTH-1:0] val;
        reg signed [DATA_WIDTH+1:0] scaled;
        reg signed [DATA_WIDTH+1:0] approx;
        begin
            if (val >= SAT_LIMIT)
                sigmoid_ref = ONE_Q;
            else if (val <= -SAT_LIMIT)
                sigmoid_ref = {DATA_WIDTH{1'b0}};
            else begin
                scaled = val >>> 2;
                approx = HALF_Q + scaled;
                if (approx < 0)
                    sigmoid_ref = {DATA_WIDTH{1'b0}};
                else if (approx > ONE_Q)
                    sigmoid_ref = ONE_Q;
                else
                    sigmoid_ref = approx[DATA_WIDTH-1:0];
            end
        end
    endfunction

    integer idx;
    reg signed [DATA_WIDTH-1:0] expected [0:ELEMENT_COUNT-1];
    integer errors;

    initial begin
        $dumpfile("vcd/vector_sigmoid_tb.vcd");
        $dumpvars(0, vector_sigmoid_tb);

        clk   = 1'b0;
        rst   = 1'b1;
        start = 1'b0;
        data_in = {DATA_WIDTH*ELEMENT_COUNT{1'b0}};
        errors  = 0;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        for (idx = 0; idx < ELEMENT_COUNT; idx = idx + 1) begin
            set_word(idx, (idx * 64) - 256);
            expected[idx] = sigmoid_ref((idx * 64) - 256);
        end

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait (done);
        @(posedge clk);

        for (idx = 0; idx < ELEMENT_COUNT; idx = idx + 1) begin
            if (get_word(idx) !== expected[idx]) begin
                $display("[TB] Mismatch idx %0d: expected %0d, got %0d", idx, expected[idx], get_word(idx));
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("[TB] PASS: vector_sigmoid outputs match reference");
        else begin
            $display("[TB] FAIL: %0d mismatches detected", errors);
            $fatal;
        end

        #20;
        $finish;
    end
endmodule
