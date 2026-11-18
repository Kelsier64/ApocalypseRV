"""Cut 44.1 kHz mono PCM pilot assets from the decoded source recordings."""

import argparse
import struct
import wave
from pathlib import Path

import numpy as np


RATE = 44100


def read_clip(source, start, end):
    with wave.open(str(source), "rb") as track:
        if (track.getframerate(), track.getnchannels(), track.getsampwidth()) != (RATE, 1, 2):
            raise ValueError(f"{source} must be 44.1 kHz mono PCM16")
        track.setpos(round(start * RATE))
        return np.frombuffer(track.readframes(round((end - start) * RATE)), "<i2").astype(float)


def make_clip(source, output, start, end, peak_db, loop=0.0):
    audio = read_clip(source, start, end)
    audio -= np.mean(audio)
    if loop:
        overlap = round(loop * RATE)
        blend = (1.0 - np.cos(np.linspace(0.0, np.pi, overlap))) * 0.5
        audio = np.concatenate((audio[overlap:-overlap],
                                (1 - blend) * audio[-overlap:] + blend * audio[:overlap]))
    else:
        fade_in = round(0.008 * RATE)
        fade_out = round(0.04 * RATE)
        audio[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
        audio[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)
    audio *= 32767 * 10 ** (peak_db / 20) / np.max(np.abs(audio))
    with wave.open(str(output), "wb") as clip:
        clip.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        clip.writeframes(np.rint(audio).astype("<i2").tobytes())
    if loop:
        # The WAV importer reads the forward loop directly from the smpl chunk.
        content = output.read_bytes()
        sample_loop = struct.pack("<15I", 0, 0, round(1e9 / RATE), 60, 0, 0, 0, 1, 0,
                                  0, 0, 0, len(audio) - 1, 0, 0)
        chunk = b"smpl" + struct.pack("<I", len(sample_loop)) + sample_loop
        output.write_bytes(content[:4] + struct.pack("<I", len(content) + len(chunk) - 8)
                           + content[8:] + chunk)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, recording, start, end, peak, overlap in (
        ("door_open", "door", 0.55, 1.40, -3, 0.0),
        ("door_close", "door", 3.26, 3.96, -1, 0.0),
        ("engine_idle", "diesel", 5.60, 8.45, -5, 0.18),
        ("engine_rev", "diesel", 17.80, 18.39, -4, 0.12),
        ("engine_start", "diesel", 0.00, 0.78, -3, 0.0),
        ("engine_stop", "diesel", 26.20, 27.15, -3, 0.0),
    ):
        make_clip(args.source / f"{recording}.wav", args.output / f"{name}.wav",
                  start, end, peak, overlap)


if __name__ == "__main__":
    main()
