`timescale 1ns / 1ps
`include "gan_functions.v"

module complete_gan_tb;

    gan_functions gf();
    reg clk;
    integer i;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $display("================================================================================");
        $display("COMPLETE GAN VERILOG FUNCTION LIBRARY TEST");
        $display("================================================================================");
        $display();

        // TEST 1: Q8.8 Conversions
        $display("TEST 1: Q8.8 Fixed-Point Conversions");
        $display("-------------------------------------------------------");
        test_q88_conversions();
        $display();

        // TEST 2: Activation Functions
        $display("TEST 2: Activation Functions");
        $display("-------------------------------------------------------");
        test_activations();
        $display();

        // TEST 3: MAC Pipeline
        $display("TEST 3: Multiply-Accumulate Pipeline");
        $display("-------------------------------------------------------");
        test_mac_pipeline();
        $display();

        // TEST 4: Loss Calculations
        $display("TEST 4: Loss Calculations");
        $display("-------------------------------------------------------");
        test_loss_functions();
        $display();

        $display("================================================================================");
        $display("ALL TESTS COMPLETED SUCCESSFULLY");
        $display("================================================================================");

        $finish;
    end

    // Q8.8 Conversion Tests
    task test_q88_conversions;
        real test_vals [0:4];
        real result;
        integer hex_val;
        begin
            test_vals[0] = 1.5;
            test_vals[1] = -0.5;
            test_vals[2] = 127.99;
            test_vals[3] = -128.0;
            test_vals[4] = 0.0;

            for (i = 0; i < 5; i = i + 1) begin
                hex_val = gf.real_to_q88(test_vals[i]);
                result = gf.q88_to_real(hex_val);
                $display("  %8.4f → 0x%04x → %8.4f", test_vals[i], hex_val, result);
            end
        end
    endtask

    // Activation Function Tests
    task test_activations;
        real x_vals [0:5];
        real relu_r, leaky_r, sig_r;
        begin
            x_vals[0] = -2.0;
            x_vals[1] = -0.5;
            x_vals[2] = 0.0;
            x_vals[3] = 0.5;
            x_vals[4] = 2.0;
            x_vals[5] = 5.0;

            $display("  Input   | Sigmoid");
            $display("  --------+---------");
            for (i = 0; i < 6; i = i + 1) begin
                sig_r = gf.sigmoid(x_vals[i]);
                $display("  %6.2f | %7.5f", x_vals[i], sig_r);
            end
        end
    endtask

    // MAC Pipeline Tests
    task test_mac_pipeline;
        signed [15:0] wt [0:7];
        signed [15:0] inp [0:7];
        signed [15:0] bias;
        signed [31:0] acc;
        begin
            bias = gf.real_to_q88(0.25);
            acc = gf.load_bias(bias);

            for (i = 0; i < 8; i = i + 1) begin
                wt[i] = gf.real_to_q88(0.5);
                inp[i] = gf.real_to_q88(1.0);
                acc = gf.mac_step(acc, inp[i], wt[i]);
            end

            $display("  Input: 8 × (1.0 × 0.5)");
            $display("  Bias: %f", gf.q88_to_real(bias));
            $display("  Result: %f (Expected: 4.25)", gf.q88_to_real(gf.extract_q88(acc)));
        end
    endtask

    // Loss Function Tests
    task test_loss_functions;
        real targets [0:3];
        real preds [0:3];
        real mae, bce;
        begin
            targets[0] = 1.0; preds[0] = 0.9;
            targets[1] = 0.0; preds[1] = 0.1;
            targets[2] = 1.0; preds[2] = 0.5;
            targets[3] = 0.0; preds[3] = 0.8;

            $display("  Target | Prediction | MAE      | BCE");
            $display("  -------+------------+----------+-------");
            for (i = 0; i < 4; i = i + 1) begin
                mae = gf.calc_mae(targets[i], preds[i]);
                bce = gf.calc_bce(targets[i], preds[i]);
                $display("  %6.1f | %10.4f | %8.6f | %7.4f",
                    targets[i], preds[i], mae, bce);
            end
        end
    endtask

endmodule
