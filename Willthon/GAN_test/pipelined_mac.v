module pipelined_mac (
    input wire clk,
    input wire rst,
    input wire start,
    input wire signed [511:0] a_flat,
    input wire signed [511:0] b_flat,
    input wire signed [15:0] bias,
    output reg signed [15:0] result,
    output reg done
);

    // ==========================================
    // 1. PIPELINE STAGE: Input Registers (Membantu Timing DSP)
    // ==========================================
    reg signed [15:0] ra [0:31]; // Register untuk Input A
    reg signed [15:0] rb [0:31]; // Register untuk Input B

    // ==========================================
    // 2. PIPELINE STAGE: Product Registers
    // ==========================================
    reg signed [31:0] p [0:31]; 

    // ==========================================
    // 3. PIPELINE STAGE: Adder Tree
    // ==========================================
    reg signed [31:0] s1 [0:15]; // Stage Sum 1
    reg signed [31:0] s2 [0:7];  // Stage Sum 2
    reg signed [31:0] s3 [0:3];  // Stage Sum 3
    reg signed [31:0] s4 [0:1];  // Stage Sum 4
    reg signed [31:0] total_sum; // Final Sum

    // ==========================================
    // Control Signals (Shift Register Pipeline)
    // ==========================================
    // d0: Input captured
    // d1: Multiplied
    // d2..d6: Sum stages
    reg d0, d1, d2, d3, d4, d5, d6;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            d0 <= 0; d1 <= 0; d2 <= 0; d3 <= 0; 
            d4 <= 0; d5 <= 0; d6 <= 0;
            done <= 0;
            result <= 0;
            total_sum <= 0;
            // (Opsional: Reset reg data jika perlu, tapi reset control signals biasanya cukup)
        end else begin
            
            // ============================================================
            // STEP 1: Input Registration (Memotong path delay input)
            // ============================================================
            if (start) begin
                // Manual Slicing & Registering (Tanpa Loop)
                ra[0] <= a_flat[15:0];    rb[0] <= b_flat[15:0];
                ra[1] <= a_flat[31:16];   rb[1] <= b_flat[31:16];
                ra[2] <= a_flat[47:32];   rb[2] <= b_flat[47:32];
                ra[3] <= a_flat[63:48];   rb[3] <= b_flat[63:48];
                ra[4] <= a_flat[79:64];   rb[4] <= b_flat[79:64];
                ra[5] <= a_flat[95:80];   rb[5] <= b_flat[95:80];
                ra[6] <= a_flat[111:96];  rb[6] <= b_flat[111:96];
                ra[7] <= a_flat[127:112]; rb[7] <= b_flat[127:112];
                ra[8] <= a_flat[143:128]; rb[8] <= b_flat[143:128];
                ra[9] <= a_flat[159:144]; rb[9] <= b_flat[159:144];
                ra[10]<= a_flat[175:160]; rb[10]<= b_flat[175:160];
                ra[11]<= a_flat[191:176]; rb[11]<= b_flat[191:176];
                ra[12]<= a_flat[207:192]; rb[12]<= b_flat[207:192];
                ra[13]<= a_flat[223:208]; rb[13]<= b_flat[223:208];
                ra[14]<= a_flat[239:224]; rb[14]<= b_flat[239:224];
                ra[15]<= a_flat[255:240]; rb[15]<= b_flat[255:240];
                ra[16]<= a_flat[271:256]; rb[16]<= b_flat[271:256];
                ra[17]<= a_flat[287:272]; rb[17]<= b_flat[287:272];
                ra[18]<= a_flat[303:288]; rb[18]<= b_flat[303:288];
                ra[19]<= a_flat[319:304]; rb[19]<= b_flat[319:304];
                ra[20]<= a_flat[335:320]; rb[20]<= b_flat[335:320];
                ra[21]<= a_flat[351:336]; rb[21]<= b_flat[351:336];
                ra[22]<= a_flat[367:352]; rb[22]<= b_flat[367:352];
                ra[23]<= a_flat[383:368]; rb[23]<= b_flat[383:368];
                ra[24]<= a_flat[399:384]; rb[24]<= b_flat[399:384];
                ra[25]<= a_flat[415:400]; rb[25]<= b_flat[415:400];
                ra[26]<= a_flat[431:416]; rb[26]<= b_flat[431:416];
                ra[27]<= a_flat[447:432]; rb[27]<= b_flat[447:432];
                ra[28]<= a_flat[463:448]; rb[28]<= b_flat[463:448];
                ra[29]<= a_flat[479:464]; rb[29]<= b_flat[479:464];
                ra[30]<= a_flat[495:480]; rb[30]<= b_flat[495:480];
                ra[31]<= a_flat[511:496]; rb[31]<= b_flat[511:496];
            end
            d0 <= start;

            // ============================================================
            // STEP 2: Multiplication (Register to Register)
            // ============================================================
            // Ini akan infer DSP Block dengan Input Register + Output Register
            if (d0) begin
                p[0]  <= ra[0] * rb[0];    p[1]  <= ra[1] * rb[1];
                p[2]  <= ra[2] * rb[2];    p[3]  <= ra[3] * rb[3];
                p[4]  <= ra[4] * rb[4];    p[5]  <= ra[5] * rb[5];
                p[6]  <= ra[6] * rb[6];    p[7]  <= ra[7] * rb[7];
                p[8]  <= ra[8] * rb[8];    p[9]  <= ra[9] * rb[9];
                p[10] <= ra[10] * rb[10];  p[11] <= ra[11] * rb[11];
                p[12] <= ra[12] * rb[12];  p[13] <= ra[13] * rb[13];
                p[14] <= ra[14] * rb[14];  p[15] <= ra[15] * rb[15];
                p[16] <= ra[16] * rb[16];  p[17] <= ra[17] * rb[17];
                p[18] <= ra[18] * rb[18];  p[19] <= ra[19] * rb[19];
                p[20] <= ra[20] * rb[20];  p[21] <= ra[21] * rb[21];
                p[22] <= ra[22] * rb[22];  p[23] <= ra[23] * rb[23];
                p[24] <= ra[24] * rb[24];  p[25] <= ra[25] * rb[25];
                p[26] <= ra[26] * rb[26];  p[27] <= ra[27] * rb[27];
                p[28] <= ra[28] * rb[28];  p[29] <= ra[29] * rb[29];
                p[30] <= ra[30] * rb[30];  p[31] <= ra[31] * rb[31];
            end
            d1 <= d0;

            // ============================================================
            // STEP 3: Sum Stage 1 (32 -> 16)
            // ============================================================
            if (d1) begin
                s1[0] <= p[0] + p[1];   s1[1] <= p[2] + p[3];
                s1[2] <= p[4] + p[5];   s1[3] <= p[6] + p[7];
                s1[4] <= p[8] + p[9];   s1[5] <= p[10] + p[11];
                s1[6] <= p[12] + p[13]; s1[7] <= p[14] + p[15];
                s1[8] <= p[16] + p[17]; s1[9] <= p[18] + p[19];
                s1[10]<= p[20] + p[21]; s1[11]<= p[22] + p[23];
                s1[12]<= p[24] + p[25]; s1[13]<= p[26] + p[27];
                s1[14]<= p[28] + p[29]; s1[15]<= p[30] + p[31];
            end
            d2 <= d1;

            // ============================================================
            // STEP 4: Sum Stage 2 (16 -> 8)
            // ============================================================
            if (d2) begin
                s2[0] <= s1[0] + s1[1]; s2[1] <= s1[2] + s1[3];
                s2[2] <= s1[4] + s1[5]; s2[3] <= s1[6] + s1[7];
                s2[4] <= s1[8] + s1[9]; s2[5] <= s1[10]+ s1[11];
                s2[6] <= s1[12]+ s1[13];s2[7] <= s1[14]+ s1[15];
            end
            d3 <= d2;

            // ============================================================
            // STEP 5: Sum Stage 3 (8 -> 4)
            // ============================================================
            if (d3) begin
                s3[0] <= s2[0] + s2[1]; s3[1] <= s2[2] + s2[3];
                s3[2] <= s2[4] + s2[5]; s3[3] <= s2[6] + s2[7];
            end
            d4 <= d3;

            // ============================================================
            // STEP 6: Sum Stage 4 (4 -> 2)
            // ============================================================
            if (d4) begin
                s4[0] <= s3[0] + s3[1]; s4[1] <= s3[2] + s3[3];
            end
            d5 <= d4;

            // ============================================================
            // STEP 7: Final Sum & Bias (2 -> 1)
            // ============================================================
            if (d5) begin
                total_sum <= s4[0] + s4[1] + {{16{bias[15]}}, bias};
            end
            d6 <= d5;

            // ============================================================
            // STEP 8: Output Scaling
            // ============================================================
            if (d6) begin
                result <= total_sum[25:10]; // Q16.16 to Q8.8
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule