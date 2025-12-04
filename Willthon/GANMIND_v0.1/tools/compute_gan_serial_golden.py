#!/usr/bin/env python3
"""Generate golden reference data for gan_serial_top testbench.

The script reproduces the deterministic stimulus used by tb/gan_serial_tb.v and
runs a software model of the generator + discriminator pipelines using the same
hex weight/bias dumps that the RTL consumes. The resulting vectors/scores are
written to tb/golden/*.hex so the testbench can compare every major pipeline
stage against a known-good snapshot.
"""
from __future__ import annotations

from pathlib import Path
from typing import List, Sequence, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]
HEX_DIR = REPO_ROOT / "src" / "layers" / "hex_data"
GOLDEN_DIR = REPO_ROOT / "tb" / "golden"

DATA_WIDTH = 16
Q_FRAC = 8
ONE_Q = 1 << Q_FRAC
HALF_Q = 1 << (Q_FRAC - 1)
SIGMOID_SAT = 1024  # matches sigmoid_approx SAT_LIMIT


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def wrap32(value: int) -> int:
    value &= 0xFFFFFFFF
    if value & 0x80000000:
        value -= 0x1_0000_0000
    return value


def to_signed16(value: int) -> int:
    value &= 0xFFFF
    if value & 0x8000:
        value -= 0x10000
    return value


def slice_q(acc: int) -> int:
    shifted = acc >> Q_FRAC
    return to_signed16(shifted)


def load_hex(path: Path) -> List[int]:
    values: List[int] = []
    with path.open() as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("//"):
                continue
            values.append(to_signed16(int(line, 16)))
    return values


def write_hex(path: Path, values: Sequence[int]) -> None:
    with path.open("w") as fh:
        for val in values:
            fh.write(f"{val & 0xFFFF:04x}\n")


def lfsr_sequence(seed: int = 0xACE1, count: int = 64) -> List[int]:
    state = seed & 0xFFFF
    seq: List[int] = []
    for _ in range(count):
        seq.append(to_signed16(state))
        feedback = ((state >> 15) ^ (state >> 13) ^ (state >> 12) ^ (state >> 10)) & 1
        state = ((state << 1) & 0xFFFF) | feedback
    return seq


def dense_layer(
    vec_in: Sequence[int],
    weights: Sequence[int],
    bias: Sequence[int],
    in_count: int,
) -> List[int]:
    out_count = len(bias)
    out: List[int] = []
    for neuron in range(out_count):
        acc = wrap32(bias[neuron] << Q_FRAC)
        base = neuron * in_count
        for idx in range(in_count):
            prod = wrap32(vec_in[idx] * weights[base + idx])
            acc = wrap32(acc + prod)
        out.append(slice_q(acc))
    return out


def sigmoid_vector(vec: Sequence[int]) -> List[int]:
    result: List[int] = []
    for sample in vec:
        if sample >= SIGMOID_SAT:
            result.append(ONE_Q)
        elif sample <= -SIGMOID_SAT:
            result.append(0)
        else:
            approx = HALF_Q + (sample >> 2)
            approx = max(0, min(ONE_Q, approx))
            result.append(to_signed16(approx))
    return result


def lut_expand(vec: Sequence[int], out_count: int) -> List[int]:
    in_count = len(vec)
    expanded: List[int] = []
    for out_idx in range(out_count):
        src_idx = (out_idx * in_count) // out_count
        expanded.append(vec[src_idx])
    return expanded


def build_frame_pattern() -> List[int]:
    frame: List[int] = []
    for idx in range(28 * 28):
        bit = 1 if (idx % 7 == 0) else 0
        frame.append(bit * ONE_Q)
    return frame


def frame_sampler(frame: Sequence[int], out_count: int = 256) -> List[int]:
    input_count = len(frame)
    base_step = input_count // out_count
    step_rem = input_count % out_count
    out: List[int] = []
    src_index = 0
    rem_accum = 0
    for _ in range(out_count):
        out.append(frame[src_index])
        if step_rem == 0:
            src_index = min(input_count - 1, src_index + base_step)
            continue
        rem_accum += step_rem
        next_idx = src_index + base_step
        if rem_accum >= out_count:
            rem_accum -= out_count
            next_idx += 1
        src_index = min(input_count - 1, next_idx)
    return out


def discriminator_head(vec: Sequence[int], golden: dict) -> Tuple[int, int]:
    l1 = dense_layer(vec, golden["disc_l1_w"], golden["disc_l1_b"], 256)
    l2 = dense_layer(l1, golden["disc_l2_w"], golden["disc_l2_b"], 128)
    l3_acc = wrap32(golden["disc_l3_b"][0] << Q_FRAC)
    for i in range(32):
        prod = wrap32(l2[i] * golden["disc_l3_w"][i])
        l3_acc = wrap32(l3_acc + prod)
    score = slice_q(l3_acc)
    decision = 1 if score > 0 else 0
    return score, decision


def main() -> None:
    ensure_dir(GOLDEN_DIR)

    gold = {
        "gen_l1_w": load_hex(HEX_DIR / "layer1_gen_weights.hex"),
        "gen_l1_b": load_hex(HEX_DIR / "layer1_gen_bias.hex"),
        "gen_l2_w": load_hex(HEX_DIR / "Generator_Layer2_Weights_All.hex"),
        "gen_l2_b": load_hex(HEX_DIR / "Generator_Layer2_Biases_All.hex"),
        "gen_l3_w": load_hex(HEX_DIR / "Generator_Layer3_Weights_All.hex"),
        "gen_l3_b": load_hex(HEX_DIR / "Generator_Layer3_Biases_All.hex"),
        "disc_l1_w": load_hex(HEX_DIR / "Discriminator_Layer1_Weights_All.hex"),
        "disc_l1_b": load_hex(HEX_DIR / "Discriminator_Layer1_Biases_All.hex"),
        "disc_l2_w": load_hex(HEX_DIR / "Discriminator_Layer2_Weights_All.hex"),
        "disc_l2_b": load_hex(HEX_DIR / "Discriminator_Layer2_Biases_All.hex"),
        "disc_l3_w": load_hex(HEX_DIR / "Discriminator_Layer3_Weights_All.hex"),
        "disc_l3_b": load_hex(HEX_DIR / "Discriminator_Layer3_Biases_All.hex"),
    }

    seeds = lfsr_sequence()
    g_l1 = dense_layer(seeds, gold["gen_l1_w"], gold["gen_l1_b"], 64)
    g_l2 = dense_layer(g_l1, gold["gen_l2_w"], gold["gen_l2_b"], 256)
    g_l3 = dense_layer(g_l2, gold["gen_l3_w"], gold["gen_l3_b"], 256)
    g_sigmoid = sigmoid_vector(g_l3)
    fake_disc_vec = lut_expand(g_sigmoid, 256)
    fake_frame = lut_expand(g_sigmoid, 784)

    frame = build_frame_pattern()
    sampled_real = frame_sampler(frame)

    fake_score, fake_flag = discriminator_head(fake_disc_vec, gold)
    real_score, real_flag = discriminator_head(sampled_real, gold)

    write_hex(GOLDEN_DIR / "gan_seed.hex", seeds)
    write_hex(GOLDEN_DIR / "gan_gen_features.hex", g_l3)
    write_hex(GOLDEN_DIR / "gan_sigmoid.hex", g_sigmoid)
    write_hex(GOLDEN_DIR / "gan_fake_disc_vec.hex", fake_disc_vec)
    write_hex(GOLDEN_DIR / "gan_fake_frame.hex", fake_frame)
    write_hex(GOLDEN_DIR / "gan_real_sample.hex", sampled_real)
    write_hex(GOLDEN_DIR / "gan_scores.hex", [fake_score, fake_flag, real_score, real_flag])

    print("Generated golden data in", GOLDEN_DIR)


if __name__ == "__main__":
    main()
