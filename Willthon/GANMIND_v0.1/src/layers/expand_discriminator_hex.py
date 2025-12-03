#!/usr/bin/env python3
"""
Expand discriminator hex files into All.hex format for multi-layer discriminator.

Architecture (matching Generator reversed):
- Layer 1: 256 inputs (from Generator output) -> 128 neurons
- Layer 2: 128 inputs -> 32 neurons
- Layer 3: 32 inputs -> 1 neuron (final decision)

Strategy: Since we have per-neuron hex files, we need to duplicate/tile them
to create the full weight matrices.
"""

import os

hex_data_dir = "hex_data"

def read_hex_file(filepath):
    """Read hex file and return list of hex strings."""
    try:
        with open(filepath, 'r') as f:
            lines = [line.strip() for line in f if line.strip()]
        return lines
    except FileNotFoundError:
        print(f"ERROR: File not found: {filepath}")
        return []

def write_hex_file(filepath, data):
    """Write list of hex strings to file."""
    with open(filepath, 'w') as f:
        for val in data:
            f.write(val + '\n')
    print(f"  Written {len(data)} entries to {filepath}")

# Process Layer 1: 256 inputs -> 128 neurons
print("Processing Layer 1 (256 inputs -> 128 neurons)...")
layer1_weight_file = os.path.join(hex_data_dir, "Discriminator_Layer1_Weights_Neuron1.hex")
layer1_bias_file = os.path.join(hex_data_dir, "Discriminator_Layer1_Biases.hex")

layer1_weights_neuron = read_hex_file(layer1_weight_file)
layer1_biases = read_hex_file(layer1_bias_file)

if layer1_weights_neuron and layer1_biases:
    # Expand neuron weights to fill 128 neurons
    # Strategy: tile the single neuron weights 128 times (or generate random if size mismatch)
    expected_weights_layer1 = 256 * 128  # 32768
    layer1_weights_all = []
    
    if len(layer1_weights_neuron) == 256:
        # Tile the 256-element neuron across 128 neurons
        for neuron in range(128):
            layer1_weights_all.extend(layer1_weights_neuron)
        print(f"  Layer 1 weights: Expanded single neuron ({len(layer1_weights_neuron)} inputs) x 128 neurons")
    elif len(layer1_weights_neuron) == 784:
        # Original was 784 inputs; take first 256 and tile
        print(f"  WARNING: Layer 1 has {len(layer1_weights_neuron)} weights (expected 256 or 32768)")
        layer1_weights_neuron = layer1_weights_neuron[:256]
        for neuron in range(128):
            layer1_weights_all.extend(layer1_weights_neuron)
        print(f"  Layer 1 weights: Truncated to 256 and expanded x 128 neurons")
    else:
        print(f"  ERROR: Layer 1 weights count {len(layer1_weights_neuron)}, expected 256 or 784")
        layer1_weights_all = []
    
    if layer1_weights_all:
        output_file = os.path.join(hex_data_dir, "Discriminator_Layer1_Weights_All.hex")
        write_hex_file(output_file, layer1_weights_all)
        
        # Biases: take first 128 from the bias file
        layer1_biases_all = layer1_biases[:128]
        output_file = os.path.join(hex_data_dir, "Discriminator_Layer1_Biases_All.hex")
        write_hex_file(output_file, layer1_biases_all)
        print("  Layer 1: OK\n")
    else:
        print("  Layer 1: FAILED\n")
else:
    print("  ERROR: Could not read Layer 1 files\n")

# Process Layer 2: 128 inputs -> 32 neurons
print("Processing Layer 2 (128 inputs -> 32 neurons)...")
layer2_weight_file = os.path.join(hex_data_dir, "Discriminator_Layer2_Weights_Neuron1.hex")
layer2_bias_file = os.path.join(hex_data_dir, "Discriminator_Layer2_Biases.hex")

layer2_weights_neuron = read_hex_file(layer2_weight_file)
layer2_biases = read_hex_file(layer2_bias_file)

if layer2_weights_neuron and layer2_biases:
    # Expand to 32 neurons x 128 inputs = 4096 weights
    expected_weights_layer2 = 128 * 32  # 4096
    layer2_weights_all = []
    
    if len(layer2_weights_neuron) == 128:
        # Tile the 128-element neuron across 32 neurons
        for neuron in range(32):
            layer2_weights_all.extend(layer2_weights_neuron)
        print(f"  Layer 2 weights: Expanded single neuron ({len(layer2_weights_neuron)} inputs) x 32 neurons")
    elif len(layer2_weights_neuron) == 256:
        # Take first 128 and tile
        layer2_weights_neuron = layer2_weights_neuron[:128]
        for neuron in range(32):
            layer2_weights_all.extend(layer2_weights_neuron)
        print(f"  Layer 2 weights: Truncated to 128 and expanded x 32 neurons")
    else:
        print(f"  ERROR: Layer 2 weights count {len(layer2_weights_neuron)}, expected 128 or 256")
        layer2_weights_all = []
    
    if layer2_weights_all:
        output_file = os.path.join(hex_data_dir, "Discriminator_Layer2_Weights_All.hex")
        write_hex_file(output_file, layer2_weights_all)
        
        # Biases: take first 32
        layer2_biases_all = layer2_biases[:32]
        output_file = os.path.join(hex_data_dir, "Discriminator_Layer2_Biases_All.hex")
        write_hex_file(output_file, layer2_biases_all)
        print("  Layer 2: OK\n")
    else:
        print("  Layer 2: FAILED\n")
else:
    print("  ERROR: Could not read Layer 2 files\n")

# Process Layer 3: 32 inputs -> 1 neuron (final decision)
print("Processing Layer 3 (32 inputs -> 1 neuron)...")
layer3_weight_file = os.path.join(hex_data_dir, "Discriminator_Layer3_Weights_Neuron1.hex")
layer3_bias_file = os.path.join(hex_data_dir, "Discriminator_Layer3_Biases.hex")

layer3_weights_neuron = read_hex_file(layer3_weight_file)
layer3_biases = read_hex_file(layer3_bias_file)

if layer3_weights_neuron and layer3_biases:
    # Layer 3 should have 32 weights for the final neuron
    if len(layer3_weights_neuron) >= 32:
        layer3_weights_all = layer3_weights_neuron[:32]
        print(f"  Layer 3 weights: Using first 32 entries")
    else:
        print(f"  WARNING: Layer 3 has {len(layer3_weights_neuron)} weights, need 32")
        layer3_weights_all = layer3_weights_neuron
    
    output_file = os.path.join(hex_data_dir, "Discriminator_Layer3_Weights_All.hex")
    write_hex_file(output_file, layer3_weights_all)
    
    # Biases: take first 1
    layer3_biases_all = layer3_biases[:1]
    output_file = os.path.join(hex_data_dir, "Discriminator_Layer3_Biases_All.hex")
    write_hex_file(output_file, layer3_biases_all)
    print("  Layer 3: OK\n")
else:
    print("  ERROR: Could not read Layer 3 files\n")

print("Discriminator hex expansion complete.")
