"""Build the RV sample bank from a mono 44.1 kHz Engine Simulator dyno render.

Hold each RPM for 4.8 s in ascending order, repeating the sweep at each pedal
opening. Input is little-endian signed PCM16 starting at the first hold.
"""
import argparse
import wave
from pathlib import Path

import numpy as np
from scipy import signal

RPM = (750, 1000, 1350, 1750, 2200, 2700, 3150, 3600)
PEDAL = (0.0, 0.45, 1.0)
RATE = 44100
HOLD = round(4.8 * RATE)
CYCLES = 16
SAMPLES_PER_CYCLE = 2048  # One complete four-stroke cycle spans two revolutions.


def extract_loop(hold, rpm):
    period = RATE * 120 / rpm
    # Leave the first part of the hold to settle after a dyno change.
    start = len(hold) - round((CYCLES + 1) * period) - 32
    offset = np.arange((CYCLES + 1) * SAMPLES_PER_CYCLE) * period / SAMPLES_PER_CYCLE
    cutoff = min(0.98, 0.94 * SAMPLES_PER_CYCLE / period)
    filtered = signal.sosfiltfilt(signal.butter(8, cutoff, output="sos"), hold)
    cycles = np.interp(start + offset, np.arange(len(hold)), filtered)
    cycles = cycles.reshape(CYCLES + 1, SAMPLES_PER_CYCLE)
    fade = np.sin(np.linspace(0, np.pi / 2, SAMPLES_PER_CYCLE)) ** 2
    cycles[0] = cycles[-1] * (1 - fade) + cycles[0] * fade
    loop = cycles[:-1].flatten()
    return loop - loop.mean()


def mean_cycle(loop):
    cycle = loop.reshape(CYCLES, SAMPLES_PER_CYCLE).mean(axis=0)
    return cycle / np.linalg.norm(cycle)


def build(raw, output):
    if abs(len(raw) - HOLD * len(RPM) * len(PEDAL)) > 2:
        raise ValueError("Expected one 4.8-second hold per RPM and pedal setting")
    loops = []
    for load_index in range(len(PEDAL)):
        for rpm_index, rpm in enumerate(RPM):
            offset = len(loops) * HOLD
            loop = extract_loop(raw[offset:offset + HOLD], rpm)
            # Align engine orders with both neighbouring axes before crossfading.
            neighbours = []
            if rpm_index:
                neighbours.append(mean_cycle(loops[-1]))
            if load_index:
                neighbours.append(mean_cycle(loops[-len(RPM)]))
            if neighbours:
                target = np.sum(neighbours, axis=0)
                correlation = np.fft.irfft(np.fft.rfft(target) * np.fft.rfft(mean_cycle(loop)).conj())
                loop = np.roll(loop, correlation.argmax())
            loops.append(loop)
    # A single trim preserves the model's relative level between loads and RPMs.
    samples = np.rint(np.concatenate(loops) * 2.4)
    if np.max(np.abs(samples)) >= 32767:
        raise ValueError("Output would clip")
    with wave.open(str(output), "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", ""))
        wav.writeframes(samples.astype("<i2").tobytes())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("render", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(np.fromfile(args.render, dtype="<i2"), args.output)
