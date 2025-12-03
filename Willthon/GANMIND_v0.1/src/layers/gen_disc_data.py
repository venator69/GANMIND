import numpy as np

# --- KONFIGURASI ---
INPUT_SIZE = 256  # Sesuai output Generator
OUTPUT_SIZE = 1   # Skor Real/Fake
FRAC_BITS = 8     # Q8.8 Fixed Point

def float_to_q8_8(x):
    # Konversi float ke integer 16-bit (Q8.8)
    val = int(x * (2**FRAC_BITS))
    if val < -32768: val = -32768
    if val > 32767: val = 32767
    return val & 0xFFFF # Format hex 16-bit

def to_hex(val):
    return f"{val:04x}"

# 1. Generate Random Weights & Bias
# Bobot kecil agar tidak overflow cepat
weights = np.random.uniform(-0.5, 0.5, size=(INPUT_SIZE)) 
bias = np.random.uniform(-0.5, 0.5)

# 2. Simpan ke File HEX (untuk Verilog)
with open("layer1_disc_weights.hex", "w") as f:
    for w in weights:
        f.write(to_hex(float_to_q8_8(w)) + "\n")

with open("layer1_disc_bias.hex", "w") as f:
    f.write(to_hex(float_to_q8_8(bias)) + "\n")

# 3. Buat Test Vector (Input Random)
input_vector = np.random.uniform(-1.0, 1.0, size=(INPUT_SIZE))

# 4. Hitung Hasil Diharapkan (Python Float Logic)
# Rumus: dot_product(input, weights) + bias
expected_output_float = np.dot(input_vector, weights) + bias
expected_decision = 1 if expected_output_float > 0 else 0

# 5. Hitung Hasil Simulasi Hardware (Fixed Point Logic)
accum_fixed = int(bias * 256) * 256 # Bias digeser di accumulator (Q16.16 equivalent)
for i in range(INPUT_SIZE):
    in_fixed = int(input_vector[i] * 256)
    w_fixed = int(weights[i] * 256)
    accum_fixed += (in_fixed * w_fixed)

final_fixed_output = accum_fixed // 256 # Kembalikan ke Q8.8
final_fixed_output = max(-32768, min(32767, final_fixed_output)) # Clamp 16-bit

print("=== DATA UNTUK TESTBENCH ===")
print("Copy input_vector di bawah ini ke dalam testbench Verilog jika perlu manual,")
print("atau gunakan logic generate random di testbench.")
print("\n=== HASIL VALIDASI (GOLDEN REF) ===")
print(f"Bias Float: {bias:.4f}")
print(f"Expected Score (Float): {expected_output_float:.4f}")
print(f"Expected Score (Q8.8 Int): {final_fixed_output}")
print(f"Expected Hex Output: {to_hex(final_fixed_output & 0xFFFF)}")
print(f"Decision: {'REAL' if expected_decision else 'FAKE'}")

# Simpan input test vector ke file hex juga agar mudah diload testbench
with open("disc_input_test.hex", "w") as f:
    for val in input_vector:
        f.write(to_hex(float_to_q8_8(val)) + "\n")

print("\nFile 'layer1_disc_weights.hex', 'layer1_disc_bias.hex', dan 'disc_input_test.hex' telah dibuat.")