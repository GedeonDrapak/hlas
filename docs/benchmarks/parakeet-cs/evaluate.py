"""Score benchmark outputs. Usage: python evaluate.py BENCH_DIR > results.md (also writes out/results.json)
WER/CER after normalization: NFC, lowercase, '%' -> 'procent', punctuation -> space, digit groups '3 500' -> '3500',
whitespace collapsed. 'WER bez diakritiky' additionally strips combining marks (ř->r, ů->u).
'Formát WER' keeps case and punctuation (punctuation split off as separate tokens) on the synthetic set."""
import json, os, re, statistics, sys, unicodedata
import jiwer

B = sys.argv[1]
ENGINES = ["whisper", "pk_ggml_q8", "pk_ggml_f16", "pk_mlx", "pk_sherpa_int8"]
refs = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "references.json")))
REF = {u["id"]: u for u in refs["utterances"]}

def norm(s, strip_diacritics=False):
    s = unicodedata.normalize("NFC", s).lower().replace("%", " procent ")
    s = re.sub(r"[^\w\s]", " ", s)
    s = re.sub(r"(?<=\d) (?=\d{3}\b)", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    if strip_diacritics:
        s = "".join(c for c in unicodedata.normalize("NFD", s) if not unicodedata.combining(c))
    return s

def fmt_tokens(s):
    s = unicodedata.normalize("NFC", s.strip())
    s = re.sub(r"([.,!?:;])", r" \1 ", s)
    return re.sub(r"\s+", " ", s).strip()

def scores(r, h):
    rn, hn = [norm(x) for x in r], [norm(x) for x in h]
    rd, hd = [norm(x, True) for x in r], [norm(x, True) for x in h]
    return {"wer": jiwer.wer(rn, hn), "cer": jiwer.cer(rn, hn), "wer_nodia": jiwer.wer(rd, hd)}

def load(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    meta = [r for r in rows if "load_ms" in r or "process_wall_s" in r]
    return meta, [r for r in rows if "file" in r]

def peak_mb(path):
    for l in open(path):
        if "peak memory footprint" in l:
            return int(l.split()[0]) / 1e6
    return None

kref = open(f"{B}/audio/kviff_ref.txt", encoding="utf-8").read()
res, outs = {}, {}
for e in ENGINES:
    if not os.path.exists(f"{B}/out/{e}.acc.jsonl"):
        continue
    _, rows = load(f"{B}/out/{e}.acc.jsonl")
    rows = rows[1:]  # drop warm-up
    by = {}
    for r in rows:
        k = r["file"].split("/")[-2] + "/" + os.path.basename(r["file"])[:-4]
        by[k] = r["text"].strip()
    outs[e] = by
    syn_ids = sorted(REF)
    R = {}
    R["syn"] = scores([REF[i]["text"] for i in syn_ids], [by[f"syn/{i}"] for i in syn_ids])
    R["syn_fmt_wer"] = jiwer.wer([fmt_tokens(REF[i]["text"]) for i in syn_ids], [fmt_tokens(by[f"syn/{i}"]) for i in syn_ids])
    nid = refs["noisy_copies"]
    R["noisy"] = scores([REF[i]["text"] for i in nid], [by[f"noisy/{i}_n20"] for i in nid])
    R["noisy_clean_same5"] = scores([REF[i]["text"] for i in nid], [by[f"syn/{i}"] for i in nid])
    for tag in ["numbers", "tech", "names", "diacritics"]:
        ids = [i for i in syn_ids if tag in REF[i]["tags"]]
        R[f"tag_{tag}"] = scores([REF[i]["text"] for i in ids], [by[f"syn/{i}"] for i in ids])
    khyp = " ".join(by[k] for k in sorted(k for k in by if k.startswith("kchunks/")))
    outs[e]["_kviff_full"] = khyp
    R["kviff"] = scores([kref], [khyp])
    hs = [by[f"syn/{i}"] for i in syn_ids]
    R["starts_upper"] = sum(1 for h in hs if h[:1].isupper()) / len(hs)
    R["ends_punct"] = sum(1 for h in hs if h[-1:] in ".!?") / len(hs)
    R["commas_per_100w_syn"] = 100 * sum(h.count(",") for h in hs) / sum(len(h.split()) for h in hs)
    R["peak_mb"] = peak_mb(f"{B}/out/{e}.acc.time")
    # latency: median of reps 2..5 per clip
    _, lat = load(f"{B}/out/{e}.lat.jsonl")
    lat = [r for r in lat if "/clips/" in r["file"]]
    med = {os.path.basename(r["file"]): statistics.median(r["ms"][1:]) for r in lat}
    R["lat10_ms"] = statistics.mean(v for k, v in med.items() if k.endswith("_10s.wav"))
    R["lat30_ms"] = statistics.mean(v for k, v in med.items() if k.endswith("_30s.wav"))
    R["first_call_10s_ms"] = statistics.median([r["ms"][0] for r in lat if r["file"].endswith("c00_10s.wav")])
    meta, cold = load(f"{B}/out/{e}.cold.jsonl")
    R["cold_load_ms"] = statistics.median(m["load_ms"] for m in meta if "load_ms" in m)
    R["cold_first_infer_ms"] = statistics.median(r["ms"][0] for r in cold)
    R["cold_process_s"] = statistics.median(m["process_wall_s"] for m in meta if "process_wall_s" in m)
    res[e] = R

json.dump({"results": res, "outputs": outs}, open(f"{B}/out/results.json", "w"), ensure_ascii=False, indent=1)
pct = lambda x: f"{100*x:.1f} %"
print("| metrika | " + " | ".join(res) + " |")
print("|---|" + "---|" * len(res))
rows = [("Syntetika WER", lambda R: pct(R["syn"]["wer"])), ("Syntetika CER", lambda R: pct(R["syn"]["cer"])),
        ("Syntetika WER bez diakritiky", lambda R: pct(R["syn"]["wer_nodia"])), ("Syntetika formát WER (velká písmena + interpunkce)", lambda R: pct(R["syn_fmt_wer"])),
        ("Šum 20 dB WER (5 klipů)", lambda R: pct(R["noisy"]["wer"])), ("Tytéž klipy bez šumu WER", lambda R: pct(R["noisy_clean_same5"]["wer"])),
        ("Čísla WER", lambda R: pct(R["tag_numbers"]["wer"])), ("Tech termíny WER", lambda R: pct(R["tag_tech"]["wer"])),
        ("Jména WER", lambda R: pct(R["tag_names"]["wer"])), ("Diakritika WER", lambda R: pct(R["tag_diacritics"]["wer"])),
        ("KVIFF WER", lambda R: pct(R["kviff"]["wer"])), ("KVIFF CER", lambda R: pct(R["kviff"]["cer"])), ("KVIFF WER bez diakritiky", lambda R: pct(R["kviff"]["wer_nodia"])),
        ("Začíná velkým písmenem", lambda R: pct(R["starts_upper"])), ("Končí . ! ?", lambda R: pct(R["ends_punct"])), ("Čárky na 100 slov", lambda R: f"{R['commas_per_100w_syn']:.1f}"),
        ("Latence 10 s klip (warm)", lambda R: f"{R['lat10_ms']:.0f} ms"), ("Latence 30 s klip (warm)", lambda R: f"{R['lat30_ms']:.0f} ms"),
        ("Cold load modelu", lambda R: f"{R['cold_load_ms']:.0f} ms"), ("První inference po loadu (10 s)", lambda R: f"{R['cold_first_infer_ms']:.0f} ms"),
        ("Studený start celkem (proces)", lambda R: f"{R['cold_process_s']:.1f} s"), ("Peak paměť", lambda R: f"{R['peak_mb']:.0f} MB")]
for name, f in rows:
    print(f"| {name} | " + " | ".join(f(res[e]) for e in res) + " |")
