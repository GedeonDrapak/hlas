// In-process benchmark harness for whisper.cpp (Whisper + Parakeet, both ggml/Metal).
// Loads the model once, then transcribes each file `reps` times and prints one JSON line per file.
// Usage: ggml_bench whisper|parakeet MODEL REPS file1.wav [file2.wav ...]
// Whisper params mirror Hlas LocalWhisper.swift: beam 5, temp 0, cs, priming prompt, flash_attn, 6 threads.
#include "whisper.h"
#include "parakeet.h"
#include "ggml-backend.h"
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

static double now_ms() {
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

// minimal reader for 16 kHz mono PCM16 WAV (what ffmpeg writes)
static bool read_wav(const char * path, std::vector<float> & out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    std::vector<char> buf((std::istreambuf_iterator<char>(f)), {});
    size_t p = 12;
    while (p + 8 <= buf.size()) {
        uint32_t sz; memcpy(&sz, &buf[p + 4], 4);
        if (memcmp(&buf[p], "data", 4) == 0) {
            size_t n = std::min<size_t>(sz, buf.size() - p - 8) / 2;
            out.resize(n);
            const int16_t * s = (const int16_t *) &buf[p + 8];
            for (size_t i = 0; i < n; i++) out[i] = s[i] / 32768.0f;
            return true;
        }
        p += 8 + sz + (sz & 1);
    }
    return false;
}

static std::string json_escape(const std::string & s) {
    std::string o;
    for (char c : s) {
        if (c == '"' || c == '\\') { o += '\\'; o += c; }
        else if (c == '\n') o += "\\n";
        else if ((unsigned char) c < 0x20) o += ' ';
        else o += c;
    }
    return o;
}

static void quiet(enum ggml_log_level, const char *, void *) {}

int main(int argc, char ** argv) {
    if (argc < 5) { fprintf(stderr, "usage\n"); return 1; }
    std::string mode = argv[1];
    const char * model = argv[2];
    int reps = atoi(argv[3]);
    ggml_backend_load_all();
    whisper_log_set(quiet, nullptr);
    parakeet_log_set(quiet, nullptr);
    const char * PRIMING = "Toto je přesný přepis mluveného projevu se správnou diakritikou, interpunkcí a velkými písmeny.";

    double t0 = now_ms();
    whisper_context * wctx = nullptr;
    parakeet_context * pctx = nullptr;
    if (mode == "whisper") {
        auto cp = whisper_context_default_params();
        cp.use_gpu = true; cp.flash_attn = true;
        wctx = whisper_init_from_file_with_params(model, cp);
        if (!wctx) return 2;
    } else {
        auto cp = parakeet_context_default_params();
        cp.use_gpu = true;
        pctx = parakeet_init_from_file_with_params(model, cp);
        if (!pctx) return 2;
    }
    double load_ms = now_ms() - t0;
    printf("{\"load_ms\": %.1f}\n", load_ms);
    fflush(stdout);

    for (int a = 4; a < argc; a++) {
        std::vector<float> pcm;
        if (!read_wav(argv[a], pcm)) { fprintf(stderr, "read fail %s\n", argv[a]); continue; }
        std::string text;
        std::vector<double> times;
        for (int r = 0; r < reps; r++) {
            text.clear();
            double s = now_ms();
            if (wctx) {
                auto p = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH);
                p.beam_search.beam_size = 5;
                p.print_progress = false; p.print_realtime = false; p.print_special = false; p.print_timestamps = false;
                p.no_timestamps = true; p.suppress_blank = true; p.temperature = 0;
                p.n_threads = 6; p.language = "cs"; p.initial_prompt = PRIMING;
                if (whisper_full(wctx, p, pcm.data(), (int) pcm.size()) != 0) { fprintf(stderr, "fail\n"); break; }
                for (int i = 0; i < whisper_full_n_segments(wctx); i++) text += whisper_full_get_segment_text(wctx, i);
            } else {
                auto p = parakeet_full_default_params(PARAKEET_SAMPLING_GREEDY);
                p.n_threads = 6;
                if (parakeet_full(pctx, p, pcm.data(), (int) pcm.size()) != 0) { fprintf(stderr, "fail\n"); break; }
                for (int i = 0; i < parakeet_full_n_segments(pctx); i++) {
                    if (i) text += " ";
                    text += parakeet_full_get_segment_text(pctx, i);
                }
            }
            times.push_back(now_ms() - s);
        }
        printf("{\"file\": \"%s\", \"dur_s\": %.3f, \"text\": \"%s\", \"ms\": [", argv[a], pcm.size() / 16000.0, json_escape(text).c_str());
        for (size_t i = 0; i < times.size(); i++) printf("%s%.1f", i ? ", " : "", times[i]);
        printf("]}\n");
        fflush(stdout);
    }
    if (wctx) whisper_free(wctx);
    if (pctx) parakeet_free(pctx);
    return 0;
}
