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


def ambient_drone() -> np.ndarray:
    """~8 s pętla: niski, falujący szum maszynowni + delikatne buczenie. Końce zgrane do zapętlenia."""
    seconds = 8.0
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    # Częstotliwości dobrane tak, żeby mieściły się całkowicie w 8 s (pętla bez trzasku).
    hum = 0.25 * np.sin(2 * np.pi * 55 * t) + 0.12 * np.sin(2 * np.pi * 82.5 * t)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / seconds)
    wind = band_noise(seconds, 60, 400) * (0.5 + 0.5 * np.sin(2 * np.pi * 2 * t / seconds + 1.0))
    return (hum + 0.6 * wind) * swell


def heartbeat() -> np.ndarray:
    """1 s pętla: "lub-dub" przy 60 BPM (tempo zmienia pitch_scale w grze)."""
    n = RATE
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for start, level in [(0.0, 1.0), (0.22, 0.7)]:
        s0 = int(start * RATE)
        k = np.arange(int(0.12 * RATE))
        thump = np.sin(2 * np.pi * 48 * k / RATE) * np.exp(-k / (0.03 * RATE)) * level
        out[s0:s0 + len(k)] += thump
    return out


def panic_breath() -> np.ndarray:
    """~1.6 s pętla: szybki, płytki oddech postaci (wyższy niż oddech potwora)."""
    parts = []
    for seconds, low, high, level in [(0.45, 700, 3000, 0.7), (0.1, 0, 0, 0.0), (0.55, 500, 2400, 0.9), (0.5, 0, 0, 0.0)]:
        n = int(seconds * RATE)
        if level == 0:
            parts.append(np.zeros(n))
            continue
        parts.append(band_noise(seconds, low, high) * envelope(n, 0.3, 0.5) * level)
    return np.concatenate(parts)


def door_thud() -> np.ndarray:
    """~0.7 s: ciężkie uderzenie w drewniane drzwi. Niskie „bum” skrzydła, krótki trzask
    drewna na początku i brzęczenie futryny/zawiasów (15x: Kenney ma tylko miękkie puknięcia)."""
    seconds = 0.7
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    body = np.sin(2 * np.pi * (72 - 20 * t) * t) * np.exp(-t * 7)          # rezonans skrzydła
    body += 0.5 * np.sin(2 * np.pi * 143 * t) * np.exp(-t * 11)
    knock = band_noise(seconds, 150, 1800) * np.exp(-t * 38)               # uderzenie w deski
    rattle = band_noise(seconds, 900, 3500) * np.exp(-t * 9) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 23 * t)))
    return body * 1.0 + knock * 0.8 + rattle * 0.12


def door_splinter() -> np.ndarray:
    """~1.3 s: wyłamanie. Najmocniejsze uderzenie, pękanie desek (seria trzasków) i upadek skrzydła."""
    seconds = 1.3
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    hit = door_thud()
    signal = np.zeros(n)
    signal[: hit.size] += hit * 1.2
    cracks = np.zeros(n)
    for start in rng.uniform(0.02, 0.45, 14):                              # drzazgi
        i = int(start * RATE)
        m = int(0.05 * RATE)
        cracks[i:i + m] += band_noise(0.05, 1200, 6000)[: n - i] * np.exp(-np.arange(min(m, n - i)) / RATE * 90) * rng.uniform(0.4, 1.0)
    signal += cracks * 0.7
    fall = int(0.75 * RATE)                                                # skrzydło uderza o podłogę
    tf = np.arange(n - fall) / RATE
    signal[fall:] += (np.sin(2 * np.pi * 55 * tf) * np.exp(-tf * 6) + band_noise((n - fall) / RATE + 0.01, 100, 900)[: n - fall] * np.exp(-tf * 14) * 0.6)
    return signal / np.max(np.abs(signal))


# --- 47g.6: rozpoznawalny dźwięk każdego typu potwora (pętle) i akcent przy wykryciu ---
# Osobny generator losowy: dźwięki wyżej nie zmieniają się po dopisaniu nowych.
rng2 = np.random.default_rng(47)


def clicks(n: int, times, freq: float, decay: float) -> np.ndarray:
    """Suche kliknięcia (krótki ton z szybkim zanikiem) w podanych chwilach (s)."""
    out = np.zeros(n)
    k = np.arange(int(0.05 * RATE))
    click = np.sin(2 * np.pi * freq * k / RATE) * np.exp(-k / (decay * RATE))
    for t0 in times:
        s0 = int(t0 * RATE)
        end = min(n, s0 + len(k))
        out[s0:end] += click[: end - s0]
    return out


def hunter_presence() -> np.ndarray:
    """Łowca, 4 s: serie szybkiego klekotu (jak cykanie owada) i ciche syczenie między nimi."""
    seconds = 4.0
    n = int(seconds * RATE)
    times = []
    for start in (0.3, 1.9, 2.6):
        count = int(rng2.integers(6, 11))
        times += list(start + np.cumsum(rng2.uniform(0.035, 0.07, count)))
    out = clicks(n, times, 1800, 0.004) + 0.6 * clicks(n, [t + 0.012 for t in times], 900, 0.006)
    hiss = band_noise(seconds, 2500, 6000) * (0.08 + 0.08 * np.sin(2 * np.pi * np.arange(n) / n))
    return out + hiss


def butcher_presence() -> np.ndarray:
    """Rzeźnik, 4 s: wlecze coś ciężkiego po betonie (zgrzyt) i co krok brzęk łańcucha."""
    seconds = 4.0
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    drag = band_noise(seconds, 200, 1800) * (0.35 + 0.25 * np.abs(np.sin(np.pi * t / 2.0)))
    out = drag * (1 + 0.4 * np.sin(2 * np.pi * 11 * t))
    k = np.arange(int(0.3 * RATE))
    for t0 in (0.5, 2.5):
        s0 = int(t0 * RATE)
        clank = sum(np.sin(2 * np.pi * f * k / RATE) for f in (520, 1230, 2110)) * np.exp(-k / (0.06 * RATE))
        out[s0:s0 + len(k)] += 0.5 * clank
    fade = np.minimum(1, np.minimum(t, seconds - t) / 0.2)  # bez trzasku na styku pętli
    return out * fade


def guard_presence() -> np.ndarray:
    """Strażnik, 4 s: niskie, ciągłe mruczenie (jak pies przy misce), pulsuje dwa razy."""
    seconds = 4.0
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    phase = 2 * np.pi * np.cumsum(44 + 3 * np.sin(2 * np.pi * 0.5 * t)) / RATE
    saw = 2 * ((phase / (2 * np.pi)) % 1) - 1
    pulse = 0.4 + 0.6 * np.sin(np.pi * t / 2.0) ** 2
    return (0.6 * saw + 0.4 * band_noise(seconds, 60, 300)) * pulse * (1 + 0.5 * np.sin(2 * np.pi * 17 * t))


def watcher_presence() -> np.ndarray:
    """Obserwator, 6 s: cienki, rozstrojony pisk (dwa bliskie tony dają dudnienie) i szept."""
    seconds = 6.0
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    tone = np.sin(2 * np.pi * 1320 * t) + np.sin(2 * np.pi * 1320.5 * t) + 0.5 * np.sin(2 * np.pi * 1977 * t)
    whisper = band_noise(seconds, 1500, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 3.0)) ** 3
    return 0.15 * tone * (0.6 + 0.4 * np.sin(2 * np.pi * t / 6.0)) + 0.5 * whisper


def abductor_presence() -> np.ndarray:
    """Porywacz, 4 s: mokre węszenie: pary krótkich wciągnięć powietrza nosem."""
    seconds = 4.0
    n = int(seconds * RATE)
    out = np.zeros(n)
    for t0 in (0.2, 0.42, 0.64, 2.1, 2.32):
        length = int(0.16 * RATE)
        s0 = int(t0 * RATE)
        sniff = band_noise(0.16, 700, 3500) * envelope(length, 0.2, 0.6)
        out[s0:s0 + length] += sniff * (1 + 0.6 * np.sin(2 * np.pi * 60 * np.arange(length) / RATE))
    return out


def stinger() -> np.ndarray:
    """Akcent przy wykryciu, 2,5 s: ostre uderzenie klastra rozstrojonych pił i szum, długi zanik."""
    seconds = 2.5
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for f in (110, 116.5, 155.6, 164.8, 233, 246.9):
        phase = 2 * np.pi * f * t * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))
        out += 2 * ((phase / (2 * np.pi)) % 1) - 1
    out = out / 6 * np.exp(-t * 1.4)
    hit = band_noise(seconds, 80, 4000) * np.exp(-t * 9)
    return out + 0.8 * hit


if __name__ == "__main__":
    save("ambient_drone.wav", ambient_drone(), 0.5)
    save("heartbeat.wav", heartbeat(), 0.9)
    save("panic_breath.wav", panic_breath(), 0.5)
    save("monster_breath.wav", breath_loop(), 0.7)
    save("monster_growl.wav", growl(), 0.8)
    save("door_thud.wav", door_thud() / np.max(np.abs(door_thud())), 0.95)
    save("door_splinter.wav", door_splinter(), 0.95)
    save("presence_hunter.wav", hunter_presence() / np.max(np.abs(hunter_presence())), 0.8)
    save("presence_butcher.wav", butcher_presence() / np.max(np.abs(butcher_presence())), 0.8)
    save("presence_guard.wav", guard_presence() / np.max(np.abs(guard_presence())), 0.8)
    save("presence_watcher.wav", watcher_presence() / np.max(np.abs(watcher_presence())), 0.7)
    save("presence_abductor.wav", abductor_presence() / np.max(np.abs(abductor_presence())), 0.8)
    save("stinger.wav", stinger() / np.max(np.abs(stinger())), 0.9)
