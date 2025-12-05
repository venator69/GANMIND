# GAN Generator - All Layers Testbench Summary

## Overview
Semua 3 layer generator telah berhasil diimplementasikan dan ditest dengan format yang konsisten.

## Testbench Files Created

### 1. **layer1_generator_tb.v**
- **Input**: 64 elements (16-bit signed)
- **Output**: 256 elements (16-bit signed) 
- **Test Time**: ~164 microseconds (16,384 cycles)
- **Status**: ✅ WORKING

**Output Sample (20 values):**
```
[ 0] = -1.19921875 (hex: 0xfecd)
[ 1] = -0.82421875 (hex: 0xff2d)
[ 2] = -0.55468750 (hex: 0xff72)
[ 3] = -0.24609375 (hex: 0xffc1)
[ 4] = -0.46093750 (hex: 0xff8a)
[ 5] = -0.44531250 (hex: 0xff8e)
[ 6] = -1.00390625 (hex: 0xfeff)
[ 7] = -0.88281250 (hex: 0xff1e)
[ 8] = -0.60546875 (hex: 0xff65)
[ 9] = -0.41406250 (hex: 0xff96)
[10] = -1.27734375 (hex: 0xfeb9)
[11] = -0.66406250 (hex: 0xff56)
[12] = -0.92968750 (hex: 0xff12)
[13] = -1.31640625 (hex: 0xfeaf)
[14] = -0.25000000 (hex: 0xffc0)
[15] = -0.32812500 (hex: 0xffac)
[16] = -0.80859375 (hex: 0xff31)
[17] = -1.49609375 (hex: 0xfe81)
[18] = -1.00390625 (hex: 0xfeff)
[19] = -0.03906250 (hex: 0xfff6)
```

### 2. **layer2_generator_tb.v**
- **Input**: 256 elements (16-bit signed)
- **Output**: 256 elements (16-bit signed)
- **Test Time**: ~655 microseconds (65,536 cycles)
- **Status**: ✅ WORKING

**Output Sample (20 values):**
```
[ 0] = 0.46875000 (hex: 0x0078)
[ 1] = 0.06640625 (hex: 0x0011)
[ 2] = 0.05078125 (hex: 0x000d)
[ 3] = 0.19140625 (hex: 0x0031)
[ 4] = 0.72265625 (hex: 0x00b9)
[ 5] = -0.06250000 (hex: 0xfff0)
[ 6] = 0.15625000 (hex: 0x0028)
[ 7] = -0.07812500 (hex: 0xffec)
[ 8] = 0.30468750 (hex: 0x004e)
[ 9] = 0.19531250 (hex: 0x0032)
[10] = 0.50000000 (hex: 0x0080)
[11] = 0.37890625 (hex: 0x0061)
[12] = 0.22656250 (hex: 0x003a)
[13] = 0.22656250 (hex: 0x003a)
[14] = 0.21875000 (hex: 0x0038)
[15] = 0.35156250 (hex: 0x005a)
[16] = -0.18359375 (hex: 0xffd1)
[17] = 0.33593750 (hex: 0x0056)
[18] = 0.10156250 (hex: 0x001a)
[19] = 0.17968750 (hex: 0x002e)
```

### 3. **layer3_generator_tb.v**
- **Input**: 256 elements (16-bit signed)
- **Output**: 128 elements (16-bit signed)
- **Test Time**: ~328 microseconds (32,768 cycles)
- **Status**: ✅ WORKING

**Output Sample (20 values):**
```
[ 0] = -0.31250000 (hex: 0xffb0)
[ 1] = -0.40234375 (hex: 0xff99)
[ 2] = -0.48437500 (hex: 0xff84)
[ 3] = -0.44921875 (hex: 0xff8d)
[ 4] = -0.45703125 (hex: 0xff8b)
[ 5] = -0.53515625 (hex: 0xff77)
[ 6] = -0.58984375 (hex: 0xff69)
[ 7] = -0.48046875 (hex: 0xff85)
[ 8] = -0.58203125 (hex: 0xff6b)
[ 9] = -0.49218750 (hex: 0xff82)
[10] = -0.61718750 (hex: 0xff62)
[11] = -0.63671875 (hex: 0xff5d)
[12] = -0.47265625 (hex: 0xff87)
[13] = -0.53515625 (hex: 0xff77)
[14] = -0.58984375 (hex: 0xff69)
[15] = -0.42578125 (hex: 0xff93)
[16] = -0.51562500 (hex: 0xff7c)
[17] = -0.35937500 (hex: 0xffa4)
[18] = -0.54296875 (hex: 0xff75)
[19] = -0.51562500 (hex: 0xff7c)
```

## Running Tests

### Universal Testbench Workflow
Follow these steps for **any** Verilog testbench in this project so the corresponding VCD waveform is always regenerated with fresh data:

1. **Open the workspace root** and ensure the `vcd` directory exists (all benches dump there):
  ```powershell
  cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
  if (!(Test-Path vcd)) { New-Item -ItemType Directory -Path vcd | Out-Null }
  ```
2. **Build the desired testbench** with `iverilog -g2012`, writing the `.out` artifact into `tb/`:
  ```powershell
  iverilog -g2012 -o tb/<bench>.out <bench_sources>
  ```
3. **Run the bench** with `vvp tb/<bench>.out`. Each bench calls `$dumpfile("vcd/<name>.vcd")`, so replaying the test automatically overwrites the waveform.
4. (Optional) **Delete stale waveforms** before running if you want to guarantee the timestamp reflects the latest simulation:
  ```powershell
  Remove-Item vcd/<name>.vcd -ErrorAction Ignore
  ```

| Bench | Build Command (relative to repo root) | Run Command | Waveform |
|-------|---------------------------------------|-------------|----------|
| `layer1_generator_tb` | `iverilog -g2012 -o tb/layer1_gen_tb.out src/layers/layer1_generator_tb.v src/layers/layer1_generator.v` | `vvp tb/layer1_gen_tb.out` | `vcd/layer1_test.vcd` |
| `layer2_generator_tb` | `iverilog -g2012 -o tb/layer2_gen_tb.out src/layers/layer2_generator_tb.v src/layers/layer2_generator.v` | `vvp tb/layer2_gen_tb.out` | `vcd/layer2_test.vcd` |
| `layer3_generator_tb` | `iverilog -g2012 -o tb/layer3_gen_tb.out src/layers/layer3_generator_tb.v src/layers/layer3_generator.v` | `vvp tb/layer3_gen_tb.out` | `vcd/layer3_test.vcd` |
| `gan_serial_tb` | `iverilog -g2012 -o tb/gan_serial_tb.out tb/gan_serial_tb.v src/top/gan_serial_top.v ...` | `vvp tb/gan_serial_tb.out` | `vcd/gan_serial_tb.vcd` |
| `frame_sampler_tb` | `iverilog -g2012 -o tb/frame_sampler_tb.out tb/frame_sampler_tb.v src/interfaces/frame_sampler.v` | `vvp tb/frame_sampler_tb.out` | `vcd/frame_sampler_tb.vcd` |
| `vector_sigmoid_tb` | `iverilog -g2012 -o tb/vector_sigmoid_tb.out tb/vector_sigmoid_tb.v src/interfaces/vector_sigmoid.v src/interfaces/sigmoid_approx.v` | `vvp tb/vector_sigmoid_tb.out` | `vcd/vector_sigmoid_tb.vcd` |
| `interfaces_integration_tb` | `iverilog -g2012 -o tb/interfaces_integration_tb.out tb/interfaces_integration_tb.v src/interfaces/pixel_serial_loader.v src/fifo/sync_fifo.v src/interfaces/frame_sampler.v src/interfaces/vector_sigmoid.v src/interfaces/sigmoid_approx.v src/interfaces/vector_expander.v src/interfaces/vector_upsampler.v` | `vvp tb/interfaces_integration_tb.out` | `vcd/interfaces_integration_tb.vcd` |
| `gan_circle_tb` | `iverilog -g2012 -o tb/gan_circle_tb.out tb/gan_circle_tb.v tb/gan_serial_tb.v src/top/gan_serial_top.v ...` | `vvp tb/gan_circle_tb.out` | `vcd/gan_circle_tb.vcd` |
| `gan_number_two_tb` | `iverilog -g2012 -o tb/gan_number_two_tb.out tb/gan_number_two_tb.v tb/gan_serial_tb.v src/top/gan_serial_top.v ...` | `vvp tb/gan_number_two_tb.out` | `vcd/gan_number_two_tb.vcd` |

### `gan_serial_tb` Quick Run + Waveform
Fast mode keeps the generator/loader datapath checks intact while forcing cached discriminator scores so the bench finishes in seconds. From the repo root:

```powershell
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -I src/top -I src/generator -I src/discriminator -I src/interfaces -I src/layers -I src/fifo -o tb/gan_serial_tb.out tb/gan_serial_tb.v src/top/gan_serial_top.v
vvp tb/gan_serial_tb.out
gtkwave vcd/gan_serial_tb.vcd
```

The VCD shows the loader smoke test, generator pipeline checkpoints, and the fast discriminator snapshot confirmation (`Discriminator reference snapshot berhasil masuk (fast mode)`).

### Layer 1 Test
```bash
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -o tb/layer1_gen_tb.out src/layers/layer1_generator_tb.v src/layers/layer1_generator.v
vvp tb/layer1_gen_tb.out
```

### Layer 2 Test
```bash
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -o tb/layer2_gen_tb.out src/layers/layer2_generator_tb.v src/layers/layer2_generator.v
vvp tb/layer2_gen_tb.out
```

### Layer 3 Test
```bash
cd d:\GANMIND\GANMIND\Willthon\GANMIND_v0.1
iverilog -g2012 -o tb/layer3_gen_tb.out src/layers/layer3_generator_tb.v src/layers/layer3_generator.v
vvp tb/layer3_gen_tb.out
```

### Waveform Capture
- Each generator testbench writes its waveform into `vcd/layer*_test.vcd`.
- Launch GTKWave with, for example, `gtkwave vcd/layer1_test.vcd &` to inspect the sequential MAC pipeline.

## Architecture Details

### Fixed-Point Format
- Format: Q8.8 (8-bit integer, 8-bit fractional)
- Bias shift: `<<<< 8` (shift left 8 bits)
- Output: `next_acc[23:8]` (scale down from Q16.16 to Q8.8)

### Sequential MAC Pipeline
- 1 MAC operation per clock cycle
- Shared hardware MAC unit
- Pipelined neuron processing

### Compute Times (@ 100 MHz clock)
- Layer 1: 64 × 256 = 16,384 cycles → ~164 µs
- Layer 2: 256 × 256 = 65,536 cycles → ~655 µs
- Layer 3: 128 × 256 = 32,768 cycles → ~328 µs

## Data Sources
- Weights and biases loaded from `src/layers/hex_data/` directory
- Expanded format (all neurons) from Python generation script
- Layer 1: 16,384 weights + 256 biases
- Layer 2: 65,536 weights + 256 biases
- Layer 3: 32,768 weights + 128 biases

## Comparison Format
Setiap testbench menampilkan 20 output values pertama dalam format:
```
[INDEX] = REAL_VALUE (hex: 0xHEX_VALUE)
```

Format ini memudahkan untuk compare output antar layer dan verifikasi nilai fisik.

## Hardware Resource Inventory

### Per-Layer Hardware Counts

#### Layer 1 (64 inputs → 256 neurons)
| Resource Type | Count | Notes |
|---------------|-------|-------|
| **Multipliers** | 1 | Shared MAC multiplier (time-multiplexed across neurons) |
| **Adders** | ~4 | 1 main MAC adder + 1 address adder (neuron*64+input) + 2 incrementers |
| **Subtractors** | 0 | No subtraction operations |
| **Muxes (Input Select)** | 1 × 64:1 (16-bit) | Selects current input from 64-element bus |
| **Muxes (Output Select)** | 1 × 256:1 (16-bit) | Routes computed output to correct neuron position |
| **Memory (Weights)** | 16,384 × 16-bit | 256 neurons × 64 inputs per neuron |
| **Memory (Bias)** | 256 × 16-bit | One bias per neuron |

#### Layer 2 (256 inputs → 256 neurons)
| Resource Type | Count | Notes |
|---------------|-------|-------|
| **Multipliers** | 1 | Shared MAC multiplier |
| **Adders** | ~4 | 1 main MAC adder + 1 address adder (neuron*256+input) + 2 incrementers |
| **Subtractors** | 0 | No subtraction operations |
| **Muxes (Input Select)** | 1 × 256:1 (16-bit) | Selects current input from 256-element bus |
| **Muxes (Output Select)** | 1 × 256:1 (16-bit) | Routes computed output to correct neuron position |
| **Memory (Weights)** | 65,536 × 16-bit | 256 neurons × 256 inputs per neuron |
| **Memory (Bias)** | 256 × 16-bit | One bias per neuron |

#### Layer 3 (256 inputs → 128 neurons)
| Resource Type | Count | Notes |
|---------------|-------|-------|
| **Multipliers** | 1 | Shared MAC multiplier |
| **Adders** | ~4 | 1 main MAC adder + 1 address adder (neuron*256+input) + 2 incrementers |
| **Subtractors** | 0 | No subtraction operations |
| **Muxes (Input Select)** | 1 × 256:1 (16-bit) | Selects current input from 256-element bus |
| **Muxes (Output Select)** | 1 × 128:1 (16-bit) | Routes computed output to correct neuron position |
| **Memory (Weights)** | 32,768 × 16-bit | 128 neurons × 256 inputs per neuron |
| **Memory (Bias)** | 128 × 16-bit | One bias per neuron |

### Total Hardware Summary (All 3 Layers Combined)

| Resource Type | Total Count | Per-Layer Breakdown |
|---------------|-------------|---------------------|
| **Multipliers** | 3 | 1 + 1 + 1 (one per layer, shared MAC) |
| **Adders** | ~12 | ~4 + ~4 + ~4 (MAC + addressing + incrementers) |
| **Subtractors** | 0 | 0 + 0 + 0 |
| **Multiplexers** | 6 input + 3 output | See per-layer breakdown |
| **Total Weights** | 114,688 (16-bit) | 16,384 + 65,536 + 32,768 |
| **Total Biases** | 640 (16-bit) | 256 + 256 + 128 |

### Implementation Notes

- **Shared Hardware Pattern**: Each layer uses a single multiplier and single adder, time-multiplexed across all MAC operations. This is a **pipelined sequential MAC** architecture, not parallel processing.
  
- **Fixed-Point Precision**: Q8.8 representation provides 8-bit integer range (±127) and 8-bit fractional range (1/256 resolution).

- **Memory Access Patterns**:
  - Weights: Linear indexed as `layer[neuron*inputs_per_neuron + input_idx]`
  - Bias: Indexed by neuron number
  - Both use ROM (readmemh) initialized from hex files at module startup

- **Multiplexer Estimates**: Input/output selectors are counted as N:1 muxes. Actual gate-level mux count depends on synthesis tool and target (FPGA vs ASIC). For FPGA, these may be implemented as distributed RAM/LUT-based selectors rather than explicit mux gates.

- **Adder Breakdown**:
  - 1 × MAC adder (32-bit) per layer
  - 1 × Address adder per layer (calculating neuron offset + input offset)
  - 2 × Small incrementers per layer (input_idx+1, neuron_idx+1)

### Synthesis Notes
To get exact gate counts (LUT, DSP, ALM, etc.), run synthesis on target FPGA/ASIC:
- **Vivado** (Xilinx): Check DSP/BRAM utilization, LUT counts
- **Quartus** (Altera): Check ALM/M20K/DSP usage
- **Yosys** (Open-source): Generate detailed resource reports
