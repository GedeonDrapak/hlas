"""Split a long 16 kHz wav into <=28 s chunks cut at pauses (ffmpeg silencedetect at -22 dB; radio audio is loud, mean -15.5 dB), so every engine sees identical
dictation-length inputs. Usage: python chunk_long.py IN.wav OUT_DIR"""
import os, re, subprocess, sys
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
log = subprocess.run(["ffmpeg", "-i", src, "-af", "silencedetect=noise=-22dB:d=0.2", "-f", "null", "-"],
                     capture_output=True, text=True).stderr
starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", log)]
ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", log)]
mids = [(s + e) / 2 for s, e in zip(starts, ends)]
dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", src],
                           capture_output=True, text=True).stdout)
cuts, pos = [0.0], 0.0
while dur - pos > 28:
    cand = [m for m in mids if pos + 8 < m <= pos + 28]
    pos = cand[-1] if cand else pos + 28
    cuts.append(pos)
cuts.append(dur)
for i in range(len(cuts) - 1):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{cuts[i]:.3f}", "-to", f"{cuts[i+1]:.3f}", "-i", src,
                    "-c:a", "pcm_s16le", f"{out}/k{i:03d}.wav"], check=True)
print(len(cuts) - 1, "chunks; hard cuts:", sum(1 for i in range(1, len(cuts) - 1) if cuts[i] not in mids))
