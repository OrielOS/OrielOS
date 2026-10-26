# SPDX-FileCopyrightText: 2026 OrielOS contributors
# SPDX-License-Identifier: CC-BY-SA-4.0
"""Makes OrielOS's sound theme: soft glass-like chimes in D major, synthesised from sine waves.

Writes artwork/sounds/orielos/stereo/<name>.oga, one file per sound below. Needs Python 3 and an
Ogg Vorbis encoder: oggenc, or gst-launch-1.0 with GStreamer's vorbis plugin (OrielOS has it).

    python3 artwork/sounds/src/generate.py
"""

import math
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 48000

# Equal temperament, A4 = 440 Hz.
NOTES = {
    "F#4": 369.99, "A4": 440.00, "B4": 493.88, "C#5": 554.37, "D5": 587.33, "E5": 659.26,
    "F#5": 739.99, "G5": 783.99, "A5": 880.00, "B5": 987.77, "C#6": 1108.73, "D6": 1174.66,
}

# The tone of every note: (frequency ratio, level). A glassy chime: the fundamental, a quiet octave
# and two faint inharmonic partials that give the strike its shine and die away first.
PARTIALS = ((1.0, 1.0), (2.0, 0.22), (2.76, 0.06), (5.4, 0.025))


def note(name, start, level=1.0, decay=0.35):
    """One struck note: (pitch, start in seconds, level, time for the level to fall to 1/e)."""
    return (NOTES[name], start, level, decay)


# Each sound: (peak level in dBFS, notes). Plasma asks for these names (see the freedesktop.org
# sound naming specification); anything else comes from Ocean, which this theme inherits.
SOUNDS = {
    # Signing in: a rising D major arpeggio. The sound theme's demo plays the same.
    "desktop-login": (-4.0, [note("D5", 0.0, 0.8, 0.5), note("F#5", 0.12, 0.75, 0.5), note("A5", 0.24, 0.8, 0.6),
                             note("D6", 0.38, 0.7, 0.65)]),
    "desktop-logout": (-5.0, [note("A5", 0.0, 0.8, 0.45), note("F#5", 0.13, 0.75, 0.45), note("D5", 0.26, 0.8, 0.6)]),
    "message-new-instant": (-6.0, [note("A5", 0.0, 0.8, 0.25), note("D6", 0.09, 0.9, 0.45)]),
    "dialog-information": (-7.0, [note("A5", 0.0, 1.0, 0.4)]),
    "dialog-question": (-7.0, [note("E5", 0.0, 0.85, 0.25), note("A5", 0.1, 0.9, 0.4)]),
    "dialog-warning": (-6.0, [note("E5", 0.0, 0.9, 0.18), note("E5", 0.16, 0.9, 0.35)]),
    "dialog-warning-auth": (-7.0, [note("F#5", 0.0, 0.85, 0.2), note("D5", 0.11, 0.9, 0.4)]),
    "dialog-error": (-6.0, [note("C#5", 0.0, 0.9, 0.2), note("A4", 0.12, 1.0, 0.45)]),
    "dialog-error-serious": (-5.0, [note("C#5", 0.0, 0.9, 0.2), note("A4", 0.12, 1.0, 0.45)]),
    "dialog-error-critical": (-4.0, [note("E5", 0.0, 0.85, 0.18), note("C#5", 0.12, 0.9, 0.2),
                                     note("A4", 0.24, 1.0, 0.6)]),
    # The window system's bell, which Plasma rings most often: one short, quiet tap.
    "bell-window-system": (-10.0, [note("A5", 0.0, 1.0, 0.12)]),
    "bell": (-10.0, [note("A5", 0.0, 1.0, 0.12)]),
    # The volume keys' feedback: a very short tick, so pressing them repeatedly stays pleasant.
    "audio-volume-change": (-9.0, [note("D6", 0.0, 1.0, 0.05)]),
    "device-added": (-6.0, [note("D5", 0.0, 0.85, 0.2), note("A5", 0.09, 0.9, 0.4)]),
    "device-removed": (-6.0, [note("A5", 0.0, 0.85, 0.2), note("D5", 0.09, 0.9, 0.4)]),
    "power-plug": (-7.0, [note("E5", 0.0, 0.85, 0.18), note("B5", 0.08, 0.9, 0.35)]),
    "power-unplug": (-7.0, [note("B5", 0.0, 0.85, 0.18), note("E5", 0.08, 0.9, 0.35)]),
    "battery-low": (-5.0, [note("F#5", 0.0, 0.9, 0.2), note("D5", 0.14, 0.9, 0.2), note("F#5", 0.42, 0.9, 0.2),
                           note("D5", 0.56, 0.9, 0.35)]),
    "battery-caution": (-4.0, [note("F#5", 0.0, 0.9, 0.18), note("D5", 0.12, 0.9, 0.18), note("B4", 0.24, 1.0, 0.45)]),
    "battery-full": (-7.0, [note("D5", 0.0, 0.8, 0.25), note("F#5", 0.08, 0.8, 0.25), note("A5", 0.16, 0.85, 0.45)]),
    "completion-success": (-6.0, [note("D5", 0.0, 0.85, 0.22), note("F#5", 0.1, 0.85, 0.22), note("A5", 0.2, 0.9, 0.5)]),
    "completion-fail": (-6.0, [note("A4", 0.0, 0.9, 0.22), note("F#4", 0.12, 1.0, 0.5)]),
    "outcome-success": (-6.0, [note("F#5", 0.0, 0.85, 0.22), note("A5", 0.1, 0.9, 0.45)]),
    "outcome-failure": (-6.0, [note("C#5", 0.0, 0.9, 0.22), note("A4", 0.12, 1.0, 0.45)]),
    "trash-empty": (-8.0, [note("D6", 0.0, 0.6, 0.12), note("A5", 0.05, 0.6, 0.12), note("F#5", 0.1, 0.6, 0.12),
                           note("D5", 0.15, 0.7, 0.3)]),
    "alarm-clock-elapsed": (-3.0, [note("A5", 0.0, 0.9, 0.2), note("D6", 0.12, 0.9, 0.3), note("A5", 0.6, 0.9, 0.2),
                                   note("D6", 0.72, 0.9, 0.3), note("A5", 1.2, 0.9, 0.2), note("D6", 1.32, 0.9, 0.6)]),
}
SOUNDS["theme-demo"] = SOUNDS["desktop-login"]


def render(notes, peak_db):
    """The sound as 16-bit samples: every note's partials summed, normalised to peak_db."""
    end = max(start + decay * 5.0 for _, start, _, decay in notes)
    length = int(end * RATE) + 1
    out = [0.0] * length
    attack = int(0.004 * RATE)
    for freq, start, level, decay in notes:
        first = int(start * RATE)
        for ratio, weight in PARTIALS:
            f = freq * ratio
            if f >= RATE / 2:
                continue
            # Higher partials fade faster, as on a struck glass.
            tau = decay / (ratio ** 0.8)
            step = 2.0 * math.pi * f / RATE
            fall = math.exp(-1.0 / (tau * RATE))
            env = level * weight
            for i in range(length - first):
                if env < 1e-5:
                    break
                rise = 0.5 - 0.5 * math.cos(math.pi * i / attack) if i < attack else 1.0
                out[first + i] += env * rise * math.sin(step * i)
                if i >= attack:
                    env *= fall
    # Trim where the sound has fallen 40 dB below its peak, and fade out the last 60 ms.
    peak = max(abs(x) for x in out) or 1.0
    last = max(i for i, x in enumerate(out) if abs(x) > peak * 1e-2)
    out = out[: last + 1]
    fade = min(len(out), int(0.06 * RATE))
    for i in range(fade):
        out[len(out) - fade + i] *= 0.5 + 0.5 * math.cos(math.pi * i / fade)
    gain = 10 ** (peak_db / 20.0) / peak
    return [max(-32767, min(32767, round(x * gain * 32767))) for x in out]


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def encoder():
    """The command that turns a WAV file into Ogg Vorbis: encoder()(source, target)."""
    if shutil.which("oggenc"):
        return lambda src, dst: ["oggenc", "--quiet", "--quality", "4", "--output", str(dst), str(src)]
    if shutil.which("gst-launch-1.0"):
        return lambda src, dst: ["gst-launch-1.0", "--quiet", "filesrc", f"location={src}", "!", "wavparse", "!",
                                 "audioconvert", "!", "vorbisenc", "quality=0.4", "!", "oggmux", "!",
                                 "filesink", f"location={dst}"]
    sys.exit("error: no Ogg Vorbis encoder: install oggenc (vorbis-tools) or GStreamer's vorbis plugin")


def main():
    folder = pathlib.Path(__file__).resolve().parent.parent / "orielos" / "stereo"
    folder.mkdir(parents=True, exist_ok=True)
    command = encoder()
    with tempfile.TemporaryDirectory() as tmp:
        for name, (peak_db, notes) in SOUNDS.items():
            wav = pathlib.Path(tmp) / f"{name}.wav"
            samples = render(notes, peak_db)
            write_wav(wav, samples)
            subprocess.run(command(wav, folder / f"{name}.oga"), check=True)
            print(f"{name}.oga: {len(samples) / RATE:.2f} s")


if __name__ == "__main__":
    main()
