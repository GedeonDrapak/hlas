"""Generate synthetic Czech dictation clips with ElevenLabs TTS.
Reads ELEVENLABS_API_KEY from env (never printed). Writes mp3 + 16 kHz mono wav.
Usage: python tts_generate.py references.json OUT_DIR
"""
import json, os, subprocess, sys, urllib.request

refs = json.load(open(sys.argv[1]))
out = sys.argv[2]
os.makedirs(out, exist_ok=True)
key = os.environ["ELEVENLABS_API_KEY"]
chars = 0
for u in refs["utterances"]:
    mp3 = os.path.join(out, u["id"] + ".mp3")
    wav = os.path.join(out, u["id"] + ".wav")
    if not os.path.exists(mp3):
        vid = refs["voices"][u["voice"]]
        body = json.dumps({"text": u["text"], "model_id": refs["tts_model"],
                           "voice_settings": {"stability": 0.5, "similarity_boost": 0.75}}).encode()
        req = urllib.request.Request(
            f"https://api.elevenlabs.io/v1/text-to-speech/{vid}?output_format=mp3_44100_128",
            data=body, headers={"xi-api-key": key, "Content-Type": "application/json"})
        with urllib.request.urlopen(req) as r, open(mp3, "wb") as f:
            f.write(r.read())
        chars += len(u["text"])
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", mp3, "-ar", "16000", "-ac", "1",
                    "-c:a", "pcm_s16le", wav], check=True)
print("TTS characters billed this run:", chars)
