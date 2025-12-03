# GAN-MIND: Complete Hardware Architecture

## System Overview

Full end-to-end GAN (Generative Adversarial Network) implementation in pipelined shared-hardware Verilog:
- **Generator**: 3-layer MLP producing 256-element fake MNIST digits
- **Discriminator**: 3-layer MLP classifying real vs fake images

Waveforms for the serialized path land in `vcd/gan_serial_tb.vcd`, ready for inspection via `gtkwave vcd/gan_serial_tb.vcd`.
- **Training Target**: MNIST digit generation (28×28 pixels → 256 flattened values)

## Complete System Data Flow

```
                    GENERATOR PATH
                    ===============
Random Seed (100 bits)
        ↓
[Layer 1 Gen: 100 → 256]  ~164 µs (16,384 cycles)
        ↓ 256 neurons
[Layer 2 Gen: 256 → 256]  ~655 µs (65,536 cycles)
        ↓ 256 neurons
[Layer 3 Gen: 256 → 128]  ~328 µs (32,768 cycles)
        ↓ 128 neurons
Generated Fake Image (128 elements, Q8.8)
        ↓
        └─────────────────────┐
                              ↓
                    DISCRIMINATOR PATH
                    ==================
Real MNIST Image OR Fake Generated Image (256-256 elements)
        ↓
[Layer 1 Disc: 256 → 128]  ~328 µs (32,768 cycles)
        ↓ 128 neurons
[Layer 2 Disc: 128 → 32]   ~41 µs (4,096 cycles)
        ↓ 32 neurons
[Layer 3 Disc: 32 → 1]     ~0.32 µs (32 cycles)
        ↓ 1 neuron
Final Decision: Real (1) or Fake (0)
Score Output: -2 to +2 (Q8.8 logit)
```

## Serialized I/O Wrapper

To follow the latest block diagram (pseudo-random seed → generator → sigmoid → discriminator with serialized 28×28 pixels), the repository now includes a structured wrapper around the existing layers:

- `src/fifo/sync_fifo.v`: BRAM-friendly synchronous FIFO so serialized pixels do not consume thousands of registers.
- `src/interfaces/pixel_serial_loader.v`: Aggregates 28×28 binary pixels into a flattened Q8.8 frame using the FIFO and exposes a `frame_valid/frame_consume` handshake.
- `src/generator/seed_lfsr_bank.v` and `src/generator/generator_pipeline.v`: Deterministic latent-vector source plus an FSM that sequences the three generator layers.
- `src/interfaces/vector_sigmoid.v` + `sigmoid_approx.v`: Cheap sigmoid approximation applied element-wise before visualization or discriminator sharing.
- `src/interfaces/frame_sampler.v`, `vector_expander.v`, `vector_upsampler.v`: Deterministic resampling blocks to map 784 serialized pixels to the discriminator’s 256-feature input and back to 28×28 for debug output.
- `src/discriminator/discriminator_pipeline.v`: Runs the discriminator stack twice per transaction (fake then real) while reusing the same hardware.
- `src/top/gan_serial_top.v`: High-level controller that accepts serialized pixels, launches the generator/discriminator pair, and reports both logits along with a rebuilt 28×28 frame.
- **Synthesis friendly**: All RTL modules are clocked, avoid behavioral delays, and any simulation-only guards (`$error`) live under ``ifndef SYNTHESIS`` (see `src/fifo/sync_fifo.v`).

A dedicated testbench lives in `tb/gan_serial_tb.v`; it streams a synthetic serialized frame, asserts `start`, waits for `done`, and prints the discriminator scores together with the `generated_frame_valid` flag. This verifies the full serialized data path before integrating with external logic.

## Module Specifications

### Generator Layers

#### Gen Layer 1
- **Architecture**: 100 inputs → 256 neurons
- **Total Parameters**: 25,600 weights + 256 biases
- **Fixed-Point**: Q8.8 input/output, Q16.16 accumulator
- **Latency**: 100 × 256 = 25,600 cycles
- **File**: `layer1_generator.v`

#### Gen Layer 2
- **Architecture**: 256 inputs → 256 neurons
- **Total Parameters**: 65,536 weights + 256 biases
- **Latency**: 256 × 256 = 65,536 cycles
- **File**: `layer2_generator.v`

#### Gen Layer 3
- **Architecture**: 256 inputs → 128 neurons
- **Total Parameters**: 32,768 weights + 128 biases
- **Latency**: 256 × 128 = 32,768 cycles
- **Output**: Final generated image (128 elements)
- **File**: `layer3_generator.v`

### Discriminator Layers

#### Disc Layer 1
- **Architecture**: 256 inputs → 128 neurons
- **Total Parameters**: 32,768 weights + 128 biases
- **Latency**: 256 × 128 = 32,768 cycles
- **File**: `layer1_discriminator_new.v`

#### Disc Layer 2
- **Architecture**: 128 inputs → 32 neurons
- **Total Parameters**: 4,096 weights + 32 biases
- **Latency**: 128 × 32 = 4,096 cycles
- **File**: `layer2_discriminator.v`

#### Disc Layer 3
- **Architecture**: 32 inputs → 1 neuron
- **Total Parameters**: 32 weights + 1 bias
- **Output**: Final score (16-bit) + decision bit
- **Decision Logic**: score > 0 → Real, score ≤ 0 → Fake
- **Latency**: 32 cycles
- **File**: `layer3_discriminator.v`

## Total Hardware Resources (All 6 Layers)

| Resource | Generator | Discriminator | **Total** |
|----------|-----------|---------------|----------|
| **Multipliers** | 3 | 3 | **6** |
| **Adders** | ~12 | ~11 | **~23** |
| **Subtractors** | 0 | 0 | **0** |
| **Total Weights** | 114,688 | 36,896 | **151,584** |
| **Total Biases** | 640 | 161 | **801** |
| **Max Sequential Latency** | ~1.15 ms | ~0.37 ms | **~1.52 ms** |

## Compute Performance @ 100 MHz Clock

### Generator Throughput (Sequential Layers)
- Layer 1: 16,384 cycles → 163.84 µs
- Layer 2: 65,536 cycles → 655.36 µs
- Layer 3: 32,768 cycles → 327.68 µs
- **Total Generator Latency**: 1,146.88 µs ≈ **1.15 ms per image**

### Discriminator Throughput (Sequential Layers)
- Layer 1: 32,768 cycles → 327.68 µs
- Layer 2: 4,096 cycles → 40.96 µs
- Layer 3: 32 cycles → 0.32 µs
- **Total Discriminator Latency**: 368.96 µs ≈ **0.37 ms per image**

### Full GAN Pipeline (Sequential)
- Generate 1 fake image: 1.15 ms
- Discriminate real/fake: 0.37 ms
- **One complete cycle**: ~1.52 ms

**Throughput**: ~657 GAN iterations per second @ 100 MHz sequential pipeline

## Fixed-Point Arithmetic Details

### Q8.8 Format
- **Range**: -128 to +127.99609375
- **Resolution**: 1/256 ≈ 0.00391 (about 0.4%)
- **Representation**: 16-bit signed integer
  - Bits [15:8]: Integer part (signed)
  - Bits [7:0]: Fractional part

### MAC Pipeline (Q16.16 Intermediate)
- **Accumulator**: 32-bit signed
  - Bits [31:16]: Integer part (Q8 range: -32768 to +32767)
  - Bits [15:0]: Fractional part
- **Bias Scaling**: Bias (Q8.8) ≪ 8 → Q16.16
- **Output Scaling**: Accumulator[23:8] → Q8.8

### Example Calculation
```
Bias = -1.546875 (hex: fe74) = -396 in Q8.8
Loaded as: -396 <<< 8 = -101376 (Q16.16)

Product = 0.3 × 0.5 = 0.15
  = (77 Q8.8) × (128 Q8.8) = 9856 (32-bit product)
Accumulated: -101376 + 9856 = -91520

Output: -91520[23:8] = -1441 >> 8 ≈ -5.625... actually -1441 (Q8.8) ÷ 256 = -5.625

Final output: -1441 & 0xFFFF = 0xfc3f = -961 in Q8.8 = -3.75
```

## Memory Organization

### Generator Parameter Storage (ROM/RAM)
- `src/layers/hex_data/Generator_Layer1_Weights_All.hex`: 25,600 lines (layer1 weights)
- `src/layers/hex_data/Generator_Layer1_Biases_All.hex`: 256 lines
- `src/layers/hex_data/Generator_Layer2_Weights_All.hex`: 65,536 lines
- `src/layers/hex_data/Generator_Layer2_Biases_All.hex`: 256 lines
- `src/layers/hex_data/Generator_Layer3_Weights_All.hex`: 32,768 lines
- `src/layers/hex_data/Generator_Layer3_Biases_All.hex`: 128 lines
- **Total Generator ROM**: ~124 KB

### Discriminator Parameter Storage (ROM/RAM)
- `src/layers/hex_data/Discriminator_Layer1_Weights_All.hex`: 32,768 lines
- `src/layers/hex_data/Discriminator_Layer1_Biases_All.hex`: 128 lines
- `src/layers/hex_data/Discriminator_Layer2_Weights_All.hex`: 4,096 lines
- `src/layers/hex_data/Discriminator_Layer2_Biases_All.hex`: 32 lines
- `src/layers/hex_data/Discriminator_Layer3_Weights_All.hex`: 32 lines
- `src/layers/hex_data/Discriminator_Layer3_Biases_All.hex`: 1 line
- **Total Discriminator ROM**: ~37.8 KB

## Testbench Files

### Generator Testbenches
- `layer1_generator_tb.v`: Tests 64→256 (for compatibility/testing)
- `layer2_generator_tb.v`: Tests 256→256
- `layer3_generator_tb.v`: Tests 256→128
- All testbenches print first 20 outputs in Q8.8 real and hex format

### Discriminator Testbenches
- `layer1_discriminator_tb_new.v`: Tests 256→128
- `layer2_discriminator_tb.v`: Tests 128→32
- `layer3_discriminator_tb.v`: Tests 32→1 (decision logic)

## Synthesis & Implementation Notes

### FPGA Targeting (Xilinx/Altera)
- Each multiplier may map to 1 DSP block (18×25 or 27×27)
- Adders likely distributed across LUT/ALU slices
- ROM weights can use BRAM or distributed LUT RAM
- Estimated footprint (rough):
  - **DSP**: 6 blocks (for 6 multipliers)
  - **BRAM**: 4-6 blocks (for weight storage)
  - **LUT**: 2000-5000 LUTs (MAC logic + control)
  - **FF**: 1000-2000 flip-flops (registers + accumulator)

### ASIC Implementation
- Leakage power dominated by large ROM blocks
- Peak power: ~100-500 mW @ 100 MHz (rough estimate)
- Silicon area: ~5-10 mm² @ 28nm (rough estimate)
- Main contributors: ROM (70%), MAC logic (20%), control (10%)

## Performance vs Accuracy Trade-off

### Q8.8 Fixed-Point Limitations
- **Precision Loss**: ~0.4% due to 8-bit fractional quantization
- **Range Limitation**: Score clipping at ±128 in theory (soft-clipped by readmemh)
- **Training Impact**: May reduce convergence speed; suitable for inference-only

### Optimization Opportunities
1. **Higher Precision**: Q16.16 (32-bit per element) - doubles memory/bandwidth
2. **Lower Precision**: Q4.4 (8-bit) - reduces area 50% but may degrade performance
3. **Parallel MAC**: Multiple MACs per layer - trades area for speed
4. **Pipelined Stages**: Insert registers between layers - enables higher clock speeds

## Usage & Integration

### Serialized Top-Level Simulation

Run the end-to-end wrapper before hooking it to external logic:

```bash
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -o tb/gan_serial_tb.out tb/gan_serial_tb.v \
        src/top/gan_serial_top.v src/interfaces/pixel_serial_loader.v \
        src/fifo/sync_fifo.v src/interfaces/frame_sampler.v \
        src/interfaces/vector_expander.v src/interfaces/vector_upsampler.v \
        src/interfaces/sigmoid_approx.v src/interfaces/vector_sigmoid.v \
        src/generator/seed_lfsr_bank.v src/generator/generator_pipeline.v \
        src/discriminator/discriminator_pipeline.v \
        src/layers/layer1_generator.v src/layers/layer2_generator.v src/layers/layer3_generator.v \
        src/layers/layer1_discriminator.v src/layers/layer2_discriminator.v src/layers/layer3_discriminator.v \
        src/layers/pipelined_mac.v
vvp tb/gan_serial_tb.out
```

Expected log excerpt (seed/drain FIFOs in place):

```
=== GAN Serial Test Complete ===
D(G(z)) score = -713 | real? 0
D(x)    score = -2425 | real? 0
Generated frame valid: 1
```

### Test Input Images & .mem Conversion

The folder `src/test_input_image/` ships a ready-made 28×28 circle sample (`test_circle.mem`) plus `mem_image_tools.py`.
The `.mem` file stores 784 Q8.8 pixels (one per line) and mirrors the format used by
`generated_frame_flat` and the discriminator real-image sampler. Use the helper script to
preview or author frames:

```powershell
# Convert .mem → human-viewable ASCII PGM (loadable by IrfanView, GIMP, ImageMagick)
python src/test_input_image/mem_image_tools.py mem-to-pgm `
        src/test_input_image/test_circle.mem build/test_circle.pgm

# Convert edited PGM → .mem to feed back into the GAN pipeline
python src/test_input_image/mem_image_tools.py pgm-to-mem `
        build/my_frame.pgm build/my_frame.mem
```

For handwritten digits, `src/test_input_number_two/` contains:

- `test_number_two.mem` + `.png` + `.jpg`: autogenerated digit “2” assets (28×28).
- `number_two_tools.py`: Pillow-backed helper to go between PNG/JPG and Q8.8 `.mem`.
- `test_number_two_generated.mem/.png/.jpg`: GAN output captured via `tb/gan_number_two_tb.v`.

Usage examples:

```powershell
# Generate or refresh the default digit assets
python src/test_input_number_two/number_two_tools.py generate --out src/test_input_number_two

# Convert any mem → png/jpg
python src/test_input_number_two/number_two_tools.py mem-to-image `
        src/test_input_number_two/test_number_two_generated.mem `
        build/test_number_two_generated.png build/test_number_two_generated.jpg

# Convert PNG/JPG edits back into mem
python src/test_input_number_two/number_two_tools.py image-to-mem `
        src/test_input_number_two/test_number_two.png `
        build/test_number_two_from_png.mem
```

The dedicated regression `tb/gan_circle_tb.v` streams `test_circle.mem` through `gan_serial_top`, dumps the generator
output to `src/test_input_image/test_circle_generated.mem`, and compares it against the golden
`test_circle_expected.mem`. Convert the generated file back into an image with:

```powershell
python src/test_input_image/mem_image_tools.py mem-to-pgm `
        src/test_input_image/test_circle_generated.mem build/test_circle_generated.pgm
```

Similarly, `tb/gan_number_two_tb.v` uses the digit “2” assets and produces/validates
`src/test_input_number_two/test_number_two_generated.mem`, which can be viewed with

```powershell
python src/test_input_number_two/number_two_tools.py mem-to-image `
        src/test_input_number_two/test_number_two_generated.mem `
        build/test_number_two_generated.png build/test_number_two_generated.jpg
```

Tip: After a serialized run (`vvp tb/gan_serial_tb.out`), capture the 784-sample frame that you wish
to inspect (e.g., via a cocotb probe or by dumping `generated_frame_flat` into a text file) and then
run `mem-to-pgm` to visualize the GAN output. The same script works for any other 28×28 `.mem` file
you intend to inject as a “real” image.

### Standalone Layer Testing
```verilog
// Example: instantiate Generator Layer 1
layer1_generator gen_l1 (
    .clk(clk),
    .rst(rst),
    .start(start_gen),
    .flat_input_flat(seed_bus),     // 100×16-bit random seed
    .flat_output_flat(gen_l1_out),  // 256×16-bit layer1 output
    .done(gen_l1_done)
);
```

### Chained Pipeline
```verilog
// Connect Gen L1 → Gen L2 → Gen L3 → Disc L1 → Disc L2 → Disc L3
assign gen_l2_input = gen_l1_output;
assign gen_l3_input = gen_l2_output;
assign disc_l1_input = gen_l3_output;
// ... etc
```

### Training Loop Integration
(Software side, not shown in Verilog, but architecture supports):
1. Generate fake image (1.15 ms)
2. Discriminate fake (0.37 ms)
3. Discriminate real (0.37 ms)
4. Calculate loss, update weights
5. Repeat

## File Structure
```
GAN_test/
├── src/
│   ├── fifo/ (sync_fifo)
│   ├── generator/ (seed_lfsr_bank, generator_pipeline)
│   ├── discriminator/ (discriminator_pipeline)
│   ├── interfaces/ (pixel loader, samplers, sigmoid, upsamplers)
│   ├── layers/
│   │   ├── layer*_generator*.v / layer*_discriminator*.v / pipelined_mac.v
│   │   ├── layer*_generator/discriminator testbenches
│   │   ├── hex_data/ (all weights, biases, and layer1 standalone hex files)
│   │   └── *.py tooling (expand_hex, gen_disc_data, verify scripts, etc.)
│   └── top/ (gan_serial_top)
├── tb/
│   └── gan_serial_tb.v
├── TESTBENCH_SUMMARY.md (Generator summary)
├── DISCRIMINATOR_SUMMARY.md (Discriminator summary)
└── GAN_ARCHITECTURE.md (This file)
```

## Next Steps / Future Enhancements

1. **Integration Test**: Connect all 6 layers end-to-end with feedback training loop
2. **Activation Functions**: Add ReLU/Leaky ReLU after each layer (currently linear)
3. **Batch Processing**: Pipeline multiple images through layers simultaneously
4. **Dynamic Precision**: Adapt Q8.8 scaling based on layer statistics
5. **Hardware Verification**: Synthesis on Vivado/Quartus with gate-level simulation
6. **Throughput Optimization**: Unroll inner loop for parallel MACs (2-4× speedup)
7. **Training Hardware**: Add weight update logic (gradient computation + SGD)

## References

- Q8.8 Fixed-Point Arithmetic: `https://en.wikipedia.org/wiki/Fixed-point_arithmetic`
- MAC Pipeline Design: Sequential multiply-accumulate with shared hardware
- GAN Architecture: Simplified MNIST-compatible 3-layer MLP (no BatchNorm/Conv)
