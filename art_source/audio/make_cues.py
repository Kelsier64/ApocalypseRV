"""Cut the pistol, panel damage, monster, player, scrapper and rain sounds.

Inputs are the Freesound previews listed in the assets/audio/<domain>/README.md
files, decoded to 44.1 kHz PCM16 WAV and named after the SOURCES keys below:
mono, except the two rain recordings, which stay stereo. Variants of one event
are matched in loudness after their attack, then the loudest is set to the peak
target. Loops are crossfaded at the seam and carry a forward loop in a smpl chunk.

    python art_source/audio/make_cues.py <decoded folder> assets/audio
"""

import argparse
import struct
import wave
from pathlib import Path

import numpy as np

RATE = 44100
PEAK_DB = -1.0
FADE_IN = 0.001

# Freesound id of each decoded input, for reproducing the source folder.
SOURCES = {
    "shot_9mm": 427592, "shot_glock": 828786, "shot_handgun": 668348,
    "reload_hipower": 674569, "dry_fire": 674568,
    "metal_bangs": 798843, "metal_shear": 669692, "rv_window_smash": 452670,
    "scrap_drop": 587443, "glass_pickup": 156579, "glass_fall": 336425,
    "hand_metal": 344563, "hand_metal_2": 344562, "hand_metal_3": 344561,
    "hollow_bang": 157609, "hollow_thunk": 406493,
    "gut_rip": 530919, "gore_tear": 762900, "gore_impact": 641046,
    "power_kick": 586841, "body_fall_heavy": 504626,
    "shredder_factory": 679018, "rain_light": 167034, "rain_heavy": 200272,
    "tinnitus_t": 377205,
}

# Output "domain/file": list of (source, start, end, offset, gain dB) layers and
# the fade-out length. Files sharing the part before the last underscore form
# one event and are loudness matched.
CUTS = {
    "pistol/shot_a": ([("shot_9mm", 0.11, 1.30)], 0.30),
    "pistol/shot_b": ([("shot_glock", 0.0, 1.20)], 0.30),
    "pistol/shot_c": ([("shot_handgun", 0.0, 0.46)], 0.10),
    "pistol/dry_fire_a": ([("dry_fire", 0.0, 0.29)], 0.05),
    # Magazine out, magazine in, slide release, placed on the 1.5 s reload.
    "pistol/reload_a": ([("reload_hipower", 0.0, 0.42, 0.0), ("reload_hipower", 0.98, 1.70, 0.48),
                         ("reload_hipower", 3.47, 3.85, 1.12)], 0.05),
    "rv/panel_dent_a": ([("metal_bangs", 0.0, 0.75)], 0.25),
    "rv/panel_dent_b": ([("metal_bangs", 1.42, 2.17)], 0.25),
    "rv/panel_dent_c": ([("metal_bangs", 4.90, 5.65)], 0.25),
    "rv/panel_dent_d": ([("metal_bangs", 15.43, 16.18)], 0.25),
    "rv/panel_dent_e": ([("metal_bangs", 22.30, 23.05)], 0.25),
    "rv/panel_break_a": ([("metal_bangs", 17.63, 18.60, 0.0), ("metal_shear", 2.47, 3.60, 0.05, -4.0)], 0.30),
    "rv/panel_break_b": ([("rv_window_smash", 0.10, 2.00, 0.0), ("metal_bangs", 7.91, 8.70, 0.0, -3.0)], 0.40),
    "rv/panel_break_c": ([("metal_bangs", 23.36, 24.30, 0.0), ("glass_fall", 0.0, 1.20, 0.02, -6.0)], 0.40),
    "rv/debris_metal_a": ([("scrap_drop", 0.02, 0.50)], 0.20),
    "rv/debris_metal_b": ([("scrap_drop", 2.45, 2.93)], 0.20),
    "rv/debris_metal_c": ([("scrap_drop", 10.81, 11.29)], 0.20),
    "rv/debris_metal_d": ([("scrap_drop", 15.24, 15.72)], 0.20),
    "rv/debris_glass_a": ([("glass_fall", 2.02, 2.20)], 0.06),
    "rv/debris_glass_b": ([("glass_fall", 3.00, 3.24)], 0.08),
    "rv/debris_glass_c": ([("glass_pickup", 0.40, 0.70)], 0.10),
    "monsters/climb_grip_a": ([("hand_metal", 0.0, 0.90)], 0.35),
    "monsters/climb_grip_b": ([("hand_metal_2", 0.10, 1.00)], 0.35),
    "monsters/climb_grip_c": ([("hand_metal_3", 0.13, 1.03)], 0.35),
    "monsters/strike_a": ([("hollow_bang", 0.0, 0.95)], 0.30),
    "monsters/strike_b": ([("metal_bangs", 6.63, 7.45)], 0.30),
    "monsters/strike_c": ([("metal_bangs", 20.18, 21.05)], 0.30),
    "monsters/strike_d": ([("hollow_thunk", 0.0, 0.60)], 0.20),
    "monsters/body_hit_a": ([("power_kick", 0.54, 0.95)], 0.12),
    "monsters/body_hit_b": ([("power_kick", 2.57, 2.98)], 0.12),
    "monsters/body_hit_c": ([("power_kick", 4.56, 4.97)], 0.12),
    "monsters/body_hit_d": ([("power_kick", 8.54, 8.95)], 0.12),
    "monsters/body_hit_e": ([("body_fall_heavy", 0.34, 0.95)], 0.15),
    "player/gore_tear_a": ([("gut_rip", 0.0, 1.30)], 0.30),
    "player/gore_tear_b": ([("gore_tear", 0.10, 0.80)], 0.20),
    "player/gore_tear_c": ([("gore_impact", 0.0, 0.95)], 0.25),
}

# Output "domain/file": (source, start, end, seam seconds, RMS dBFS, processing).
# "flatten" evens slow level swings; "limit" softly rounds off drip transients so
# the rain can reach its loudness without clipping.
LOOPS = {
    "scrapper/grinding": ("shredder_factory", 40.0, 46.3, 0.25, -16.0, "flatten"),
    "player/tinnitus": ("tinnitus_t", 2.0, 3.2, 0.10, -16.0, ""),
    "weather/rain_light": ("rain_light", 4.0, 14.5, 0.50, -24.0, "limit"),
    "weather/rain_heavy": ("rain_heavy", 10.0, 20.5, 0.50, -20.0, "limit"),
}


def read(folder, name, start, end):
    """Frames x channels float array of one stretch of a decoded source."""
    with wave.open(str(folder / f"{name}.wav"), "rb") as track:
        if (track.getframerate(), track.getsampwidth()) != (RATE, 2):
            raise ValueError(f"{name} must be 44.1 kHz PCM16")
        channels = track.getnchannels()
        track.setpos(round(start * RATE))
        data = np.frombuffer(track.readframes(round((end - start) * RATE)), "<i2").astype(float)
    return data.reshape(-1, channels)


def fade(audio, fade_out):
    head = round(FADE_IN * RATE)
    tail = min(round(fade_out * RATE), len(audio))
    audio[:head] *= np.linspace(0.0, 1.0, head)[:, None]
    audio[-tail:] *= np.linspace(1.0, 0.0, tail)[:, None]
    return audio


def layered(folder, layers, fade_out):
    parts = []
    for layer in layers:
        name, start, end = layer[:3]
        offset = layer[3] if len(layer) > 3 else 0.0
        gain = 10 ** ((layer[4] if len(layer) > 4 else 0.0) / 20)
        clip = read(folder, name, start, end)
        clip -= clip.mean(axis=0)
        # Each placed piece fades on its own, so pieces never click at their edges.
        parts.append((round(offset * RATE), fade(clip, 0.03 if len(layers) > 1 else fade_out) * gain))
    length = max(at + len(clip) for at, clip in parts)
    audio = np.zeros((length, 1))
    for at, clip in parts: audio[at:at + len(clip)] += clip
    return fade(audio, fade_out)


def attack_rms(audio):
    """Loudness of the first 200 ms after the attack, where variants compare."""
    mono = np.abs(audio).max(axis=1)
    start = int(np.argmax(mono > 0.5 * mono.max()))
    head = audio[start:start + int(0.2 * RATE)]
    return np.sqrt(np.mean(head ** 2))


def write(path, audio, loop=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames, channels = audio.shape
    with wave.open(str(path), "wb") as clip:
        clip.setparams((channels, 2, RATE, 0, "NONE", "not compressed"))
        clip.writeframes(np.rint(np.clip(audio, -32767, 32767)).astype("<i2").tobytes())
    if loop:
        # The WAV importer reads the forward loop, in frames, from the smpl chunk.
        content = path.read_bytes()
        sample_loop = struct.pack("<15I", 0, 0, round(1e9 / RATE), 60, 0, 0, 0, 1, 0,
                                  0, 0, 0, frames - 1, 0, 0)
        chunk = b"smpl" + struct.pack("<I", len(sample_loop)) + sample_loop
        path.write_bytes(content[:4] + struct.pack("<I", len(content) + len(chunk) - 8) + content[8:] + chunk)


def flatten(audio, window=0.3):
    """Even out slow level swings so the loop has no audible pumping."""
    size = round(window * RATE)
    power = np.convolve((audio ** 2).mean(axis=1), np.ones(size) / size, mode="same")
    envelope = np.sqrt(power)
    floor = 0.25 * np.median(envelope)
    return audio * (np.median(envelope) / np.maximum(envelope, floor))[:, None]


def seamless(audio, seam):
    """Crossfade the tail into the head with equal power; the result loops cleanly."""
    overlap = round(seam * RATE)
    # Trim up to 15 ms off the end so tail and head line up in phase; this keeps
    # steady tones from dipping at the seam.
    head = audio[:overlap].ravel()
    trim = max(range(round(0.015 * RATE)),
               key=lambda k: np.dot(audio[len(audio) - k - overlap:len(audio) - k].ravel(), head))
    audio = audio[:len(audio) - trim]
    body = audio[:-overlap].copy()
    t = np.linspace(0.0, np.pi / 2, overlap)[:, None]
    body[:overlap] = body[:overlap] * np.sin(t) + audio[-overlap:] * np.cos(t)
    return body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    events = {}
    for name, (layers, fade_out) in CUTS.items():
        events.setdefault(name.rsplit("_", 1)[0], []).append((name, layered(args.source, layers, fade_out)))
    for variants in events.values():
        reference = np.mean([attack_rms(audio) for _, audio in variants])
        scaled = [(name, audio * reference / attack_rms(audio)) for name, audio in variants]
        # One gain for the whole event keeps its variants level with each other.
        gain = 32767 * 10 ** (PEAK_DB / 20) / max(np.max(np.abs(audio)) for _, audio in scaled)
        for name, audio in scaled:
            write(args.output / f"{name}.wav", audio * gain)
    ceiling = 10 ** (PEAK_DB / 20)
    for name, (source, start, end, seam, rms_db, processing) in LOOPS.items():
        audio = read(args.source, source, start, end) / 32768
        audio -= audio.mean(axis=0)
        if processing == "flatten": audio = flatten(audio)
        audio = seamless(audio, seam)
        audio *= 10 ** (rms_db / 20) / np.sqrt(np.mean(audio ** 2))
        if processing == "limit": audio = np.tanh(audio / ceiling) * ceiling
        audio *= min(1.0, ceiling / np.max(np.abs(audio)))
        write(args.output / f"{name}.wav", audio * 32767, loop=True)


if __name__ == "__main__":
    main()
