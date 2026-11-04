"""Prepare noisy copies of synthetic clips, the KVIFF 16 kHz wav, latency clips and the KVIFF reference text.
Usage: python prep_audio.py BENCH_DIR TRANSCRIPT_TXT
"""
import json, os, re, subprocess, sys
import numpy as np, soundfile as sf

B, T = sys.argv[1], sys.argv[2]
refs = json.load(open(os.path.join(os.path.dirname(__file__), "references.json")))
rng = np.random.default_rng(42)

def pink(n):
    w = rng.standard_normal(n)
    X = np.fft.rfft(w)
    f = np.arange(len(X)); f[0] = 1
    y = np.fft.irfft(X / np.sqrt(f), n)
    return y / np.sqrt(np.mean(y ** 2))

os.makedirs(f"{B}/audio/noisy", exist_ok=True)
for uid in refs["noisy_copies"]:
    x, sr = sf.read(f"{B}/audio/syn/{uid}.wav")
    speech = x[np.abs(x) > 0.01]  # rough speech-only RMS
    rms = np.sqrt(np.mean(speech ** 2))
    n = pink(len(x)) * rms / (10 ** (20 / 20))  # 20 dB SNR
    y = x + n
    y = y / max(1.0, np.max(np.abs(y)) / 0.99)
    sf.write(f"{B}/audio/noisy/{uid}_n20.wav", y, sr, subtype="PCM_16")

# KVIFF full file
kw = f"{B}/audio/kviff.wav"
if not os.path.exists(kw):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f"{B}/audio/kviff.mp3", "-ar", "16000", "-ac", "1", kw], check=True)

# latency clips: 10 clips, 10-30 s, spread over the debate
os.makedirs(f"{B}/audio/clips", exist_ok=True)
spec = [(95, 10), (210, 30), (330, 15), (450, 20), (575, 10), (690, 30), (820, 25), (960, 10), (1080, 30), (1190, 20)]
for i, (s, d) in enumerate(spec):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(s), "-t", str(d), "-i", kw,
                    f"{B}/audio/clips/c{i:02d}_{d}s.wav"], check=True)

# KVIFF reference text: drop header, timestamps, speaker labels, stage directions
raw = open(T, encoding="utf-8").read()
body = raw.split("=" * 70)[1]
lines = []
for ln in body.splitlines():
    ln = re.sub(r"^\[\d+:\d+\]\s*", "", ln.strip())
    ln = re.sub(r"^[A-ZÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ][\wáčďéěíňóřšťúůýž]+:\s*", "", ln)
    ln = re.sub(r"\([^)]*\)", "", ln).strip()
    if ln:
        lines.append(ln)
open(f"{B}/audio/kviff_ref.txt", "w", encoding="utf-8").write(" ".join(lines) + "\n")
print("ref words:", len(" ".join(lines).split()))
