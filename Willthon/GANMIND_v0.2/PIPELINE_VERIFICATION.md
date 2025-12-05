# GAN Generator - Pipeline & Shared Hardware Verification

## Architecture Confirmation ✅

Semua 3 layer generator sudah diimplementasikan dengan **Sequential MAC Pipeline** dan **Shared Hardware** architecture.

---

## 1. LAYER 1 GENERATOR - Pipelined Shared Hardware ✅

### Architecture Components:

**Shared Hardware MAC Unit:**
```verilog
// Single combinational MAC unit - shared for all neurons
wire signed [31:0] current_product = current_input * layer1_gen_weights[neuron_idx*64 + input_idx];
wire signed [31:0] next_acc = accumulator + current_product;
```
- 1 multiplier (16-bit × 16-bit → 32-bit)
- 1 adder (32-bit + 32-bit)
- Multipleksed across all 256 neurons

**Sequential Pipeline State:**
```verilog
reg [8:0] neuron_idx;   // Current neuron being processed (0..255)
reg [6:0] input_idx;    // Current input index (0..63)
reg busy;               // Pipeline state machine
reg signed [31:0] accumulator;  // Holds partial result
```

**1 MAC Operation Per Clock Cycle:**
- Clock 1-64: Neuron 0 (64 MACs for 64 inputs)
- Clock 65-128: Neuron 1 (64 MACs for 64 inputs)
- ...continues...
- Clock 16320-16384: Neuron 255 (64 MACs for 64 inputs)

**Total Computation:** 256 neurons × 64 inputs = **16,384 clock cycles**

### Pipelined Execution Flow:
```
start → Load bias[0] → MAC[0] → MAC[1] → ... → MAC[63] → Write output[0] → 
        Load bias[1] → MAC[0] → MAC[1] → ... → MAC[63] → Write output[1] → 
        ... → done
```

---

## 2. LAYER 2 GENERATOR - Pipelined Shared Hardware ✅

### Architecture Components:

**Shared Hardware MAC Unit:**
```verilog
// Single combinational MAC unit - shared for all neurons
wire signed [31:0] current_product = current_input * layer2_gen_weights[neuron_idx*256 + input_idx];
wire signed [31:0] next_acc = accumulator + current_product;
```
- Same structure as Layer 1
- 1 multiplier (16-bit × 16-bit → 32-bit)
- 1 adder (32-bit + 32-bit)

**Sequential Pipeline State:**
```verilog
reg [8:0] neuron_idx;   // Current neuron being processed (0..255)
reg [8:0] input_idx;    // Current input index (0..255)
reg busy;               // Pipeline state machine
reg signed [31:0] accumulator;  // Holds partial result
```

**1 MAC Operation Per Clock Cycle:**
- Clock 1-256: Neuron 0 (256 MACs for 256 inputs)
- Clock 257-512: Neuron 1 (256 MACs for 256 inputs)
- ...continues...
- Clock 65281-65536: Neuron 255 (256 MACs for 256 inputs)

**Total Computation:** 256 neurons × 256 inputs = **65,536 clock cycles**

### Pipelined Execution Flow:
```
start → Load bias[0] → MAC[0] → MAC[1] → ... → MAC[255] → Write output[0] → 
        Load bias[1] → MAC[0] → MAC[1] → ... → MAC[255] → Write output[1] → 
        ... → done
```

---

## 3. LAYER 3 GENERATOR - Pipelined Shared Hardware ✅

### Architecture Components:

**Shared Hardware MAC Unit:**
```verilog
// Single combinational MAC unit - shared for all neurons
wire signed [31:0] current_product = current_input * layer3_gen_weights[neuron_idx*256 + input_idx];
wire signed [31:0] next_acc = accumulator + current_product;
```
- Same structure as Layer 1 & 2
- 1 multiplier (16-bit × 16-bit → 32-bit)
- 1 adder (32-bit + 32-bit)

**Sequential Pipeline State:**
```verilog
reg [7:0] neuron_idx;   // Current neuron being processed (0..127)
reg [8:0] input_idx;    // Current input index (0..255)
reg busy;               // Pipeline state machine
reg signed [31:0] accumulator;  // Holds partial result
```

**1 MAC Operation Per Clock Cycle:**
- Clock 1-256: Neuron 0 (256 MACs for 256 inputs)
- Clock 257-512: Neuron 1 (256 MACs for 256 inputs)
- ...continues...
- Clock 32513-32768: Neuron 127 (256 MACs for 256 inputs)

**Total Computation:** 128 neurons × 256 inputs = **32,768 clock cycles**

### Pipelined Execution Flow:
```
start → Load bias[0] → MAC[0] → MAC[1] → ... → MAC[255] → Write output[0] → 
        Load bias[1] → MAC[0] → MAC[1] → ... → MAC[255] → Write output[1] → 
        ... → done
```

---

## Comparison Table: All Layers

| Feature | Layer 1 | Layer 2 | Layer 3 |
|---------|---------|---------|---------|
| **Inputs** | 64 | 256 | 256 |
| **Neurons** | 256 | 256 | 128 |
| **Weights** | 16,384 | 65,536 | 32,768 |
| **MAC Unit** | 1 shared | 1 shared | 1 shared |
| **Cycles/Neuron** | 64 | 256 | 256 |
| **Total Cycles** | 16,384 | 65,536 | 32,768 |
| **Time @ 100MHz** | 163.8 µs | 655.4 µs | 327.7 µs |
| **Pipeline** | ✅ Sequential | ✅ Sequential | ✅ Sequential |
| **Hardware Share** | ✅ 1 MAC unit | ✅ 1 MAC unit | ✅ 1 MAC unit |

---

## Key Pipeline Features ✅

### 1. **Shared MAC Unit**
Setiap layer menggunakan **1 MAC multiplier** yang di-multiplex untuk semua neuron:
- Tidak ada multiple MAC units
- Hemat area hardware
- Throughput terbatas 1 MAC/clock

### 2. **Sequential Processing**
```verilog
always @(posedge clk or posedge rst) begin
    // Per-neuron processing
    if (start && !busy) begin
        neuron_idx <= 0;
        accumulator <= bias[0];
        busy <= 1;
    end else if (busy) begin
        accumulator <= next_acc;  // Update setiap clock
        if (input_idx == MAX_INPUT) begin
            // Output done, move to next neuron
            neuron_idx <= neuron_idx + 1;
        end
    end
end
```

### 3. **Fixed-Point Arithmetic**
- Bias: `<<<< 8` (shift left 8 bits untuk Q8.8 format)
- Output: `[23:8]` scaling dari Q16.16 ke Q8.8
- Single accumulator untuk semua intermediate results

### 4. **Latency Characteristics**
- Input to first output: 64-256 clocks (neuron 0 complete)
- Pipelined: 1 output per neuron after initial latency
- Final output latency: N_neurons × N_inputs cycles

---

## 4. DISCRIMINATOR PIPELINE - Shared Hardware ✅

The discriminator side mirrors the generator philosophy: each layer streams data through a **single shared MAC** with synchronous FIFOs buffering ingress/egress so the RTL stays synthesizable.

### FIFO-Fed Pipeline
```verilog
sync_fifo #(.DATA_WIDTH(16), .DEPTH(256)) u_sample_fifo (...);
sync_fifo #(.DATA_WIDTH(16), .DEPTH(4))   u_score_fifo  (...);
```
- **Ingress**: 256 samples pushed via `sample_wr_en` into a BRAM-friendly FIFO.
- **Controller**: `LOAD → L1 → L2 → L3 → OUTPUT` FSM pulls one sample per cycle, pulses each layer’s `start`, and reuses the MAC fabric exactly once per layer.
- **Egress**: Final score enters a small FIFO so the host can pop it later without stalling the datapath.

### Synthesizable Sequencing
```verilog
if (start && sample_fifo_level_int >= SAMPLE_COUNT && !score_fifo_full) begin
    state <= LOAD; // all work happens inside clocked always block
end
```
- No `#delay`, `real`, or behavioral constructs in RTL modules.
- All resets synchronous (apart from async reset input) ensuring clean mapping to FPGA/ASIC flows.
- `sync_fifo` guard is hidden behind ``ifndef SYNTHESIS`` so timing analyzers ignore `$error` checks.

### Shared MAC Usage
- `layer1_discriminator`, `layer2_discriminator`, and `layer3_discriminator` each instantiate **one multiplier + accumulator** reused across neurons.
- The top-level `discriminator_pipeline` simply feeds flattened vectors between layers; no extra MACs are created.

### Timing Summary (@100 MHz)
| Stage | Cycles |
|-------|--------|
| L1    | 32,768 |
| L2    | 4,096  |
| L3    | 32     |
| **Total** | **36,896** |

---

## Verification Results ✅

All three testbenches successfully ran:

### Layer 1
```
Computation Time: 163.88 ms (16,384 cycles @ 100MHz)
Status: ✅ PASSED
```

### Layer 2
```
Computation Time: 655.40 ms (65,536 cycles @ 100MHz)
Status: ✅ PASSED
```

### Layer 3
```
Computation Time: 327.72 ms (32,768 cycles @ 100MHz)
Status: ✅ PASSED
```

### Discriminator Stack
```
Latency: 36,896 cycles @ 100 MHz ≈ 369 µs
Status: ✅ PASSED (see DISCRIMINATOR_SUMMARY)
```

---

## Conclusion

✅ **All 3 generators are properly pipelined with shared hardware:**
- Sequential MAC pipeline (1 MAC/cycle)
- Single shared multiplier per layer
- Efficient area usage
- Deterministic latency
- Clean finite-state machine control

This is an **optimal time-area tradeoff** for neural network inference on FPGA.
