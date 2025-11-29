`timescale 1ns / 1ps

/**
 * GAN Hardware - Verilog Function Library
 * Q8.8 Fixed-Point & Activation Functions
 */

module gan_functions;

    // Q8.8 to Real conversion
    function real q88_to_real;
        input signed [15:0] val;
        begin
            q88_to_real = val / 256.0;
        end
    endfunction

    // Real to Q8.8 conversion
    function signed [15:0] real_to_q88;
        input real val;
        integer ival;
        begin
            ival = $rtoi(val * 256.0);
            if (ival > 32767) ival = 32767;
            if (ival < -32768) ival = -32768;
            real_to_q88 = ival;
        end
    endfunction

    // ReLU activation
    function signed [31:0] relu_q1616;
        input signed [31:0] x;
        begin
            relu_q1616 = (x[31]) ? 32'sd0 : x;
        end
    endfunction

    // Leaky ReLU: x if x>0, else 0.2*x
    function signed [31:0] leaky_relu_q1616;
        input signed [31:0] x;
        begin
            leaky_relu_q1616 = (x[31]) ? ((x * 51) >>> 8) : x;
        end
    endfunction

    // Sigmoid: 1 / (1 + exp(-x))
    function real sigmoid;
        input real x;
        real exp_neg_x;
        begin
            exp_neg_x = 2.718281828 ** (-x);
            sigmoid = 1.0 / (1.0 + exp_neg_x);
        end
    endfunction

    // MAC operation: acc + (a * b)
    function signed [31:0] mac_step;
        input signed [31:0] acc;
        input signed [15:0] a;
        input signed [15:0] b;
        begin
            mac_step = acc + (a * b);
        end
    endfunction

    // Load bias (shift to Q16.16)
    function signed [31:0] load_bias;
        input signed [15:0] bias;
        begin
            load_bias = bias <<< 8;
        end
    endfunction

    // Extract Q8.8 from Q16.16
    function signed [15:0] extract_q88;
        input signed [31:0] acc;
        begin
            extract_q88 = acc[23:8];
        end
    endfunction

    // Mean Absolute Error
    function real calc_mae;
        input real expected;
        input real actual;
        begin
            calc_mae = (expected > actual) ? (expected - actual) : (actual - expected);
        end
    endfunction

    // Binary Cross-Entropy Loss
    function real calc_bce;
        input real y;
        input real p;
        real epsilon;
        real ln2;
        begin
            epsilon = 1e-7;
            ln2 = 0.693147181;
            if (p < epsilon) p = epsilon;
            if (p > 1.0 - epsilon) p = 1.0 - epsilon;
            calc_bce = -(y * $ln(p) / ln2 + (1.0 - y) * $ln(1.0 - p) / ln2);
        end
    endfunction

endmodule
```