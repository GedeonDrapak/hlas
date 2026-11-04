"""Per-utterance WER, KVIFF error breakdown, whisper WER without s19. Usage: python analyze.py BENCH_DIR"""
import json, sys, os, importlib.util
import jiwer
B = sys.argv[1]
d = json.load(open(f"{B}/out/results.json")); outs = d["outputs"]
refs = {u["id"]: u for u in json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "references.json")))["utterances"]}
import re, unicodedata
def norm(s):
    s = unicodedata.normalize("NFC", s).lower().replace("%", " procent ")
    s = re.sub(r"[^\w\s]", " ", s); s = re.sub(r"(?<=\d) (?=\d{3}\b)", "", s)
    return re.sub(r"\s+", " ", s).strip()
E = list(outs)
print("id " + " ".join(f"{e[:12]:>12}" for e in E))
for i in sorted(refs):
    print(i, " ".join(f"{100*jiwer.wer(norm(refs[i]['text']), norm(outs[e]['syn/'+i])):12.0f}" for e in E))
ids = [i for i in sorted(refs) if i != "s19"]
for e in E:
    w = jiwer.wer([norm(refs[i]["text"]) for i in ids], [norm(outs[e]["syn/" + i]) for i in ids])
    print("syn WER without s19", e, f"{100*w:.1f}")
kref = norm(open(f"{B}/audio/kviff_ref.txt").read())
for e in E:
    o = jiwer.process_words(kref, norm(outs[e]["_kviff_full"]))
    print("kviff", e, "S", o.substitutions, "D", o.deletions, "I", o.insertions, "hyp words", len(norm(outs[e]["_kviff_full"]).split()), "ref words", len(kref.split()))
