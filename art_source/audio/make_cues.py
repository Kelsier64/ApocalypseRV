"""Cut the pistol, panel damage, monster, player, footstep, scrapper, rain and ambience sounds.

Inputs are the Freesound previews listed in the assets/audio/<domain>/README.md
files, decoded to 44.1 kHz PCM16 WAV and named after the SOURCES keys below:
mono, except the rain and room-tone recordings, which stay stereo. Variants of
one event are matched in loudness after their attack, then the loudest is set to
the peak target. Loops are crossfaded at the seam; WAV loops carry a forward loop
in a smpl chunk, and the room tones are written as Ogg Vorbis (needs the
soundfile package), whose loop flag is set in the Godot import file.

    python art_source/audio/make_cues.py <decoded folder> assets/audio [--only raker/ ...]

--only limits the run to outputs whose name starts with one of the prefixes, so
a folder holding only those sources is enough.
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
    "ghost_whispers": 175944, "ghost_breath": 338344, "creepy_breathing": 369294,
    "monster_shriek": 442564, "monster_scream": 427412, "barefoot_run": 788636,
    "heavy_steps": 383724, "growl_large": 699932, "growl_9": 389653,
    "predator_clicks": 235529, "alien_clicks": 512472, "snarl_3": 204610, "snarl_4": 204611,
    "goblin_snarl": 442815, "metal_creak": 119468, "oil_drum": 506274,
    "bucket_slosh": 388014, "fuse": 140715, "drum_footsteps": 487076,
    "step_asphalt": 637556, "step_gravel": 521588, "step_dirt": 682127, "step_grass": 521587,
    "step_wood": 119914, "step_tin": 466618, "step_concrete": 459964,
    "room_small": 451064, "room_hall": 451614, "drips": 262641,
    "crows_cornwall": 144553, "crow_call": 813114, "tree_creaks": 726217, "branch_snap": 452109, "sign_creak": 759692, "metal_creaks": 625616, "cricket_single": 753272,
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
    # Player footsteps, one shod step per cut: RV cabin floor is wood, RV roof is tin sheet.
    "player/step_asphalt_a": ([("step_asphalt", 3.09, 3.49)], 0.10),
    "player/step_asphalt_b": ([("step_asphalt", 4.29, 4.69)], 0.10),
    "player/step_asphalt_c": ([("step_asphalt", 5.45, 5.85)], 0.10),
    "player/step_asphalt_d": ([("step_asphalt", 6.55, 6.95)], 0.10),
    "player/step_asphalt_e": ([("step_asphalt", 7.05, 7.45)], 0.10),
    "player/step_asphalt_f": ([("step_asphalt", 7.59, 7.99)], 0.10),
    "player/step_gravel_a": ([("step_gravel", 0.07, 0.52)], 0.10),
    "player/step_gravel_b": ([("step_gravel", 0.83, 1.28)], 0.10),
    "player/step_gravel_c": ([("step_gravel", 1.53, 1.98)], 0.10),
    "player/step_gravel_d": ([("step_gravel", 2.19, 2.64)], 0.10),
    "player/step_dirt_a": ([("step_dirt", 0.09, 0.45)], 0.10),
    "player/step_dirt_b": ([("step_dirt", 0.65, 1.01)], 0.10),
    "player/step_dirt_c": ([("step_dirt", 1.07, 1.43)], 0.10),
    "player/step_dirt_d": ([("step_dirt", 1.59, 1.95)], 0.10),
    "player/step_dirt_e": ([("step_dirt", 2.05, 2.41)], 0.10),
    "player/step_dirt_f": ([("step_dirt", 3.09, 3.45)], 0.10),
    "player/step_grass_a": ([("step_grass", 0.07, 0.47)], 0.10),
    "player/step_grass_b": ([("step_grass", 0.77, 1.17)], 0.10),
    "player/step_grass_c": ([("step_grass", 1.47, 1.87)], 0.10),
    "player/step_grass_d": ([("step_grass", 3.03, 3.43)], 0.10),
    "player/step_grass_e": ([("step_grass", 3.77, 4.17)], 0.10),
    "player/step_wood_a": ([("step_wood", 1.13, 1.58)], 0.10),
    "player/step_wood_b": ([("step_wood", 1.71, 2.16)], 0.10),
    "player/step_wood_c": ([("step_wood", 2.27, 2.72)], 0.10),
    "player/step_wood_d": ([("step_wood", 2.81, 3.26)], 0.10),
    "player/step_wood_e": ([("step_wood", 3.91, 4.36)], 0.10),
    "player/step_metal_a": ([("step_tin", 5.85, 6.35)], 0.10),
    "player/step_metal_b": ([("step_tin", 10.09, 10.59)], 0.10),
    "player/step_metal_c": ([("step_tin", 17.51, 18.01)], 0.10),
    "player/step_metal_d": ([("step_tin", 18.09, 18.59)], 0.10),
    "player/step_metal_e": ([("step_tin", 18.71, 19.21)], 0.10),
    "player/step_concrete_a": ([("step_concrete", 0.00, 0.32)], 0.10),
    "player/step_concrete_b": ([("step_concrete", 8.71, 9.03)], 0.10),
    "player/step_concrete_c": ([("step_concrete", 14.99, 15.31)], 0.10),
    "player/step_concrete_d": ([("step_concrete", 15.95, 16.27)], 0.10),
    "player/step_concrete_e": ([("step_concrete", 18.15, 18.47)], 0.10),
    "player/gore_tear_a": ([("gut_rip", 0.0, 1.30)], 0.30),
    "player/gore_tear_b": ([("gore_tear", 0.10, 0.80)], 0.20),
    "player/gore_tear_c": ([("gore_impact", 0.0, 0.95)], 0.25),
    # White apparition: a soft swelling breath when it appears.
    "apparitions/white_appear_a": ([("ghost_breath", 1.0, 5.5)], 0.80),
    # Black apparition: the shriek when it rages, and bare running steps.
    "apparitions/black_shriek_a": ([("monster_shriek", 0.0, 3.30)], 0.30),
    "apparitions/black_shriek_b": ([("monster_scream", 0.0, 2.00)], 0.30),
    "apparitions/black_step_a": ([("barefoot_run", 0.45, 0.68)], 0.08),
    "apparitions/black_step_b": ([("barefoot_run", 0.74, 0.97)], 0.08),
    "apparitions/black_step_c": ([("barefoot_run", 1.02, 1.25)], 0.08),
    "apparitions/black_step_d": ([("barefoot_run", 1.30, 1.53)], 0.08),
    "apparitions/black_step_e": ([("barefoot_run", 1.64, 1.87)], 0.08),
    "apparitions/black_step_f": ([("barefoot_run", 2.16, 2.39)], 0.08),
    # Raker: heavy steps, idle growls and clicks, and the two attack tells. The
    # tells start on the attack so they fit the 0.72 s sweep and 0.24 s reach.
    "raker/step_a": ([("heavy_steps", 2.12, 2.42)], 0.12),
    "raker/step_b": ([("heavy_steps", 3.40, 3.70)], 0.12),
    "raker/step_c": ([("heavy_steps", 4.04, 4.34)], 0.12),
    "raker/step_d": ([("heavy_steps", 6.57, 6.87)], 0.12),
    "raker/step_e": ([("heavy_steps", 7.84, 8.14)], 0.12),
    "raker/step_f": ([("heavy_steps", 9.66, 9.96)], 0.12),
    "raker/growl_a": ([("growl_large", 0.0, 1.45)], 0.20),
    "raker/growl_b": ([("growl_9", 0.05, 0.95)], 0.15),
    "raker/click_a": ([("predator_clicks", 0.0, 1.75)], 0.20),
    "raker/click_b": ([("predator_clicks", 3.40, 5.30)], 0.25),
    "raker/click_c": ([("alien_clicks", 0.0, 0.98)], 0.15),
    "raker/windup_a": ([("snarl_4", 0.28, 1.15)], 0.25),
    "raker/windup_b": ([("snarl_3", 0.45, 1.35)], 0.25),
    "raker/lunge_a": ([("goblin_snarl", 0.0, 0.45)], 0.10),
    "raker/lunge_b": ([("goblin_snarl", 0.95, 1.40)], 0.10),
    # Barrel man: a drum hit under a creak when it wakes, then knocks with slosh.
    "barrel_man/wake_a": ([("oil_drum", 2.80, 3.70, 0.0), ("metal_creak", 0.0, 1.60, 0.12, -4.0)], 0.30),
    "barrel_man/wake_b": ([("oil_drum", 11.91, 12.75, 0.0), ("metal_creak", 1.50, 3.10, 0.10, -4.0)], 0.30),
    "barrel_man/step_a": ([("oil_drum", 5.12, 5.47, 0.0), ("bucket_slosh", 1.25, 1.70, 0.02, -3.0)], 0.15),
    "barrel_man/step_b": ([("oil_drum", 10.93, 11.25, 0.0), ("bucket_slosh", 4.00, 4.45, 0.02, -3.0)], 0.15),
    "barrel_man/step_c": ([("oil_drum", 21.41, 21.76, 0.0), ("bucket_slosh", 6.75, 7.20, 0.02, -3.0)], 0.15),
    "barrel_man/step_d": ([("oil_drum", 14.37, 14.72, 0.0), ("bucket_slosh", 10.50, 10.95, 0.02, -3.0)], 0.15),
    # Slender Speaker: deep drum footfalls, each left to ring.
    "slender_speaker/step_a": ([("drum_footsteps", 0.25, 1.35)], 0.50),
    "slender_speaker/step_b": ([("drum_footsteps", 2.60, 3.70)], 0.50),
    "slender_speaker/step_c": ([("drum_footsteps", 5.25, 6.35)], 0.50),
    "slender_speaker/step_d": ([("drum_footsteps", 9.20, 10.30)], 0.50),
    "slender_speaker/step_e": ([("drum_footsteps", 13.18, 14.28)], 0.50),
    # Sparse ambience, outdoors: one caw, creak, snap or chirp burst each.
    # The quieter Cornwall calls sit over other birds and are left out.
    "ambience/crow_a": ([("crow_call", 0.00, 0.84)], 0.20),
    "ambience/crow_b": ([("crows_cornwall", 0.00, 1.60)], 0.40),
    "ambience/crow_c": ([("crows_cornwall", 51.99, 53.60)], 0.40),
    "ambience/tree_creak_a": ([("tree_creaks", 4.93, 6.50)], 0.40),
    "ambience/tree_creak_b": ([("tree_creaks", 9.87, 12.80)], 0.60),
    "ambience/tree_creak_c": ([("tree_creaks", 16.19, 17.40)], 0.40),
    "ambience/tree_creak_d": ([("tree_creaks", 21.47, 23.30)], 0.40),
    "ambience/branch_snap_a": ([("branch_snap", 0.45, 1.40)], 0.30),
    "ambience/branch_snap_b": ([("branch_snap", 1.41, 2.70)], 0.40),
    "ambience/metal_creak_a": ([("sign_creak", 0.11, 1.50)], 0.30),
    "ambience/metal_creak_b": ([("sign_creak", 2.41, 3.40)], 0.30),
    "ambience/metal_creak_c": ([("sign_creak", 6.15, 7.90)], 0.30),
    "ambience/metal_creak_d": ([("sign_creak", 10.15, 11.20)], 0.30),
    "ambience/cricket_a": ([("cricket_single", 0.00, 1.85)], 0.30),
    "ambience/cricket_b": ([("cricket_single", 4.23, 6.10)], 0.30),
    "ambience/cricket_c": ([("cricket_single", 9.13, 11.00)], 0.30),
    # Sparse ambience, interiors: a drip or a metal contraction creak.
    "ambience/drip_a": ([("drips", 14.97, 15.50)], 0.25),
    "ambience/drip_b": ([("drips", 25.75, 26.30)], 0.25),
    "ambience/drip_c": ([("drips", 41.81, 42.40)], 0.25),
    "ambience/drip_d": ([("drips", 90.31, 90.85)], 0.25),
    "ambience/drip_e": ([("drips", 95.90, 96.45)], 0.25),
    "ambience/drip_f": ([("drips", 98.39, 98.95)], 0.25),
    "ambience/room_creak_a": ([("metal_creaks", 0.85, 3.20)], 0.50),
    "ambience/room_creak_b": ([("metal_creaks", 6.17, 7.80)], 0.40),
}

# Output "domain/file": (source, start, end, seam seconds, RMS dBFS, processing).
# Processing is a space-separated list: "flatten" evens slow level swings; "limit"
# softly rounds off drip transients so the loop can reach its loudness without
# clipping; "rumble" removes rumble below 60 Hz before levelling; "low" keeps
# only what lies below about 400 Hz, so a room tone is a felt hum with no hiss;
# "ogg" writes Ogg Vorbis.
LOOPS = {
    "scrapper/grinding": ("shredder_factory", 40.0, 46.3, 0.25, -16.0, "flatten"),
    "player/tinnitus": ("tinnitus_t", 2.0, 3.2, 0.10, -16.0, ""),
    "weather/rain_light": ("rain_light", 4.0, 14.5, 0.50, -24.0, "limit"),
    "weather/rain_heavy": ("rain_heavy", 10.0, 20.5, 0.50, -20.0, "limit"),
    "apparitions/white_presence": ("ghost_whispers", 3.0, 21.0, 0.50, -22.0, "flatten"),
    "apparitions/black_breathing": ("creepy_breathing", 2.9, 22.0, 0.50, -24.0, ""),
    "barrel_man/fuse": ("fuse", 0.2, 3.5, 0.30, -18.0, "flatten"),
    "ambience/room_small": ("room_small", 17.0, 37.0, 1.5, -24.0, "rumble low ogg"),
    "ambience/room_hall": ("room_hall", 155.0, 175.0, 1.5, -24.0, "rumble low ogg"),
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


def write_ogg(path, audio):
    import soundfile
    path.parent.mkdir(parents=True, exist_ok=True)
    audio = np.ascontiguousarray(np.clip(audio, -1.0, 1.0))
    with soundfile.SoundFile(str(path), "w", RATE, audio.shape[1], format="OGG", subtype="VORBIS",
                             compression_level=0.3) as out:
        # libsndfile's Vorbis writer crashes on very large single writes.
        for at in range(0, len(audio), 4096): out.write(audio[at:at + 4096])


def equalize(audio, gain_at):
    """Zero-phase gain curve over frequency; the loop seam hides the edges."""
    spectrum = np.fft.rfft(audio, axis=0)
    spectrum *= gain_at(np.fft.rfftfreq(len(audio), 1.0 / RATE))[:, None]
    return np.fft.irfft(spectrum, n=len(audio), axis=0)


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
    parser.add_argument("--only", nargs="+", default=[""])
    args = parser.parse_args()
    wanted = lambda name: any(name.startswith(prefix) for prefix in args.only)
    events = {}
    for name, (layers, fade_out) in CUTS.items():
        if not wanted(name): continue
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
        if not wanted(name): continue
        steps = processing.split()
        audio = read(args.source, source, start, end) / 32768
        audio -= audio.mean(axis=0)
        if "rumble" in steps: audio = equalize(audio, lambda f: 1.0 / np.sqrt(1.0 + (60.0 / np.maximum(f, 1.0)) ** 8))
        if "low" in steps: audio = equalize(audio, lambda f: 1.0 / np.sqrt(1.0 + (f / 400.0) ** 8))
        if "flatten" in steps: audio = flatten(audio)
        audio = seamless(audio, seam)
        audio *= 10 ** (rms_db / 20) / np.sqrt(np.mean(audio ** 2))
        if "limit" in steps: audio = np.tanh(audio / ceiling) * ceiling
        audio *= min(1.0, ceiling / np.max(np.abs(audio)))
        if "ogg" in steps: write_ogg(args.output / f"{name}.ogg", audio)
        else: write(args.output / f"{name}.wav", audio * 32767, loop=True)


if __name__ == "__main__":
    main()
