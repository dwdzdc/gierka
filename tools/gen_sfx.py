"""Generuje placeholderowe dźwięki potwora (oddech, warczenie) do assets/sfx/generated/.

Uruchom: python3 tools/gen_sfx.py   (wymaga numpy)
To tylko zastępstwo, dopóki nie znajdziemy lepszych dźwięków (CC0).
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sfx" / "generated"
rng = np.random.default_rng(7)


def band_noise(seconds: float, low: float, high: float) -> np.ndarray:
    """Szum ograniczony do pasma [low, high] Hz (filtr w dziedzinie częstotliwości)."""
    n = int(seconds * RATE)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    spectrum[(freqs < low) | (freqs > high)] = 0
    signal = np.fft.irfft(spectrum, n)
    return signal / np.max(np.abs(signal))


def envelope(n: int, attack: float, release: float) -> np.ndarray:
    t = np.linspace(0, 1, n)
    return np.clip(t / attack, 0, 1) * np.clip((1 - t) / release, 0, 1)


def save(name: str, signal: np.ndarray, gain: float = 0.8) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data = (np.clip(signal * gain, -1, 1) * 32767).astype(np.int16)
    with wave.open(str(OUT / name), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print("zapisano", OUT / name)


def breath_loop() -> np.ndarray:
    """Pętla ~4 s: chrapliwy wdech i dłuższy wydech, cisza na końcach (łatwe zapętlenie)."""
    parts = []
    for seconds, low, high, level in [(1.1, 300, 1400, 0.6), (0.25, 0, 0, 0.0), (1.5, 150, 900, 1.0), (1.15, 0, 0, 0.0)]:
        n = int(seconds * RATE)
        if level == 0:
            parts.append(np.zeros(n))
            continue
        rasp = 1 + 0.5 * np.sin(2 * np.pi * 31 * np.arange(n) / RATE)  # chrapanie
        parts.append(band_noise(seconds, low, high) * envelope(n, 0.35, 0.45) * rasp * level)
    return np.concatenate(parts)


def growl() -> np.ndarray:
    """~1.6 s niskiego, nierównego warczenia."""
    seconds = 1.6
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    pitch = 58 + 10 * np.sin(2 * np.pi * 1.3 * t) + rng.normal(0, 2, n).cumsum() / 200
    phase = 2 * np.pi * np.cumsum(pitch) / RATE
    saw = 2 * ((phase / (2 * np.pi)) % 1) - 1
    rough = 1 + 0.6 * np.sin(2 * np.pi * 23 * t)
    signal = (0.7 * saw + 0.5 * band_noise(seconds, 80, 700)) * rough
    return signal * envelope(n, 0.15, 0.35)


if __name__ == "__main__":
    save("monster_breath.wav", breath_loop(), 0.7)
    save("monster_growl.wav", growl(), 0.8)
