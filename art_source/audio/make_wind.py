"""Cut the weather wind beds, treetop rushes, RV hull whistle and panel rattles.

Inputs are the Freesound high-quality previews listed in assets/audio/weather/README.md
and assets/audio/rv/README.md, saved as <SOURCES key>.mp3 in one folder. They are
read directly (needs the soundfile package, libsndfile 1.1 or later) and resampled
to 44.1 kHz.

Every wind sound has rumble below about 50 Hz (mic buffeting) cut, a gentle
low-pass that sets its brightness and a steep cut above that. The beds, whistle
and rattles are dark on purpose, cut steeply above about 4 kHz so no hiss
reaches the game. The treetop rushes keep the leaf noise up to about 10 kHz
(cut as dark as the beds they turn into a muddy thump) and lose more of the low
end. The beds
are flattened, since the game adds the gusts, made stereo with a fixed width,
looped with an equal-power crossfade and written as Ogg Vorbis. Their loop flag
is set in the Godot import file.

    python art_source/audio/make_wind.py <preview folder> assets/audio
    python art_source/audio/make_wind.py <preview folder> <folder> --set B
    python art_source/audio/make_wind.py <preview folder> <folder> --rushes

--set writes one of the candidate bed sets in BED_SETS instead of the chosen
beds plus the one-shots, and --rushes writes the treetop rushes of every set in
RUSH_SETS into rushes-<set> folders, for comparing in the ambience playground.
"""

import argparse
import struct
import wave
from pathlib import Path

import numpy as np
import soundfile

RATE = 44100
PEAK_DB = -1.0

# Freesound id of each preview, for reproducing the source folder.
SOURCES = {
    "trees_far": 259968, "arctic": 117136, "hurricane": 735350,
    "wind2": 30444, "strong_jpn": 97397, "polar": 521820,
    "winter_wind_01c": 117513, "gale": 181935, "howling_amb": 405601,
    "trees": 150174, "frame_whistle": 396533, "window_whistle": 69512,
    "metal_sheet": 631929, "tree_gusts": 714265, "forest_strong": 403051,
}

# Candidate beds per set: tier -> (source, start seconds). Each bed is BED_LENGTH
# long; the start is the steadiest stretch of the recording without mic thumps.
BED_SETS = {
    "A": {"breeze": ("trees_far", 23.0), "strong": ("arctic", 9.0), "gale": ("hurricane", 18.0)},
    "B": {"breeze": ("wind2", 46.0), "strong": ("strong_jpn", 6.0), "gale": ("polar", 13.0)},
    "C": {"breeze": ("winter_wind_01c", 186.0), "strong": ("gale", 6.0), "gale": ("howling_amb", 24.0)},
}
# The set each shipped bed comes from, picked by listening in the ambience playground.
CHOSEN = {"breeze": "A", "strong": "B", "gale": "B"}
BED_LENGTH = 24.0
BED_SEAM = 2.0
BED_RMS_DB = -24.0
# Low-pass corner per tier: a breeze is darkest, a gale lets a little more through.
BED_CUTOFF = {"breeze": 650.0, "strong": 1000.0, "gale": 1500.0}
# Left-right correlation of every bed; mono sources borrow a later stretch for the right side.
BED_CORRELATION = 0.3
MONO_OFFSET = 7.0

# Steep cut above which nothing of the beds, whistle and rattles reaches the game.
DARK_CUT = 4000.0
# Treetop rush candidates: name -> (source, [(start, end) seconds of one gust
# each]). Each window holds one swell and no branch cracks or mic clicks.
RUSH_SETS = {
    "gusts": ("tree_gusts", [(5.0, 15.0), (16.0, 24.0), (29.0, 39.0), (52.0, 62.0), (83.0, 91.0)]),
    "forest": ("forest_strong", [(6.0, 16.0), (53.0, 63.0), (73.0, 81.0)]),
    "trees": ("trees", [(13.0, 17.0), (19.0, 26.0), (53.0, 61.0), (101.0, 110.0)]),
}
# The set the shipped rushes come from, picked by listening in the ambience playground.
CHOSEN_RUSHES = "gusts"
# Rushes keep the leaf noise: (gentle low-pass corner, steep cut) in Hz, and a
# higher rumble cut than the beds, since they pass overhead.
RUSH_TONE = (4500.0, 10000.0)
RUSH_RUMBLE = 120.0
RUSH_FADE = (2.0, 3.0)

# One-shots: output -> (source, start, end, (cutoff, steep cut, rumble cut) Hz,
# fade in, fade out). Files sharing the part before the last underscore form one
# event and are loudness matched.
SHOTS = {
    # Short bursts from the dense shaking in the middle of the sheet recording.
    "rv/panel_rattle_a": ("metal_sheet", 30.0, 30.8, (3500.0, DARK_CUT, 50.0), 0.003, 0.25),
    "rv/panel_rattle_b": ("metal_sheet", 32.3, 33.1, (3500.0, DARK_CUT, 50.0), 0.003, 0.25),
    "rv/panel_rattle_c": ("metal_sheet", 34.6, 35.4, (3500.0, DARK_CUT, 50.0), 0.003, 0.25),
    "rv/panel_rattle_d": ("metal_sheet", 37.1, 37.9, (3500.0, DARK_CUT, 50.0), 0.003, 0.25),
}

# Mono loop: output -> (source, start, end, cutoff Hz, seam, RMS dBFS).
LOOPS = {
    "rv/wind_whistle": ("frame_whistle", 21.0, 32.0, 2400.0, 1.0, -22.0),
}


def read(folder, name, start, end):
    """Frames x channels float array at RATE of one stretch of a preview."""
    with soundfile.SoundFile(str(folder / f"{name}.mp3")) as track:
        rate = track.samplerate
        track.seek(round(start * rate))
        audio = track.read(round((end - start) * rate), always_2d=True)
    if rate != RATE:
        frames = round(len(audio) * RATE / rate)
        spectrum = np.fft.rfft(audio, axis=0)
        keep = frames // 2 + 1
        resized = np.zeros((keep, audio.shape[1]), complex)
        resized[:min(keep, len(spectrum))] = spectrum[:keep]
        audio = np.fft.irfft(resized, n=frames, axis=0) * frames / len(audio)
    return audio - audio.mean(axis=0)


def equalize(audio, gain_at):
    """Zero-phase gain curve over frequency."""
    spectrum = np.fft.rfft(audio, axis=0)
    spectrum *= gain_at(np.fft.rfftfreq(len(audio), 1.0 / RATE))[:, None]
    return np.fft.irfft(spectrum, n=len(audio), axis=0)


def darken(audio, cutoff, steep=DARK_CUT, low=50.0):
    """Cut rumble below low and everything above steep, and roll off gently above cutoff."""
    def gain(f):
        f = np.maximum(f, 1.0)
        rumble = 1.0 / np.sqrt(1.0 + (low / f) ** 8)
        soft = 1.0 / np.sqrt(1.0 + (f / cutoff) ** 4)
        hiss = 1.0 / np.sqrt(1.0 + (f / steep) ** 16)
        return rumble * soft * hiss
    return equalize(audio, gain)


def flatten(audio, window=1.5, depth=0.8):
    """Even out most of the recorded swells; the game adds its own gusts."""
    size = round(window * RATE)
    # Centred running mean of the power, from a cumulative sum.
    padded = np.pad((audio ** 2).mean(axis=1), (size // 2, size - size // 2), mode="edge")
    total = np.concatenate([[0.0], np.cumsum(padded)])
    envelope = np.sqrt(np.maximum((total[size:] - total[:-size])[:len(audio)] / size, 0.0))
    reference = np.median(envelope)
    return audio * ((reference / np.maximum(envelope, 0.25 * reference)) ** depth)[:, None]


def widen(audio):
    """Fix the left-right correlation at BED_CORRELATION through the side level."""
    mid = (audio[:, 0] + audio[:, 1]) * 0.5
    side = (audio[:, 0] - audio[:, 1]) * 0.5
    m2, s2 = np.mean(mid ** 2), np.mean(side ** 2) + 1e-20
    k = np.sqrt(m2 * (1.0 - BED_CORRELATION) / (s2 * (1.0 + BED_CORRELATION)))
    return np.stack([mid + k * side, mid - k * side], axis=1)


def seamless(audio, seam):
    """Crossfade the tail into the head with equal power; the result loops cleanly."""
    overlap = round(seam * RATE)
    body = audio[:-overlap].copy()
    t = np.linspace(0.0, np.pi / 2, overlap)[:, None]
    body[:overlap] = body[:overlap] * np.sin(t) + audio[-overlap:] * np.cos(t)
    return body


def fade(audio, fade_in, fade_out):
    head, tail = round(fade_in * RATE), round(fade_out * RATE)
    # Rushes swell in and out; a raised cosine keeps the ends soft.
    audio[:head] *= (0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, head)))[:, None]
    audio[-tail:] *= (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, tail)))[:, None]
    return audio


def write_wav(path, audio, loop=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames, channels = audio.shape
    with wave.open(str(path), "wb") as clip:
        clip.setparams((channels, 2, RATE, 0, "NONE", "not compressed"))
        clip.writeframes(np.rint(np.clip(audio * 32767, -32767, 32767)).astype("<i2").tobytes())
    if loop:
        # The WAV importer reads the forward loop, in frames, from the smpl chunk.
        content = path.read_bytes()
        sample_loop = struct.pack("<15I", 0, 0, round(1e9 / RATE), 60, 0, 0, 0, 1, 0,
                                  0, 0, 0, frames - 1, 0, 0)
        chunk = b"smpl" + struct.pack("<I", len(sample_loop)) + sample_loop
        path.write_bytes(content[:4] + struct.pack("<I", len(content) + len(chunk) - 8) + content[8:] + chunk)


def write_ogg(path, audio):
    path.parent.mkdir(parents=True, exist_ok=True)
    audio = np.ascontiguousarray(np.clip(audio, -1.0, 1.0))
    with soundfile.SoundFile(str(path), "w", RATE, audio.shape[1], format="OGG", subtype="VORBIS",
                             compression_level=0.3) as out:
        # libsndfile's Vorbis writer crashes on very large single writes.
        for at in range(0, len(audio), 4096): out.write(audio[at:at + 4096])


def bed(folder, tier, source, start):
    length = BED_LENGTH + BED_SEAM
    audio = read(folder, source, start, start + length)
    if audio.shape[1] == 1 or np.corrcoef(audio[:, 0], audio[:, -1])[0, 1] > 0.9:
        right = read(folder, source, start + MONO_OFFSET, start + MONO_OFFSET + length).mean(axis=1)
        if len(right) < len(audio):
            # Too close to the end: borrow an earlier stretch instead.
            earlier = max(0.0, start - MONO_OFFSET)
            right = read(folder, source, earlier, earlier + length).mean(axis=1)
        frames = min(len(audio), len(right))
        audio = np.stack([audio[:frames].mean(axis=1), right[:frames]], axis=1)
    audio = widen(flatten(darken(audio, BED_CUTOFF[tier])))
    audio = seamless(audio, BED_SEAM)
    audio *= 10 ** (BED_RMS_DB / 20) / np.sqrt(np.mean(audio ** 2))
    return audio * min(1.0, 10 ** (PEAK_DB / 20) / np.max(np.abs(audio)))


def rush_shots(name, prefix):
    """SHOTS entries for the treetop rushes of one RUSH_SETS candidate."""
    source, windows = RUSH_SETS[name]
    return {f"{prefix}tree_rush_{chr(97 + index)}": (source, start, end, RUSH_TONE + (RUSH_RUMBLE,)) + RUSH_FADE
            for index, (start, end) in enumerate(windows)}


def write_shots(folder, output, shots):
    events = {}
    for name, (source, start, end, (cutoff, steep, low), fade_in, fade_out) in shots.items():
        audio = darken(read(folder, source, start, end).mean(axis=1, keepdims=True), cutoff, steep, low)
        events.setdefault(name.rsplit("_", 1)[0], []).append((name, fade(audio, fade_in, fade_out)))
    for variants in events.values():
        # Match variants by overall loudness, then one gain sets the loudest peak.
        reference = np.mean([np.sqrt(np.mean(audio ** 2)) for _, audio in variants])
        scaled = [(name, audio * reference / np.sqrt(np.mean(audio ** 2))) for name, audio in variants]
        gain = 10 ** (PEAK_DB / 20) / max(np.max(np.abs(audio)) for _, audio in scaled)
        for name, audio in scaled: write_wav(output / f"{name}.wav", audio * gain)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--set", choices=sorted(BED_SETS))
    parser.add_argument("--rushes", action="store_true")
    args = parser.parse_args()
    if args.rushes:
        for name in RUSH_SETS:
            write_shots(args.source, args.output / f"rushes-{name}", rush_shots(name, ""))
        return
    if args.set:
        for tier, (source, start) in BED_SETS[args.set].items():
            write_ogg(args.output / f"wind_{tier}.ogg", bed(args.source, tier, source, start))
        return
    for tier, chosen_set in CHOSEN.items():
        source, start = BED_SETS[chosen_set][tier]
        write_ogg(args.output / f"weather/wind_{tier}.ogg", bed(args.source, tier, source, start))
    write_shots(args.source, args.output, {**rush_shots(CHOSEN_RUSHES, "weather/"), **SHOTS})
    for name, (source, start, end, cutoff, seam, rms_db) in LOOPS.items():
        audio = flatten(darken(read(args.source, source, start, end).mean(axis=1, keepdims=True), cutoff), 0.5, 1.0)
        audio = seamless(audio, seam)
        audio *= 10 ** (rms_db / 20) / np.sqrt(np.mean(audio ** 2))
        write_wav(args.output / f"{name}.wav", audio * min(1.0, 10 ** (PEAK_DB / 20) / np.max(np.abs(audio))), loop=True)


if __name__ == "__main__":
    main()
