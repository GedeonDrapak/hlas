#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bench_dir=$(mktemp -d)
trap 'rm -rf "$bench_dir"' EXIT
git show 49b9699:Sources/HlasCore/WAVEncoder.swift | sed 's/enum WAVEncoder/enum BaselineWAVEncoder/' > "$bench_dir/Baseline.swift"
swiftc -O "$bench_dir/Baseline.swift" Sources/HlasCore/WAVEncoder.swift tools/benchmarks/wav.swift -o "$bench_dir/benchmark"
"$bench_dir/benchmark"
