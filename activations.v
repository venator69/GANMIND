//====================================================
// FIXED POINT ACTIVATION FUNCTIONS
// Q4.4 (8-bit), Q8.8 (16-bit), Q16.16 (32-bit)
//====================================================

//====================================================
// 1. LEAKY RELU
//====================================================

// Q4.4 (8 bit)
module LRELU_8(
    input  wire signed [7:0] x, a,      
    output wire signed [7:0] y          
);
    assign y = (x > 0) ? x : ((a * x) >>> 4);
endmodule

// Q8.8 (16 bit)
module LRELU_16(
    input  wire signed [15:0] x, a,     
    output wire signed [15:0] y         
);
    assign y = (x > 0) ? x : ((a * x) >>> 8);
endmodule

// Q16.16 (32 bit)
module LRELU_32(
    input  wire signed [31:0] x, a,    
    output wire signed [31:0] y         
);
    assign y = (x > 0) ? x : ((a * x) >>> 16);
endmodule



//====================================================
// 2. SIGMOID 3 SEGMENT
//====================================================

// Q4.4 (8 bit)
module sigmoid_8_3(
    input  wire signed [7:0] x,
    output reg  signed [7:0] y
);

localparam signed [7:0] POS2 = 32;
localparam signed [7:0] NEG2 = -32;
localparam signed [7:0] ONE  = 16;

always @(*) begin
    if (x > POS2)
        y = ONE;
    else if (x < NEG2)
        y = 0;
    else
        y = ((x >>> 1) + ONE) >>> 1;
end
endmodule

// Q8.8 (16 bit)
module sigmoid_16_3(
    input  wire signed [15:0] x,
    output reg  signed [15:0] y
);

localparam signed [15:0] POS2 = 512;
localparam signed [15:0] NEG2 = -512;
localparam signed [15:0] ONE  = 256;

always @(*) begin
    if (x > POS2)
        y = ONE;
    else if (x < NEG2)
        y = 0;
    else
        y = ((x >>> 1) + ONE) >>> 1;
end
endmodule

// Q16.16 (32 bit)
module sigmoid_32_3(
    input  wire signed [31:0] x,
    output reg  signed [31:0] y
);

localparam signed [31:0] POS2 = 131072;
localparam signed [31:0] NEG2 = -131072;
localparam signed [31:0] ONE  = 65536;

always @(*) begin
    if (x > POS2)
        y = ONE;
    else if (x < NEG2)
        y = 0;
    else
        y = ((x >>> 1) + ONE) >>> 1;
end
endmodule



//====================================================
// 3. SIGMOID 5 SEGMENT
//====================================================

// Q4.4 (8 bit)
module sigmoid_8_5(
    input  wire signed [7:0] x,
    output reg  signed [7:0] y
);

localparam signed [7:0] B1  = 28;
localparam signed [7:0] B2  = 12;
localparam signed [7:0] NB1 = -28;
localparam signed [7:0] NB2 = -12;

localparam signed [7:0] ONE    = 16;
localparam signed [7:0] A125   = 2;
localparam signed [7:0] VAL15  = 24;
localparam signed [7:0] VAL875 = 14;

always @(*) begin
    if (x >= B1)
        y = ONE;
    else if (x <= NB1)
        y = 0;
    else if (x > NB1 && x < NB2)
        y = ((((x <<< 1) + VAL15) >>> 2) + A125) >>> 1;
    else if (x < B1 && x > B2)
        y = ((((x <<< 1) - VAL15) >>> 2) + VAL875) >>> 1;
    else
        y = ((x >>> 1) + ONE) >>> 1;
end
endmodule



// Q8.8 (16 bit)
module sigmoid_16_5(
    input  wire signed [15:0] x,
    output reg  signed [15:0] y
);

localparam signed [15:0] B1  = 448;
localparam signed [15:0] B2  = 192;
localparam signed [15:0] NB1 = -448;
localparam signed [15:0] NB2 = -192;

localparam signed [15:0] ONE    = 256;
localparam signed [15:0] A125   = 32;
localparam signed [15:0] VAL15  = 384;
localparam signed [15:0] VAL875 = 224;

always @(*) begin
    if (x >= B1)
        y = ONE;
    else if (x <= NB1)
        y = 0;
    else if (x > NB1 && x < NB2)
        y = ((((x <<< 1) + VAL15) >>> 2) + A125) >>> 1;
    else if (x < B1 && x > B2)
        y = ((((x <<< 1) - VAL15) >>> 2) + VAL875) >>> 1;
    else
        y = ((x >>> 1) + ONE) >>> 1;
end
endmodule



// Q16.16 (32 bit)
module sigmoid_32_5(
    input  wire signed [31:0] x,
    output reg  signed [31:0] y
);

localparam signed [31:0] B1  = 114688;
localparam signed [31:0] B2  = 49152;
localparam signed [31:0] NB1 = -114688;
localparam signed [31:0] NB2 = -49152;

localparam signed [31:0] ONE    = 65536;
localparam signed [31:0] A125   = 8192;
localparam signed [31:0] VAL15  = 98304;
localparam signed [31:0] VAL875 = 57344;

always @(*) begin
    if (x >= B1)
        y = ONE;
    else if (x <= NB1)
        y = 0;
    else if (x > NB1 && x < NB2)
        y = ((((x <<< 1) + VAL15) >>> 2) + A125) >>> 1;
    else if (x < B1 && x > B2)
        y = ((((x <<< 1) - VAL15) >>> 2) + VAL875) >>> 1;
    else
        y = ((x >>> 1) + ONE) >>> 1;
end
endmodule




//====================================================
// 4. TANH 5 SEGMENT
//====================================================

// Q4.4 (8 bit)
module tanh_8_5(
    input  wire signed [7:0] x,
    output reg  signed [7:0] y
);

localparam signed [7:0] B1  = 12;
localparam signed [7:0] NB1 = -12;
localparam signed [7:0] B2  = 4;
localparam signed [7:0] NB2 = -4;

always @(*) begin
    if (x >= B1)
        y = 16;
    else if (x <= NB1)
        y = -16;
    else if (x > NB1 && x < NB2)
        y = ((x <<< 1) + 4) >>> 2;
    else if (x < B1 && x > B2)
        y = ((x <<< 1) - 4) >>> 2;
    else
        y = x;
end
endmodule


// Q8.8 (16 bit)
module tanh_16_5(
    input  wire signed [15:0] x,
    output reg  signed [15:0] y
);

localparam signed [15:0] B1  = 192;
localparam signed [15:0] NB1 = -192;
localparam signed [15:0] B2  = 64;
localparam signed [15:0] NB2 = -64;

always @(*) begin
    if (x >= B1)
        y = 256;
    else if (x <= NB1)
        y = -256;
    else if (x > NB1 && x < NB2)
        y = ((x <<< 1) + 64) >>> 2;
    else if (x < B1 && x > B2)
        y = ((x <<< 1) - 64) >>> 2;
    else
        y = x;
end
endmodule


// Q16.16 (32 bit)
module tanh_32_5(
    input  wire signed [31:0] x,
    output reg  signed [31:0] y
);

localparam signed [31:0] B1  = 49152;
localparam signed [31:0] NB1 = -49152;
localparam signed [31:0] B2  = 16384;
localparam signed [31:0] NB2 = -16384;

always @(*) begin
    if (x >= B1)
        y = 65536;
    else if (x <= NB1)
        y = -65536;
    else if (x > NB1 && x < NB2)
        y = ((x <<< 1) + 16384) >>> 2;
    else if (x < B1 && x > B2)
        y = ((x <<< 1) - 16384) >>> 2;
    else
        y = x;
end
endmodule

