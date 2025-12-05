#!/usr/bin/env python3
"""
Verify Layer 2 Discriminator Biases
Compares expected vs actual hex values
"""

# Expected biases from user (Float and Hex Q8.8)
expected_biases = [
    (1.29300988, 0x014b),
    (-1.31465769, 0xfeaf),
    (-0.58568686, 0xff6a),
    (-1.29754198, 0xfeb4),
    (1.06772745, 0x0111),
    (1.19425619, 0x0132),
    (-1.28709793, 0xfeb7),
    (1.01370919, 0x0104),
    (1.05142260, 0x010d),
    (-1.30480039, 0xfeb2),
    (-1.56781900, 0xfe6f),
    (1.39993393, 0x0166),
    (1.25715721, 0x0142),
    (1.40841556, 0x0169),
    (-1.34417367, 0xfea8),
    (-1.31545198, 0xfeaf),
    (-1.53970063, 0xfe76),
    (1.25737250, 0x0142),
    (1.12097859, 0x011f),
    (1.23386490, 0x013c),
]

def hex_to_float_q88(hex_val):
    """Convert 16-bit hex to Q8.8 float"""
    # Handle as signed 16-bit
    if hex_val > 0x7fff:
        val = hex_val - 0x10000
    else:
        val = hex_val
    return val / 256.0

def float_to_hex_q88(fval):
    """Convert Q8.8 float to 16-bit hex"""
    ival = int(round(fval * 256))
    if ival < 0:
        ival = ival + 0x10000
    return ival & 0xffff

print("=" * 70)
print("LAYER 2 DISCRIMINATOR BIAS VERIFICATION")
print("=" * 70)
print()

mismatches = []
for i, (exp_float, exp_hex) in enumerate(expected_biases):
    # Convert expected hex back to float to see what it should be
    reconstructed_float = hex_to_float_q88(exp_hex)
    computed_hex = float_to_hex_q88(exp_float)
    
    match = "✓" if computed_hex == exp_hex else "✗"
    
    print(f"[{i:2d}] Float: {exp_float:10.8f} | Expected Hex: 0x{exp_hex:04x} | Computed Hex: 0x{computed_hex:04x} {match}")
    print(f"      Reconstructed from hex: {reconstructed_float:10.8f}")
    
    if computed_hex != exp_hex:
        mismatches.append(i)
        print(f"      ⚠️  MISMATCH!")
    print()

print("=" * 70)
print(f"SUMMARY: {len(mismatches)} mismatches out of {len(expected_biases)} biases")
print("=" * 70)

if mismatches:
    print(f"Mismatched indices: {mismatches}")
else:
    print("✅ All biases match expected values!")

# Read actual biases from Biases_All.hex and compare
print()
print("=" * 70)
print("CHECKING ACTUAL HEX FILE...")
print("=" * 70)

try:
    with open('hex_data/Biases_All.hex', 'r') as f:
        hex_lines = f.readlines()
    
    print(f"Found {len(hex_lines)} bias values in Biases_All.hex")
    print()
    
    actual_mismatches = []
    for i in range(min(20, len(hex_lines))):
        hex_str = hex_lines[i].strip()
        if hex_str:
            actual_hex = int(hex_str, 16)
            exp_float, exp_hex = expected_biases[i]
            
            actual_float = hex_to_float_q88(actual_hex)
            exp_computed_float = hex_to_float_q88(exp_hex)
            
            match = "✓" if actual_hex == exp_hex else "✗"
            print(f"[{i:2d}] Expected: 0x{exp_hex:04x} ({exp_computed_float:10.8f}) | Actual: 0x{actual_hex:04x} ({actual_float:10.8f}) {match}")
            
            if actual_hex != exp_hex:
                actual_mismatches.append(i)
    
    print()
    print(f"FILE MISMATCH SUMMARY: {len(actual_mismatches)} differences in first 20 biases")
    if actual_mismatches:
        print(f"Mismatched at indices: {actual_mismatches}")
        print("\n⚠️  Layer 2 biases in hex file DO NOT match expected values!")
    else:
        print("✅ Layer 2 biases in hex file MATCH expected values!")
        
except FileNotFoundError:
    print("❌ Biases_All.hex not found in hex_data/")
except Exception as e:
    print(f"❌ Error reading hex file: {e}")
