"""Cut the chosen render into a seamless game loop for the Slender Speaker head loudspeaker.

Für Elise at 64 BPM (quarter note), 3/8. The render starts at bar 1; the pickup E is at QN 1.0 and the
final A at QN 45.0. Cutting [QN 1, QN 46) puts the next pickup exactly one beat after the last A, like the
score's repeat. The synth has no reverb; the held final A is faded out over the last 15 ms.

usage: python make_loop.py <in.wav> <out.wav> [gain_db]
Output: mono 16-bit PCM at the input sample rate.
"""
import sys
import wave

import numpy as np

BPM = 64.0
START_QN, END_QN = 1.0, 46.0


def read_wav(path):
    with wave.open(path, "rb") as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        x = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        x = np.where(x >= 1 << 23, x - (1 << 24), x) / float(1 << 23)
    elif width == 2:
        x = np.frombuffer(raw, dtype="<i2") / 32768.0
    else:
        raise SystemExit(f"unsupported sample width {width}")
    return x.reshape(-1, ch), rate


def main():
    src, dst = sys.argv[1], sys.argv[2]
    gain_db = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    x, rate = read_wav(src)
    mono = x.mean(axis=1)
    spq = rate * 60.0 / BPM
    # Start 2 ms before the pickup so both loop edges fall in silence; keep the exact 45 QN length.
    a = int(round(START_QN * spq - 0.002 * rate))
    b = a + int(round((END_QN - START_QN) * spq))
    loop = mono[a:b] * (10 ** (gain_db / 20.0))
    # The final A is held (RH 1.15 QN, LH 0.69 QN) past QN 46, into the next pickup. In the loop it is
    # released just before the seam: 15 ms cosine fade so the cut does not click.
    fade = int(round(0.015 * rate))
    loop[-fade:] *= 0.5 * (1.0 + np.cos(np.linspace(0.0, np.pi, fade)))
    peak = float(np.max(np.abs(loop)))
    if peak >= 1.0:
        raise SystemExit(f"gain would clip: peak {20 * np.log10(peak):.2f} dBFS")
    rms = float(np.sqrt(np.mean(loop ** 2)))
    edge = float(max(np.max(np.abs(loop[:32])), np.max(np.abs(loop[-32:]))))
    with wave.open(dst, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((np.round(loop * 32767.0)).astype("<i2").tobytes())
    print(f"rate {rate} Hz, frames {b - a}, seconds {(b - a) / rate:.4f}")
    print(f"peak {20 * np.log10(peak):.2f} dBFS, rms {20 * np.log10(rms):.2f} dBFS, seam edge max {edge:.6f}")
    print(f"stereo L-R max diff {float(np.max(np.abs(x[:, 0] - x[:, 1]))) if x.shape[1] > 1 else 0.0:.8f}")


if __name__ == "__main__":
    main()
