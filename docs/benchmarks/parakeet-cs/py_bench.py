"""In-process benchmark for parakeet-mlx and sherpa-onnx (same JSON-lines output as ggml_bench).
Usage: python py_bench.py mlx|sherpa MODEL REPS file1.wav [...]
  mlx:    MODEL = HF repo id (mlx-community/parakeet-tdt-0.6b-v3)
  sherpa: MODEL = dir with encoder/decoder/joiner .int8.onnx + tokens.txt
Audio is loaded before timing (Hlas passes samples, not files)."""
import json, sys, time
import numpy as np, soundfile as sf

mode, model, reps, files = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
t0 = time.perf_counter()
if mode == "mlx":
    import mlx.core as mx
    from parakeet_mlx import from_pretrained
    from parakeet_mlx.audio import get_logmel
    m = from_pretrained(model)
    mx.eval(m.parameters())

    def run(x):
        mel = get_logmel(mx.array(x, dtype=mx.float32), m.preprocessor_config)
        return m.generate(mel)[0].text.strip()
else:
    import sherpa_onnx
    rec = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=f"{model}/encoder.int8.onnx", decoder=f"{model}/decoder.int8.onnx",
        joiner=f"{model}/joiner.int8.onnx", tokens=f"{model}/tokens.txt",
        model_type="nemo_transducer", num_threads=6, provider="cpu")

    def run(x):
        s = rec.create_stream()
        s.accept_waveform(16000, x)
        rec.decode_stream(s)
        return s.result.text.strip()
print(json.dumps({"load_ms": round((time.perf_counter() - t0) * 1000, 1)}), flush=True)

for f in files:
    x, sr = sf.read(f, dtype="float32")
    assert sr == 16000
    times, text = [], ""
    for _ in range(reps):
        s = time.perf_counter()
        text = run(x)
        times.append(round((time.perf_counter() - s) * 1000, 1))
    print(json.dumps({"file": f, "dur_s": round(len(x) / sr, 3), "text": text, "ms": times}, ensure_ascii=False), flush=True)
