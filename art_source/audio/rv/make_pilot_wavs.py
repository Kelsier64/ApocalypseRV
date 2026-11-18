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


def write_clip(output, audio, peak_db, loop=False, rms_db=None):
    max_gain = 32767 * 10 ** (peak_db / 20) / np.max(np.abs(audio))
    gain = max_gain
    if rms_db is not None:
        gain = min(max_gain, 32767 * 10 ** (rms_db / 20) / np.sqrt(np.mean(audio**2)))
    with wave.open(str(output), "wb") as clip:
        clip.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        clip.writeframes(np.rint(audio * gain).astype("<i2").tobytes())
    if loop:
        # The WAV importer reads the forward loop directly from the smpl chunk.
        content = output.read_bytes()
        sample_loop = struct.pack("<15I", 0, 0, round(1e9 / RATE), 60, 0, 0, 0, 1, 0,
                                  0, 0, 0, len(audio) - 1, 0, 0)
        chunk = b"smpl" + struct.pack("<I", len(sample_loop)) + sample_loop
        output.write_bytes(content[:4] + struct.pack("<I", len(content) + len(chunk) - 8)
                           + content[8:] + chunk)


def fade_one_shot(audio, tail=0.04):
    fade_in = round(0.008 * RATE)
    fade_out = round(tail * RATE)
    audio[:fade_in] *= np.linspace(0.0, 1.0, fade_in)
    audio[-fade_out:] *= np.linspace(1.0, 0.0, fade_out)


def engine_eq(audio, resonance_hz=None):
    # Remove subsonic noise, soften the mic/gear whine and preserve the engine pulses.
    pad = RATE // 10
    padded = np.pad(audio, pad, mode="reflect")
    frequency = np.fft.rfftfreq(len(padded), 1 / RATE)
    response = (1 - np.exp(-(frequency / 21) ** 4)) / (1 + (frequency / 3800) ** 2) ** 0.5
    if resonance_hz is not None:
        response *= 10 ** (-5 * np.exp(-0.5 * ((frequency - resonance_hz) / 15) ** 2) / 20)
    return np.fft.irfft(np.fft.rfft(padded) * response, n=len(padded))[pad:-pad]


def loop_engine(audio, blend_seconds):
    overlap = round(blend_seconds * RATE)
    search = round(0.08 * RATE)
    # Match pulses near the cut before fading. Decimation is only used to select the cut.
    stride = 6
    head = audio[:overlap:stride]
    tail = audio[-overlap - search::stride]
    similarity = np.correlate(tail, head, mode="valid") / np.sqrt(np.convolve(tail**2, np.ones(len(head)), mode="valid"))
    tail_start = len(audio) - overlap - search + stride * np.argmax(similarity)
    tail_start = min(tail_start, len(audio) - overlap)
    blend = (1 - np.cos(np.linspace(0.0, np.pi, overlap))) * 0.5
    joined = (1 - blend) * audio[tail_start:tail_start + overlap] + blend * audio[:overlap]
    return np.concatenate((audio[overlap:tail_start], joined))


def make_engine_clip(source, output, start, end, *, overlap=0.0, resonance=None, rms_db=-20.0):
    audio = engine_eq(read_clip(source, start, end), resonance)
    if overlap:
        audio = loop_engine(audio, overlap)
    else:
        fade_one_shot(audio, tail=0.18)
    write_clip(output, audio, -3.0, loop=bool(overlap), rms_db=rms_db)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--engine-only", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if not args.engine_only:
        for name, start, end, peak in (("door_open", 0.55, 1.4, -3), ("door_close", 3.26, 3.96, -1)):
            audio = read_clip(args.source / "door.wav", start, end)
            audio -= np.mean(audio)
            fade_one_shot(audio)
            write_clip(args.output / f"{name}.wav", audio, peak)

    for name, recording, start, end, overlap, resonance in (
        ("engine_idle", "bus_idle", 0.40, 8.65, 0.30, 145),
        ("engine_mid", "bus_low", 0.12, 1.64, 0.22, None),
        ("engine_rev", "bus_mid", 0.26, 3.54, 0.22, 305),
    ):
        make_engine_clip(args.source / f"{recording}.wav", args.output / f"{name}.wav",
                         start, end, overlap=overlap, resonance=resonance)
    for name, start, end in (("engine_start", 0.23, 1.36), ("engine_stop", 19.93, 20.94)):
        make_engine_clip(args.source / "start_stop.wav", args.output / f"{name}.wav",
                         start, end, rms_db=-18.0)


if __name__ == "__main__":
    main()
