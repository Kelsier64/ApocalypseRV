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


def engine_eq(audio):
    # Remove subsonic noise and soften the top end while preserving engine pulses.
    pad = RATE // 10
    padded = np.pad(audio, pad, mode="reflect")
    frequency = np.fft.rfftfreq(len(padded), 1 / RATE)
    response = (1 - np.exp(-(frequency / 21) ** 4)) / (1 + (frequency / 3800) ** 2) ** 0.5
    return np.fft.irfft(np.fft.rfft(padded) * response, n=len(padded))[pad:-pad]


def overlap_offset(reference, candidates):
    # Match pulses before fading. Decimation is only used to select the cut.
    stride = 6
    pattern = reference[::stride]
    search = candidates[::stride]
    power = np.convolve(search**2, np.ones(len(pattern)), mode="valid")
    similarity = np.correlate(search, pattern, mode="valid") / np.sqrt(np.maximum(power, 1.0))
    return min(stride * np.argmax(similarity), len(candidates) - len(reference))


def blend_audio(tail, head):
    blend = (1 - np.cos(np.linspace(0.0, np.pi, len(head)))) * 0.5
    return (1 - blend) * tail + blend * head


def loop_engine(audio, blend_seconds):
    overlap = round(blend_seconds * RATE)
    search_start = len(audio) - overlap - round(0.06 * RATE)
    tail_start = search_start + overlap_offset(audio[:overlap], audio[search_start:])
    seam = blend_audio(audio[tail_start:tail_start + overlap], audio[:overlap])
    return np.concatenate((audio[overlap:tail_start], seam))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, start, end, peak in (("door_open", 0.55, 1.4, -3), ("door_close", 3.26, 3.96, -1)):
        audio = read_clip(args.source / "door.wav", start, end)
        audio -= np.mean(audio)
        fade_one_shot(audio)
        write_clip(args.output / f"{name}.wav", audio, peak)
    # One lever motion each: out of the old gear, then into the new one.
    for name, start, end in (("gear_shift_a", 0.24, 0.70), ("gear_shift_b", 0.94, 1.34)):
        audio = read_clip(args.source / "gear_select.wav", start, end)
        audio -= np.mean(audio)
        fade_one_shot(audio, tail=0.08)
        write_clip(args.output / f"{name}.wav", audio, -1)
    for name, start, end in (("engine_start", 0.23, 1.36), ("engine_stop", 19.93, 20.94)):
        audio = engine_eq(read_clip(args.source / "start_stop.wav", start, end))
        fade_one_shot(audio, tail=0.18)
        write_clip(args.output / f"{name}.wav", audio, -3.0, rms_db=-18.0)


if __name__ == "__main__":
    main()
