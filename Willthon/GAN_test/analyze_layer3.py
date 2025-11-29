#!/usr/bin/env python3
# Compare Layer 3 expected vs actual outputs

print('=' * 80)
print('LAYER 3 DISCRIMINATOR - EXPECTED vs ACTUAL COMPARISON')
print('=' * 80)
print()

expected_cases = {
    'Zero Inputs': (0.175538, 0x002d),
    'Random Inputs': (0.700075, 0x00b3),
    'Large Positive': (1.000000, 0x0100),
}

actual_cases = {
    'Zero Inputs': (-1.546875, 0xfe74),
    'Random Inputs': (-2.273438, 0xfdba),
    'Large Positive': (-1.398438, 0xfe9a),
}

for case_name in ['Zero Inputs', 'Random Inputs', 'Large Positive']:
    exp_val, exp_hex = expected_cases[case_name]
    act_val, act_hex = actual_cases[case_name]
    diff = exp_val - act_val
    
    print(f'Test Case: {case_name}')
    print(f'  Expected: {exp_val:10.6f} (hex: 0x{exp_hex:04x})')
    print(f'  Actual:   {act_val:10.6f} (hex: 0x{act_hex:04x})')
    print(f'  Difference: {diff:10.6f}')
    print()

print('=' * 80)
print('DIAGNOSIS:')
print('=' * 80)
print()
print('❌ MAJOR MISMATCH - Layer 3 Architecture is WRONG')
print()
print('EXPECTED: Layer 3 should have 256 inputs → 1 output')
print('  - Zero input bias should be ~0.1755 (positive)')
print('  - Currently getting bias = -1.546875 (negative)')
print()
print('CURRENT: Layer 3 has only 32 inputs → 1 output')
print('  - This is receiving Layer 2 output (32 neurons)')
print('  - But should be receiving full 256-element input')
print()
print('CONCLUSION:')
print('  Layer 3 is INCORRECT - needs to be restructured!')
print()
print('Actual current architecture: Generator(256) → Disc1(256→128) → Disc2(128→32) → Disc3(32→1)')
print()
print('Expected architecture appears to be: Generator(256) → Disc(256→1)')
print('  OR')
print('Expected could be: Generator(256) → Disc1(256→128) → Disc2(128→32) → Disc3(32→256) → Disc4(256→1)')
print()
