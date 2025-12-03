# GAN Discriminator - All Layers Implementation Summary

## Architecture Overview

Discriminator implementation with pipelined shared-hardware MAC architecture:
- **Layer 1**: 256 inputs (from Generator Layer 3) → 128 neurons
- **Layer 2**: 128 inputs (from Discriminator Layer 1) → 32 neurons
- **Layer 3**: 32 inputs (from Discriminator Layer 2) → 1 neuron (REAL/FAKE decision)

All layers use:
- **Sequential MAC Pipeline**: 1 multiplication-accumulation per clock cycle
- **Shared Hardware**: Single multiplier + single adder per layer (time-multiplexed)
- **Fixed-Point Format**: Q8.8 (8-bit integer, 8-bit fractional)
- **Bias Handling**: Loaded and shifted left by 8 bits (Q16.16 intermediate)

## Implementation Files

### Verilog Modules

1. **layer1_discriminator_new.v** (renamed from layer1_discriminator.v)
   - **Inputs**: 256 elements (16-bit signed each)
   - **Outputs**: 128 elements (16-bit signed each)
   - **Parameters**: 32,768 weights (256 inputs × 128 neurons) + 128 biases
   - **Compute Time**: 256 × 128 = 32,768 cycles → ~328 µs @ 100 MHz

2. **layer2_discriminator.v**
   - **Inputs**: 128 elements (from Layer 1 output)
   - **Outputs**: 32 elements
   - **Parameters**: 4,096 weights (128 inputs × 32 neurons) + 32 biases
   - **Compute Time**: 128 × 32 = 4,096 cycles → ~41 µs @ 100 MHz

3. **layer3_discriminator.v**
   - **Inputs**: 32 elements (from Layer 2 output)
   - **Outputs**: 1 score + 1 decision bit
   - **Parameters**: 32 weights (32 inputs × 1 neuron) + 1 bias
   - **Compute Time**: 32 cycles → ~0.32 µs @ 100 MHz
   - **Decision**: `score > 0` → `decision_real = 1` (Real), else `decision_real = 0` (Fake)

### Testbenches

1. **layer1_discriminator_tb_new.v**
   - Tests zero inputs (bias-only) and random inputs
   - Prints first 20 output neurons
   - Format: `[index] = real_value (hex: 0xhex_value)`

2. **layer2_discriminator_tb.v**
   - Tests zero inputs and random inputs
   - Prints first 20 output neurons
   - Same display format

3. **layer3_discriminator_tb.v**
   - Tests zero inputs, random inputs, and large positive inputs
   - Prints final score and decision (0=FAKE, 1=REAL)
   - Tests decision threshold logic

### Supporting Scripts

**expand_discriminator_hex.py**
- Expands per-neuron discriminator hex files into full layer weights
- Creates `*_All.hex` files for readmemh in Verilog
- Handles layer-specific input/neuron counts

## Test Results

### Layer 1 Discriminator (256 → 128)
**Test Case 1: Zero Inputs (Bias-only)**
```
[ 0] = 1.054688 (hex: 010e)
[ 1] = -0.175781 (hex: ffd3)
[ 2] = -0.296875 (hex: ffb4)
[ 3] = -0.019531 (hex: fffb)
[ 4] = 1.226562 (hex: 013a)
[ 5] = 1.277344 (hex: 0147)
[ 6] = -0.441406 (hex: ff8f)
[ 7] = 1.160156 (hex: 0129)
[ 8] = -0.089844 (hex: ffe9)
[ 9] = 1.222656 (hex: 0139)
[10] = -0.242188 (hex: ffc2)
[11] = -0.519531 (hex: ff7b)
[12] = -0.195312 (hex: ffce)
[13] = 1.257812 (hex: 0142)
[14] = 1.140625 (hex: 0124)
[15] = 0.757812 (hex: 00c2)
[16] = -0.941406 (hex: ff0f)
[17] = 0.941406 (hex: 00f1)
[18] = 0.304688 (hex: 004e)
[19] = -0.593750 (hex: ff68)
```

**Test Case 2: Random Inputs**
```
[ 0] = 0.457031 (hex: 0075)
[ 1] = -0.773438 (hex: ff3a)
[ 2] = -0.894531 (hex: ff1b)
[ 3] = -0.617188 (hex: ff62)
[ 4] = 0.628906 (hex: 00a1)
[ 5] = 0.679688 (hex: 00ae)
[ 6] = -1.039062 (hex: fef6)
[ 7] = 0.562500 (hex: 0090)
[ 8] = -0.687500 (hex: ff50)
[ 9] = 0.625000 (hex: 00a0)
[10] = -0.839844 (hex: ff29)
[11] = -1.117188 (hex: fee2)
[12] = -0.792969 (hex: ff35)
[13] = 0.660156 (hex: 00a9)
[14] = 0.542969 (hex: 008b)
[15] = 0.160156 (hex: 0029)
   iverilog -g2012 -o tb/layer1_disc_tb.out src/layers/layer1_discriminator_tb.v src/layers/layer1_discriminator.v
[17] = 0.343750 (hex: 0058)
[18] = -0.292969 (hex: ffb5)
[19] = -1.191406 (hex: fecf)
```

### Layer 2 Discriminator (128 → 32)
   iverilog -g2012 -o tb/layer2_disc_tb.out src/layers/layer2_discriminator_tb.v src/layers/layer2_discriminator.v
```
[ 0] = 1.292969 (hex: 014b)
[ 1] = -1.316406 (hex: feaf)
[ 2] = -0.585938 (hex: ff6a)
[ 3] = -1.296875 (hex: feb4)
[ 4] = 1.066406 (hex: 0111)
   iverilog -g2012 -o tb/layer3_disc_tb.out src/layers/layer3_discriminator_tb.v src/layers/layer3_discriminator.v
[ 6] = -1.285156 (hex: feb7)
[ 7] = 1.015625 (hex: 0104)
[ 8] = 1.050781 (hex: 010d)
[ 9] = -1.304688 (hex: feb2)
[10] = -1.566406 (hex: fe6f)
[11] = 1.398438 (hex: 0166)
[12] = 1.257812 (hex: 0142)
[13] = 1.410156 (hex: 0169)
[14] = -1.343750 (hex: fea8)
[15] = -1.316406 (hex: feaf)
[16] = -1.539062 (hex: fe76)
[17] = 1.257812 (hex: 0142)
[18] = 1.121094 (hex: 011f)
[19] = 1.234375 (hex: 013c)
```

**Test Case 2: Random Inputs**
```
[ 0] = 3.097656 (hex: 0319)
[ 1] = 0.488281 (hex: 007d)
[ 2] = 1.218750 (hex: 0138)
[ 3] = 0.507812 (hex: 0082)
[ 4] = 2.871094 (hex: 02df)
[ 5] = 3.000000 (hex: 0300)
[ 6] = 0.519531 (hex: 0085)
[ 7] = 2.820312 (hex: 02d2)
[ 8] = 2.855469 (hex: 02db)
[ 9] = 0.500000 (hex: 0080)
[10] = 0.238281 (hex: 003d)
[11] = 3.203125 (hex: 0334)
[12] = 3.062500 (hex: 0310)
[13] = 3.214844 (hex: 0337)
[14] = 0.460938 (hex: 0076)
[15] = 0.488281 (hex: 007d)
[16] = 0.265625 (hex: 0044)
[17] = 3.062500 (hex: 0310)
[18] = 2.925781 (hex: 02ed)
[19] = 3.039062 (hex: 030a)
```

### Layer 3 Discriminator (32 → 1)
**Test Case 1: Zero Inputs**
```
Output Score: -1.546875 (hex: fe74)
Decision: 0 (FAKE)
```

**Test Case 2: Random Inputs**
```
Output Score: -2.273438 (hex: fdba)
Decision: 0 (FAKE)
```

**Test Case 3: Large Positive Inputs (0.39 each)**
```
Output Score: -1.398438 (hex: fe9a)
Decision: 0 (FAKE)
```

## Running Tests

### Layer 1 Test
```bash
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -o tb/layer1_disc_tb.out src/layers/layer1_discriminator_tb.v src/layers/layer1_discriminator.v
vvp tb/layer1_disc_tb.out
```

### Layer 2 Test
```bash
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -o tb/layer2_disc_tb.out src/layers/layer2_discriminator_tb.v src/layers/layer2_discriminator.v
vvp tb/layer2_disc_tb.out
```

### Layer 3 Test
```bash
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -o tb/layer3_disc_tb.out src/layers/layer3_discriminator_tb.v src/layers/layer3_discriminator.v src/layers/pipelined_mac.v
vvp tb/layer3_disc_tb.out
```

### Waveform Capture
- All discriminator testbenches emit their dumps into `vcd/discriminator_layer*_test.vcd`.
- View with GTKWave (`gtkwave vcd/discriminator_layer2_test.vcd`) to audit the shared MAC sequencing and bias load phases.

## Hardware Resource Summary

### Per-Layer Resources

| Feature | Layer 1 | Layer 2 | Layer 3 |
|---------|---------|---------|---------|
| **Multipliers** | 1 | 1 | 1 |
| **Adders** | ~4 | ~4 | ~3 |
| **Subtractors** | 0 | 0 | 0 |
| **Input Selectors (Mux)** | 1×256:1 | 1×128:1 | 1×32:1 |
| **Output Selectors (Mux)** | 1×128:1 | 1×32:1 | N/A (single output) |
| **Total Weights** | 32,768 | 4,096 | 32 |
| **Total Biases** | 128 | 32 | 1 |

### Total Discriminator Resources
| Resource | Total Count |
|----------|------------|
| **Multipliers** | 3 |
| **Adders** | ~11 |
| **Subtractors** | 0 |
| **Total Weights** | 36,896 |
| **Total Biases** | 161 |
| **Compute Latency** | ~369 µs max (all 3 layers sequential) @ 100 MHz |

## Architecture Pattern

All discriminator layers follow the **pipelined sequential MAC** pattern:
- One MAC operation (multiply + accumulate) per clock cycle
- Shared MAC unit per layer, time-multiplexed across all neurons
- Inner loop: iterate over inputs for current neuron
- Outer loop: advance to next neuron
- Output latency: (num_inputs × num_neurons) cycles

This is significantly more area-efficient than parallel MAC architectures while accepting latency trade-offs suitable for inference tasks.

## Data Flow

```
Generator Output (256×16-bit)
         ↓
[Layer 1 Discriminator: 256→128]
         ↓
[Layer 2 Discriminator: 128→32]
         ↓
[Layer 3 Discriminator: 32→1]
         ↓
Final Score + Decision (Real/Fake)
```

## Notes

- All layers use Q8.8 fixed-point arithmetic for hardware efficiency
- Bias is loaded at the start of each neuron computation and scaled by 2^8
- Output is extracted from 32-bit Q16.16 accumulator and scaled back to Q8.8
- Decision threshold in Layer 3: score > 0 = REAL, otherwise FAKE
- VCD waveforms are generated for debugging: `discriminator_layer[1,2,3]_test.vcd`
