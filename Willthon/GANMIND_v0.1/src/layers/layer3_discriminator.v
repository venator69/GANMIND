module layer3_discriminator (
    input wire clk,
    input wire rst,
    input wire start,
    // Flattened input bus: 32 elements * 16 bits = 512 bits
    // Input ini sudah dalam bentuk "Gepeng/Flat", jadi siap masuk MAC
    input wire signed [511:0] flat_input_flat, 
    // Output: single 16-bit score (final decision)
    output reg signed [15:0] score_out,
    output reg decision_real,
    output reg done
);

    // ==========================================
    // 1. Memory untuk Parameter (Weights & Biases)
    // ==========================================
    reg signed [15:0] w [0:31]; // Weights array (dari file hex)
    reg signed [15:0] b [0:0];  // Bias (dari file hex)

    initial begin
        // Load data hex
        $readmemh("src/layers/hex_data/Discriminator_Layer3_Weights_All.hex", w);
        $readmemh("src/layers/hex_data/Discriminator_Layer3_Biases_All.hex", b);
    end

    // ==========================================
    // 2. Flattening Weights (PENTING)
    // ==========================================
    // Kita harus mengubah Array 'w' menjadi kawat panjang 'weights_flat'
    // secara manual agar bisa masuk ke port MAC.
    wire signed [511:0] weights_flat;
    
    // Manual Concatenation (Tanpa Loop)
    // Menggabungkan w[31] sampai w[0] menjadi 1 bus lebar
    assign weights_flat = {
        w[31], w[30], w[29], w[28], w[27], w[26], w[25], w[24],
        w[23], w[22], w[21], w[20], w[19], w[18], w[17], w[16],
        w[15], w[14], w[13], w[12], w[11], w[10], w[9],  w[8],
        w[7],  w[6],  w[5],  w[4],  w[3],  w[2],  w[1],  w[0]
    };

    // Wires untuk koneksi ke output MAC
    wire mac_done;
    wire signed [15:0] mac_result;

    // ==========================================
    // 3. Instantiate Shared Pipelined MAC Module
    // ==========================================
    pipelined_mac mac_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        
        // PERHATIKAN DISINI:
        // Input Data: Langsung pass wire dari luar (Hemat resource)
        .a_flat(flat_input_flat), 
        
        // Input Weights: Pass wire yang baru kita 'gepengkan' di atas
        .b_flat(weights_flat),    
        
        .bias(b[0]),
        .result(mac_result),
        .done(mac_done)
    );

    // ==========================================
    // 4. Decision Logic
    // ==========================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            score_out <= 16'sd0;
            decision_real <= 1'b0;
            done <= 1'b0;
        end else begin
            // Pass sinyal done dari MAC ke output modul ini
            done <= mac_done; 
            
            if (mac_done) begin
                score_out <= mac_result;
                // Logika Keputusan: Real jika score > 0
                if (mac_result > 16'sd0) 
                    decision_real <= 1'b1;
                else 
                    decision_real <= 1'b0;
            end
        end
    end

endmodule