# Parakeet TDT 0.6b v3 vs. Whisper large-v3-turbo na češtině

Benchmark z 2026-11-04. Otázka: vyplatí se přidat NVIDIA Parakeet TDT 0.6b v3 jako lokální engine do Hlasu?

## TL;DR

- **Přidat jako volitelný engine ("Rychlý"), ne jako výchozí.** Na krátkém diktátu je Parakeet zhruba stejně přesný jako Whisper, 5-7x rychlejší a nehalucinuje na tichu. Na reálné spontánní řeči je ale o kus horší (víc záměn slov) a chybí mu prompt, takže neumí slovník. Zkratku "AI" skoro nikdy nenapíše správně.
- **Runtime na Macu: Parakeet přímo z whisper.cpp** (`libparakeet`, od verze 1.9.x). Hlas už `libparakeet.a` ve `Vendor/lib` má, protože se staví z checkoutu whisper.cpp 1.9.5. Bez nové závislosti, stejný ggml/Metal stack, model `ggml-parakeet-tdt-0.6b-v3-q8_0.bin` (669 MB). parakeet-mlx dává stejné výsledky, ale je to Python a bere hodně paměti.
- **Windows:** stejná cesta (whisper.cpp >= 1.9 + vlastní binding na `parakeet.h`, stejný soubor modelu). sherpa-onnx int8 funguje, ale v tomhle testu ztratil polovinu přesnosti.
- **Vedlejší nález u Whisperu:** priming prompt na jednom čistém 16s klipu a na tichu spouští halucinaci "Titulky vytvořil JohnyX.". Filtr v Hlasu ji zahodí, takže diktát potichu zmizí. Na šumu Whisper vrací "Konec.", a to filtr nechytí.

## Setup

Stroj: Apple M5 Pro, 64 GB, macOS. Všechno běží lokálně a sekvenčně, enginy se nikdy nepřetahují o GPU.

| Engine | Runtime | Model | Velikost na disku |
|---|---|---|---|
| `whisper` | whisper.cpp 1.9.5, Metal, flash attn | `ggml-large-v3-turbo-q5_0.bin` (sha256 ověřen) | 574 MB |
| `pk_ggml_q8` | whisper.cpp 1.9.5 `libparakeet`, Metal | `ggml-org/parakeet-GGUF` `ggml-parakeet-tdt-0.6b-v3-q8_0.bin` | 669 MB |
| `pk_ggml_f16` | to samé | `ggml-parakeet-tdt-0.6b-v3-f16.bin` | 1 256 MB |
| `pk_mlx` | parakeet-mlx 0.6.0, mlx 0.32.4, Python 3.12 | `mlx-community/parakeet-tdt-0.6b-v3` | 2 508 MB |
| `pk_sherpa_int8` | sherpa-onnx 2.0.1, **jen CPU**, 6 vláken | `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` | 643 MB |

Parametry Whisperu kopírují `LocalWhisper.swift`: beam 5, temperature 0, `language=cs`, `no_timestamps`, `suppress_blank`, 6 vláken, initial prompt "Toto je přesný přepis mluveného projevu se správnou diakritikou, interpunkcí a velkými písmeny." Parakeet používá greedy TDT decoding (jiný nemá) a nemá žádný prompt.

Oba ggml enginy měří vlastní C++ harness (`parakeet-cs/ggml_bench.cpp`), který načte model jednou a pak přepisuje vzorky z paměti, stejně jako Hlas. parakeet-mlx a sherpa-onnx měří `py_bench.py` stejným způsobem. Audio se načítá mimo měřený čas.

### Testovací sady

**A) Syntetika (přesná reference).** 21 diktátů o délce 6-16 s (Slack, e-mail, poznámky, nákupní seznam, čísla, data, částky, jména Ondra / Darina / Tomáš Hubálek, tech slang Seedance / Higgsfield / Kling / prompt / render / deadline / Google Drive / ElevenLabs / pull request, ř ů ě, jazykolam). ElevenLabs `eleven_multilingual_v2`, 4 české hlasy: Jan (M), Zazy.cz (M), Hana (Ž), Markéta (Ž). Navíc 5 klipů smíchaných s růžovým šumem na 20 dB SNR. Texty a štítky kategorií jsou v `parakeet-cs/references.json`. Spotřeba: 2 602 znaků.

**B) Reálná řeč.** Debata Radiožurnálu z KVIFF 2026 (21:39 min, 4 mluvčí, venkovní mobilní studio, skákání do řeči). Reference je přepis z vaultu (`interview-radiozurnal-kviff-2026-07.txt`). Pozor, ten pořídil Gemini a je učesaný: má 2 894 slov, kdežto všechny enginy vrací 3 180-3 360 slov. Absolutní WER je proto nafouknuté inserty a hodí se **jen pro relativní srovnání**. Aby všechny enginy dostaly stejné vstupy délky diktátu, je soubor rozřezaný v pauzách (ffmpeg silencedetect -22 dB) na 54 kusů po 9-28 s. 7 řezů je natvrdo uprostřed řeči. Dalších 10 klipů (10, 15, 20, 25, 30 s) slouží pro latenci.

### Metriky

WER/CER (jiwer) po normalizaci: NFC, malá písmena, `%` na "procent", interpunkce pryč, `3 500` na `3500`, sloučené mezery. "Bez diakritiky" navíc odstraní háčky a čárky. "Formát WER" nechává velká písmena a interpunkci jako samostatné tokeny, takže měří i to, jak hotově text vypadá. Latence = medián opakování 2-5 na klip v teplém procesu. Cold load = medián 3 čerstvých procesů (disková cache už teplá). Peak paměť = `peak memory footprint` z `/usr/bin/time -l` za celý běh.

## Výsledky

| Metrika | whisper turbo q5_0 | Parakeet ggml q8_0 | Parakeet ggml f16 | parakeet-mlx | sherpa-onnx int8 (CPU) |
|---|---|---|---|---|---|
| Syntetika WER (21 klipů) | 13.4 % | **6.2 %** | 6.2 % | 6.2 % | 13.6 % |
| Syntetika WER bez klipu s19 (halucinace Whisperu) | **5.1 %** | 5.8 % | 5.8 % | 5.8 % | 12.7 % |
| Syntetika CER | 11.3 % | **2.0 %** | 2.0 % | 2.2 % | 5.6 % |
| Syntetika WER bez diakritiky | 13.4 % | 6.2 % | 6.2 % | 6.2 % | 13.4 % |
| Syntetika formát WER (velká písmena + interpunkce) | 16.8 % | 9.3 % | 9.3 % | 8.9 % | 15.8 % |
| Šum 20 dB WER (5 klipů) | **4.6 %** | 11.5 % | 11.5 % | 13.1 % | 18.5 % |
| Tytéž klipy bez šumu | 32.3 % (s19) | 10.0 % | 10.0 % | 10.8 % | 16.2 % |
| Kategorie čísla | **4.1 %** | 8.2 % | 8.2 % | 7.2 % | 9.3 % |
| Kategorie tech termíny | **5.9 %** | 7.6 % | 7.6 % | 9.3 % | 12.7 % |
| Kategorie jména | 32.2 % (s19) | 6.8 % | 6.8 % | 5.1 % | 15.3 % |
| Kategorie diakritika | 12.0 % (jazykolam v číslicích) | 5.3 % | 5.3 % | 5.3 % | 18.7 % |
| KVIFF WER (relativní) | **33.4 %** | 36.4 % | 36.5 % | 36.9 % | 41.6 % |
| KVIFF záměny / výpadky slov | **284 / 111** | 402 / 127 | 401 / 134 | 413 / 139 | 535 / 189 |
| KVIFF CER | 25.8 % | **25.4 %** | 25.4 % | 25.5 % | 28.1 % |
| KVIFF WER bez diakritiky | 33.0 % | 36.1 % | 36.2 % | 36.5 % | 40.8 % |
| Začíná velkým písmenem | 95 % | 100 % | 100 % | 100 % | 95 % |
| Končí . ! ? | 100 % | 100 % | 100 % | 100 % | 100 % |
| Čárky na 100 slov (reference 6.9) | 7.4 | 6.7 | 6.7 | 6.2 | 6.4 |
| Latence 10s klipu (teplý) | 647 ms | **87 ms** | 111 ms | 160 ms | 314 ms |
| Latence 30s klipu (teplý) | 1 928 ms | **252 ms** | 282 ms | 386 ms | 1 014 ms |
| Load modelu (cold) | 279 ms | 287 ms | 466 ms | 1 144 ms | 932 ms |
| První inference po loadu (10 s) | 398 ms | 83 ms | 90 ms | 118 ms (+ cca 2.7 s kompilace grafu v prvním volání) | 262 ms |
| Studený start procesu celkem | 0.8 s | **0.4 s** | 0.6 s | 1.5 s | 1.4 s |
| Peak paměť | 938 MB | **853 MB** | 1 436 MB | 20 GB (cache MLX bez limitu; samotný latenční běh 4.8 GB) | 2 233 MB |
| Velikost modelu | 574 MB | 669 MB | 1 256 MB | 2 508 MB | 643 MB |

Úplně první načtení Parakeetu po buildu trvalo 6.4 s (kompilace Metal shaderů), potom už 0.2-0.3 s.

### Jak to číst

- **Krátký diktát, čistý zvuk:** remíza. Celý rozdíl v syntetice (13.4 % proti 6.2 %) dělá jediný klip s19, kde Whisper místo 45 slov vrátil "Titulky vytvořil JohnyX.". Bez něj vede Whisper o fous (5.1 % proti 5.8 %). Další body Whisperu ubírá jen formát čísel u jazykolamu ("333" místo "tři sta třicet tři").
- **Diakritika není problém ani u jednoho.** WER bez diakritiky je skoro stejné jako s ní, takže skoro žádná chyba není "jen v háčku". Chyby jsou ve slovech.
- **Reálná řeč:** Whisper je lepší. Na KVIFF má Parakeet o 40 % víc záměn slov (402 proti 284). Nejvíc to pozná uživatel, který mluví o AI: Whisper napsal "AI" 23x (reference 24x), Parakeet 2x a jinak píše "II", "je i", "vám i".
- **Šum:** Whisper je robustnější (4.6 % proti 11.5 % na stejných 5 klipech).
- **Kvantizace:** q8_0 a f16 dávají prakticky identický text. q8_0 je rychlejší a poloviční. MLX (bf16) přesnost nezlepší. sherpa-onnx int8 je znatelně horší, takže pro Windows bych ho nebral jako první volbu.
- **Interpunkce a velká písmena:** oba enginy je mají nativně. Parakeet je o něco striktnější (vždy velké písmeno, víc teček, méně čárek). Jako jediný sám píše `Kč` místo "korun" a `40 %` s mezerou.

## Ukázky (reference / Whisper / Parakeet ggml q8)

**1. Halucinace Whisperu na čistém diktátu (s19, 16 s)**
- REF: Chtěl bych shrnout dnešní poradu. Za prvé, Mindfall Protocol pošleme na další dva festivaly. Za druhé, na web doplníme nové reference a fotky z premiéry. Za třetí, ...
- WHISPER: Titulky vytvořil JohnyX.
- PARAKEET: Chtěl bych shrnout dnešní poradu. Za prvé, mindful protokol pošleme na další dva festival. Za druhé, na web doplníme nové reference a fotky s premiéry. Za třetí, ...

**2. Usekávání koncovek u Parakeetu (s15)**
- REF: Dnes je středa 4. listopadu 2026 a do konce roku musíme dokončit ještě dva projekty a jeden pitch.
- WHISPER: Dnes je středa 4. listopadu 2026 a do konce roku musíme dokončit ještě dva projekty a jeden pitch.
- PARAKEET: Dnes je stře 4. listopadu 2026 a do konce roku musíme dokončit ještě dva projekty a jeden pit.

**3. Čísla a měna (s14)**
- REF: Celkový rozpočet projektu je 165 000 korun, z toho 40 procent jde na generování ...
- WHISPER: Celkový rozpočet projektu je 165 tisíc korun, z toho 40% jde na generování ...
- PARAKEET: Celkový rozpočet projektu je 165 000 Kč, z toho 40 % jde na generování ...

**4. Tech slang (s06, s13)**
- REF: Ten záběr v Seedance vypadá dobře ... Zkus to přegenerovat v Klingu ... / Pushni to na branch ... a mergnu
- WHISPER: Ten záběr v sídance ... Zkus to přegenerovat v klingu ... / Puštni to na branch ... a mergnu
- PARAKEET: Ten záběr v sídlance ... Zkuste to přegenerovat v klingu ... / Pušni to na branch ... a mrgnu

Názvy nástrojů (Seedance, Higgsfield -> "Hicksfield", ElevenLabs -> "Eleven Labs") zkomolí oba. Whisper to ale umí opravit slovníkem v promptu, Parakeet ne.

**5. Jména (s05, s16)**
- REF: zavolat Darině ... / Tomáš Hubálek dnes dodělá ...
- WHISPER: zavolat darině ... / Tomáš Hubálek dnes dodělá ...
- PARAKEET: zavolat daryně ... / Tomáš Hubále dnes dodělá ...

**6. Jazykolam (s21)**
- REF: Tři sta třicet tři stříbrných stříkaček stříkalo přes tři sta třicet tři stříbrných střech.
- WHISPER: 333 stříbrných stříkaček stříkalo přes 333 stříbrných střech.
- PARAKEET: Tři sta třicet tři stříbrných stříkaček stříkalo přes tři sta třicet tři stříbrných střech.

Oboje je správně, jen jinak zapsané. Ř a ů zvládnou oba bez chyby.

**7. Reálná řeč, KVIFF (úsek s "AI")**
- WHISPER: 75 tisíc korun či si jenom v AI nákladech ... pomáháme vlastně filmařům se adaptovat na ten AI trh, na ty AI inovace.
- PARAKEET: 75 tisíc korun čistě jenom v II nákladech ... pomáháme filmařům se adaptovat na ten II trh i na ty inovace.

**8. Ticho a šum bez řeči (8 s)**
- WHISPER: ticho -> "Titulky vytvořil JohnyX.", růžový i hnědý šum -> "Konec."
- PARAKEET: ve všech třech případech prázdný výstup.

## Typické chyby

**Parakeet**
- Usekává koncovky a krátké slabiky: "stře", "pit", "Hubále", "Klče", "rend", "nahjeme".
- Splete z/s a slučuje nebo rozděluje slova: "s premiéry", "vyzvedá váš", "daryně".
- Neumí "AI" ani anglické zkratky, chybí mu jakýkoli kontext nebo prompt (TDT nemá initial prompt ani hotword biasing).
- Na šumu se zhorší víc než Whisper.
- Plus: nehalucinuje, na tichu a šumu vrací prázdný text a vždy přepíše celý vstup.

**Whisper turbo + priming prompt**
- Halucinace "Titulky vytvořil JohnyX." na čistém 16s klipu (s19). Spouští ji **priming prompt**: stejný klip bez promptu se přepíše správně, greedy s promptem halucinuje taky. `Hallucinations.filter` výstup zahodí, takže uživatel dostane prázdný diktát.
- Na šumu bez řeči vrací "Konec.", a to filtr nechytí.
- Čísla píše číslicemi i tam, kde se v češtině píšou slovy ("7 dní", "v 8 ráno", "333"). Pro diktát je to spíš plus.
- Na spontánní řeči vyhlazuje a občas vynechá celou větu (KVIFF k033).

## Doporučení

1. **Přidat Parakeet jako volitelný engine, ne jako výchozí.** Hodí se jako "Rychlý" lokální režim, pro dlouhé diktáty a pro slabší stroje. Vrátí 30 s řeči za 0.25 s (Whisper za 1.9 s) a nikdy nevrátí vymyšlený text. Výchozí zůstává Whisper turbo: na reálné řeči dělá o 40 % méně záměn, píše "AI" správně, lépe snáší šum a jeho prompt nese uživatelský slovník.
2. **Mac runtime: whisper.cpp `libparakeet` (ggml, Metal) s modelem q8_0.** Hlas už ji linkuje (`Vendor/lib/libparakeet.a` z checkoutu 1.9.5). Stačí přidat `parakeet.h` do `CWhisper/include` (`make` ho zatím nekopíruje) a v `LocalWhisper.swift` druhou větev: `parakeet_init_from_file_with_params` a `parakeet_full(ctx, parakeet_full_default_params(PARAKEET_SAMPLING_GREEDY), samples, n)`. Stávající stahování modelů a validace souborů zůstanou. Model `ggml-org/parakeet-GGUF` q8_0 (669 MB).
   - parakeet-mlx ne: je to Python, nic nepřidá k přesnosti a bez limitu cache bere hodně paměti.
   - **FluidAudio** (Swift, CoreML na Neural Engine, Parakeet v3) je rozumná alternativa, pokud by šlo o spotřebu baterie. Tady jsem ho netestoval a přidal by novou závislost, i když ggml cesta je už teď 7x rychlejší než Whisper.
   - sherpa-onnx C API funguje, ale int8 export dal dvojnásobné WER.
3. **Windows (`hlas-win`):** přejít z vendorovaného whisper.cpp 1.8.3 na >= 1.9.5 a ve vendorovaném `whisper-rs-sys` vygenerovat bindgen i pro `parakeet.h` (`whisper-rs` Parakeet nevystavuje). Výhoda je stejný soubor modelu i stejné chování na obou platformách a Vulkan feature zůstává. Záloha je sherpa-onnx (crate `sherpa-rs`), ale s int8 modelem počítat s horší přesností (13.6 % proti 6.2 %), případně zkusit jeho fp16 export. Rychlost na Windows CPU a Vulkanu jsem neměřil.
4. **Nezávisle na Parakeetu opravit Whisper:** zvážit kratší nebo jiný priming prompt (nebo ho vypnout, když uživatel nemá slovník), přidat do filtru "konec." pro výstupy o jednom slově a zahazovat vstupy bez řeči ještě před inferencí (energie nebo Silero VAD, které whisper.cpp už obsahuje). Další možnost je fallback: když Whisper vrátí prázdno nebo halucinaci, přepsat stejné audio Parakeetem (stojí cca 90 ms).

## Co se netestovalo nebo omezení

- Syntetika je TTS, tedy čistá, plynulá a bez přeřeků. Reálné diktáty uživatele budou někde mezi syntetikou a rozhlasovou debatou.
- KVIFF reference je přepis od Geminiho, ne doslovný. Absolutní WER neber vážně, platí jen pořadí a poměr záměn.
- Malý vzorek: 21 + 5 syntetických klipů a 21 minut reálné řeči. Rozdíl 5.1 % proti 5.8 % na syntetice není statisticky významný.
- FluidAudio (CoreML/ANE) a Windows runtime jsem neměřil. sherpa-onnx běžel jen na CPU.
- Neověřoval jsem, jestli Hlas nemá před Whisperem energetický gate, který by test s tichem v praxi zamaskoval.

## Reprodukce

Skripty jsou v `docs/benchmarks/parakeet-cs/` (bez audia a bez klíčů):

- `references.json`: texty, hlasy a štítky syntetické sady
- `tts_generate.py`: ElevenLabs TTS (`ELEVENLABS_API_KEY` z prostředí) a převod na 16 kHz wav
- `prep_audio.py`: šumové kopie, KVIFF wav, latenční klipy a vyčištěná reference
- `chunk_long.py`: řezání dlouhého audia v pauzách
- `ggml_bench.cpp`: harness pro Whisper a Parakeet přes whisper.cpp. Build: `clang++ -std=c++17 -O2 -I$W/include -I$W/ggml/include ggml_bench.cpp -L$BUILD/bin -lwhisper -lparakeet -lggml -lggml-base -Wl,-rpath,$BUILD/bin -o ggml_bench`
- `py_bench.py`: harness pro parakeet-mlx a sherpa-onnx (venv Python 3.12: `parakeet-mlx jiwer sherpa-onnx soundfile numpy`)
- `run_all.sh`: spustí všechny enginy (čeká skripty v `$B/scripts`, audio v `$B/audio`, modely v `$B/models`)
- `evaluate.py`: tabulka výsledků. `analyze.py`: WER po klipech a rozpad chyb na KVIFF

Rychlé ověření halucinace: `whisper-cli -m ggml-large-v3-turbo-q5_0.bin -l cs --prompt "Toto je přesný přepis ..." -bs 5 -fa -nt -f s19.wav` vrátí "Titulky vytvořil JohnyX.". Bez `--prompt` vrátí správný text.
