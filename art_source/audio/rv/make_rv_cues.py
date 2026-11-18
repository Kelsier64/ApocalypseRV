"""Cut the RV one-shot cues and contact loops from decoded CC0 recordings.

Every input is a 44.1 kHz mono PCM16 WAV named after its key in SOURCES, decoded
from the Freesound preview listed in assets/audio/rv/README.md. Variants of one
event are matched in loudness, then the loudest is set to the peak target. The
two contact loops have their slow level swings flattened before the seam.
"""

import argparse
import wave
from pathlib import Path

import numpy as np

from make_pilot_wavs import RATE, fade_one_shot, loop_engine, read_clip, write_clip

# Output file: (source, start, end) in seconds. Files sharing a prefix before the
# last underscore form one event and are loudness matched.
CUTS = {
    "handbrake_a": ("handbrake_a", 0.15, 1.30),
    "handbrake_b": ("handbrake_b", 0.18, 1.20),
    "light_switch_a": ("switch_a", 0.0, 0.30),
    "light_switch_b": ("switch_b", 0.05, 0.20),
    "hatch_release_a": ("hood_open", 0.65, 2.90),
    "hatch_latch_a": ("boot_close", 0.12, 1.20),
    "ramp_clank_a": ("ramp", 14.21, 15.40),
    "ramp_clank_b": ("ramp", 27.05, 28.05),
    "ramp_clank_c": ("ramp", 28.93, 30.50),
    "jack_ratchet_a": ("ratchet_slow", 0.0, 2.40),
    "jack_ratchet_b": ("ratchet4", 0.0, 1.85),
    "install_a": ("bolt_clunk", 12.77, 13.50),
    "install_b": ("bolt_clunk", 14.09, 14.90),
    "install_c": ("bolt_clunk", 15.51, 16.30),
    "repair_done_a": ("wrench_a", 0.0, 1.30),
    "repair_done_b": ("wrench_b", 0.04, 1.10),
    "blocked_a": ("thud", 0.0, 0.60),
    "blocked_b": ("thump_bang", 0.18, 0.90),
    "blocked_c": ("thump_bang", 2.90, 3.60),
    "puncture_a": ("puncture_a", 0.88, 1.80),
    "puncture_b": ("puncture_a", 1.92, 2.85),
    "puncture_c": ("puncture_a", 4.02, 4.95),
    "puncture_d": ("puncture_a", 4.98, 5.95),
    "tree_hit_a": ("tree_trunk", 0.70, 2.00),
    "tree_hit_b": ("tree_trunk", 3.10, 3.85),
    "tree_hit_c": ("tree_trunk", 5.94, 7.20),
    "tree_hit_d": ("tree_trunk", 9.32, 10.10),
    "tree_hit_e": ("tree_trunk", 13.36, 14.05),
    "crash_light_a": ("collide_fast", 0.0, 0.30),
    "crash_light_b": ("collide", 0.0, 0.90),
    "crash_medium_a": ("clank_crash", 0.0, 0.50),
    "crash_medium_b": ("metal_impact", 0.0, 2.20),
    "crash_heavy_a": ("crash", 0.0, 4.40),
    "crash_heavy_b": ("crash_glass", 0.0, 2.60),
}
LOOPS = {
    "tire_slip": ("squeal", 3.0, 9.0),
    "hull_scrape": ("sheet_scrape", 0.30, 2.55),
}
PEAK_DB = -1.0
LEVEL_WINDOW = 0.3


def attack_rms(audio):
    """Loudness of the first 200 ms after the attack, where variants compare."""
    start = int(np.argmax(np.abs(audio) > 0.5 * np.max(np.abs(audio))))
    head = audio[start:start + int(0.2 * RATE)]
    return np.sqrt(np.mean(head ** 2))


def flatten_level(audio):
    window = int(LEVEL_WINDOW * RATE)
    envelope = np.sqrt(np.convolve(audio ** 2, np.ones(window) / window, mode="same"))
    return audio * (np.median(envelope) / np.maximum(envelope, 0.25 * np.median(envelope)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    events = {}
    for name, (source, start, end) in CUTS.items():
        audio = read_clip(args.source / f"{source}.wav", start, end)
        audio -= np.mean(audio)
        fade_one_shot(audio)
        events.setdefault(name.rsplit("_", 1)[0], []).append((name, audio))
    for variants in events.values():
        reference = np.mean([attack_rms(audio) for _, audio in variants])
        scaled = [(name, audio * reference / attack_rms(audio)) for name, audio in variants]
        # One gain for the whole event keeps its variants level with each other.
        gain = 32767 * 10 ** (PEAK_DB / 20) / max(np.max(np.abs(audio)) for _, audio in scaled)
        for name, audio in scaled:
            with wave.open(str(args.output / f"{name}.wav"), "wb") as clip:
                clip.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
                clip.writeframes(np.rint(audio * gain).astype("<i2").tobytes())
    for name, (source, start, end) in LOOPS.items():
        audio = read_clip(args.source / f"{source}.wav", start, end)
        audio = flatten_level(audio - np.mean(audio))
        write_clip(args.output / f"{name}.wav", loop_engine(audio, 0.25), PEAK_DB, loop=True)


if __name__ == "__main__":
    main()
