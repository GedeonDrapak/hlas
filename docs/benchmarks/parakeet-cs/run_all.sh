#!/bin/bash
# Runs every engine over warm-up + synthetic + noisy + KVIFF chunks (1 rep) and latency clips (5 reps),
# under /usr/bin/time -l for peak memory, then 3 cold starts per engine. Sequential, so engines never share the GPU.
# Usage: run_all.sh BENCH_DIR
set -u
B=$1; cd $B; mkdir -p out
PY=$B/venv/bin/python; S=$B/scripts
ACC="audio/syn/s01.wav $(ls audio/syn/*.wav) $(ls audio/noisy/*.wav) $(ls audio/kchunks/*.wav)"
LAT="$(ls audio/clips/*.wav)"
declare -a NAMES=(whisper pk_ggml_q8 pk_ggml_f16 pk_mlx pk_sherpa_int8)
cmd() {
  case $1 in
    whisper)        echo "$B/ggml_bench whisper models/ggml-large-v3-turbo-q5_0.bin" ;;
    pk_ggml_q8)     echo "$B/ggml_bench parakeet models/ggml-parakeet-tdt-0.6b-v3-q8_0.bin" ;;
    pk_ggml_f16)    echo "$B/ggml_bench parakeet models/ggml-parakeet-tdt-0.6b-v3-f16.bin" ;;
    pk_mlx)         echo "$PY $S/py_bench.py mlx mlx-community/parakeet-tdt-0.6b-v3" ;;
    pk_sherpa_int8) echo "$PY $S/py_bench.py sherpa models/sherpa/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8" ;;
  esac
}
for n in "${NAMES[@]}"; do
  echo "== $n"
  /usr/bin/time -l $(cmd $n) 1 $ACC > out/$n.acc.jsonl 2> out/$n.acc.time
  /usr/bin/time -l $(cmd $n) 5 audio/syn/s01.wav $LAT > out/$n.lat.jsonl 2> out/$n.lat.time
  : > out/$n.cold.jsonl
  for i in 1 2 3; do
    s=$(python3 -c 'import time;print(time.time())')
    $(cmd $n) 1 audio/clips/c00_10s.wav >> out/$n.cold.jsonl 2>/dev/null
    e=$(python3 -c 'import time;print(time.time())')
    echo "{\"process_wall_s\": $(python3 -c "print(round($e-$s,2))")}" >> out/$n.cold.jsonl
  done
done
echo DONE
