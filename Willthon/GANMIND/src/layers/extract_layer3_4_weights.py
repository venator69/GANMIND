#!/usr/bin/env python3
"""
Extract Discriminator Layer 3 & 4 weights from PyTorch model checkpoint
and convert to Q8.8 hex format for Verilog
"""

import torch
import os
import sys

def float_to_hex_q88(fval):
    """Convert float to Q8.8 hex (16-bit signed)"""
    ival = int(round(fval * 256))
    if ival < 0:
        ival = ival + 0x10000
    return f"{(ival & 0xffff):04X}"

# Check if checkpoint file exists
checkpoint_path = "D--300.ckpt"  # Adjust path as needed
if not os.path.exists(checkpoint_path):
    print(f"ERROR: Checkpoint file '{checkpoint_path}' not found!")
    print(f"Please provide the correct path to the trained GAN checkpoint.")
    sys.exit(1)

try:
    checkpoint = torch.load(checkpoint_path, map_location='cpu')
    print("Loaded checkpoint successfully")
except Exception as e:
    print(f"ERROR loading checkpoint: {e}")
    sys.exit(1)

# Try to find discriminator layers
if 'discriminator' in checkpoint:
    disc_state = checkpoint['discriminator']
elif 'D' in checkpoint:
    disc_state = checkpoint['D']
elif 'state_dict' in checkpoint:
    disc_state = checkpoint['state_dict']
else:
    # Try to find any layer keys
    print("Available keys in checkpoint:", list(checkpoint.keys())[:10])
    disc_state = checkpoint

print("\nAvailable discriminator layers:")
layer_keys = [k for k in disc_state.keys() if '.weight' in k or '.bias' in k]
for k in sorted(layer_keys):
    val = disc_state[k]
    print(f"  {k}: shape {val.shape}")

#Extract layers
os.makedirs("hex_data", exist_ok=True)

# Layer 3 (256→256) - typically labeled as '.2.' or 'l3'
layer3_weight_key = None
layer3_bias_key = None

for key in disc_state.keys():
    if ('2.weight' in key or 'l3.weight' in key or 'layer3.weight' in key) and '4' not in key:
        layer3_weight_key = key
    if ('2.bias' in key or 'l3.bias' in key or 'layer3.bias' in key) and '4' not in key:
        layer3_bias_key = key

# Layer 4 (256→1) - typically labeled as '.3.' or 'l4'
layer4_weight_key = None
layer4_bias_key = None

for key in disc_state.keys():
    if ('3.weight' in key or 'l4.weight' in key or 'layer4.weight' in key):
        layer4_weight_key = key
    if ('3.bias' in key or 'l4.bias' in key or 'layer4.bias' in key):
        layer4_bias_key = key

if layer3_weight_key and layer3_bias_key:
    print(f"\n=== LAYER 3 ===")
    print(f"Weight key: {layer3_weight_key} | Shape: {disc_state[layer3_weight_key].shape}")
    print(f"Bias key: {layer3_bias_key} | Shape: {disc_state[layer3_bias_key].shape}")
    
    # Export Layer 3 weights
    weights_l3 = disc_state[layer3_weight_key].flatten().numpy()
    biases_l3 = disc_state[layer3_bias_key].numpy()
    
    with open("hex_data/Discriminator_Layer3_Weights_All.hex", "w") as f:
        for w in weights_l3:
            f.write(float_to_hex_q88(w) + "\n")
    
    with open("hex_data/Discriminator_Layer3_Biases_All.hex", "w") as f:
        for b in biases_l3:
            f.write(float_to_hex_q88(b) + "\n")
    
    print(f"✓ Exported Layer 3: {len(weights_l3)} weights, {len(biases_l3)} biases")
else:
    print("WARNING: Could not find Layer 3 keys")

if layer4_weight_key and layer4_bias_key:
    print(f"\n=== LAYER 4 ===")
    print(f"Weight key: {layer4_weight_key} | Shape: {disc_state[layer4_weight_key].shape}")
    print(f"Bias key: {layer4_bias_key} | Shape: {disc_state[layer4_bias_key].shape}")
    
    # Export Layer 4 weights
    weights_l4 = disc_state[layer4_weight_key].flatten().numpy()
    biases_l4 = disc_state[layer4_bias_key].numpy()
    
    with open("hex_data/Discriminator_Layer4_Weights_All.hex", "w") as f:
        for w in weights_l4:
            f.write(float_to_hex_q88(w) + "\n")
    
    with open("hex_data/Discriminator_Layer4_Biases_All.hex", "w") as f:
        for b in biases_l4:
            f.write(float_to_hex_q88(b) + "\n")
    
    print(f"✓ Exported Layer 4: {len(weights_l4)} weights, {len(biases_l4)} biases")
else:
    print("WARNING: Could not find Layer 4 keys")

print("\nHex export complete!")
