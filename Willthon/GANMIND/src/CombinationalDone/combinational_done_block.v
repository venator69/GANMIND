`timescale 1ns / 1ps

// ----------------------------------------------------------------------------
// combinational_done_block
// ----------------------------------------------------------------------------
// Helper ROM-style block that exposes the serialized digit sample (and optional
// expected/generated snapshot) as wide buses without requiring any clocking or
// handshakes. The memory contents are loaded once during time 0 using $readmemh
// so downstream testbenches can validate their datapaths with purely
// combinational comparisons.
// ----------------------------------------------------------------------------
module combinational_done_block #(
    parameter integer PIXEL_COUNT = 28 * 28,
    parameter string  SAMPLE_MEM_PATH   = "src/DigitIdentificationTest/digit_identifier_sample.mem",
    parameter string  EXPECTED_MEM_PATH = ""
)(
    output reg [16*PIXEL_COUNT-1:0] sample_flat,
    output reg [16*PIXEL_COUNT-1:0] expected_flat,
    output reg                      has_expected,
    output reg                      data_valid
);
    reg [15:0] sample_mem   [0:PIXEL_COUNT-1];
    reg [15:0] expected_mem [0:PIXEL_COUNT-1];
    integer idx;
    integer expected_fh;

    initial begin
        data_valid    = 1'b0;
        has_expected  = 1'b0;
        sample_flat   = {16*PIXEL_COUNT{1'b0}};
        expected_flat = {16*PIXEL_COUNT{1'b0}};

        if (SAMPLE_MEM_PATH != "") begin
            $display("[CombinationalDone] Loading sample mem %s", SAMPLE_MEM_PATH);
            $readmemh(SAMPLE_MEM_PATH, sample_mem);
            for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                sample_flat[(idx+1)*16-1 -: 16] = sample_mem[idx];
            end
        end

        if (EXPECTED_MEM_PATH != "") begin
            expected_fh = $fopen(EXPECTED_MEM_PATH, "r");
            if (expected_fh != 0) begin
                $fclose(expected_fh);
                $display("[CombinationalDone] Loading expected mem %s", EXPECTED_MEM_PATH);
                $readmemh(EXPECTED_MEM_PATH, expected_mem);
                has_expected = 1'b1;
                for (idx = 0; idx < PIXEL_COUNT; idx = idx + 1) begin
                    expected_flat[(idx+1)*16-1 -: 16] = expected_mem[idx];
                end
            end else begin
                $display("[CombinationalDone] Expected mem %s not found, skipping", EXPECTED_MEM_PATH);
            end
        end

        data_valid = 1'b1;
    end
endmodule
