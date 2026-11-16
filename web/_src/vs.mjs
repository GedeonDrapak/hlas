import { costChart, featureGrid, howItWorks, verdict, faqAccordion, keyCalculator, ctaBand, eur } from './visual.mjs';
// "Hlas vs X" comparison pages and the "cheapest dictation app" page, Czech and English.
// Prices come from COMPETITORS in pages.mjs (official pricing pages, checked 14-15 November 2026).
// Only claims we can back up: prices and plans from that table, and the offline column only
// where the vendor's own product page states it. Each page also says when the other app is the better pick.

const HLAS_YEAR = 35;
const num = (s) => parseFloat(String(s).replace(',', '.'));

// slug, display name, offline mode (null = not stated by us), and what the other app does better.
export const VS = [
  {
    key: 'Wispr Flow', plans: [{ n: 'Wispr Flow', y: 130.29 }], slug: 'hlas-vs-wispr-flow',
    offline: { cs: 'Ne, cloudová služba', en: 'No, cloud service' },
    better: {
      cs: 'Wispr Flow je hotová cloudová služba s propracovaným přepisováním do čistého textu a s bezplatným tarifem s týdenními limity. Pokud vám nevadí 12 až 15 $ měsíčně a chcete jednu službu na všech zařízeních, dává smysl.',
      en: 'Wispr Flow is a polished cloud service with careful clean-up of your text and a free plan with weekly limits. If $12 to $15 a month is fine and you want one service on all your devices, it makes sense.',
    },
    pickHlas: {
      cs: 'Hlas umí diktovat i úplně offline a zdarma, zvuk pak neopustí počítač. Hlas Cloud bez limitu stojí 35 € ročně, tedy asi o 73 % méně než Wispr Flow při roční platbě. Čeština, slovenština a angličtina mají v Hlasu vlastní ladění.',
      en: 'Hlas can also dictate fully offline and for free, so the audio never leaves your computer. Unlimited Hlas Cloud is €35 a year, about 73 % less than Wispr Flow billed yearly. Czech, Slovak and English get extra tuning in Hlas.',
    },
  },
  {
    key: 'Superwhisper', plans: [{ n: 'Superwhisper Pro', y: 76.90 }, { n: { cs: 'Superwhisper doživotně', en: 'Superwhisper lifetime' }, o: 226.19 }], slug: 'hlas-vs-superwhisper',
    offline: { cs: 'Ano, lokální Whisper', en: 'Yes, local Whisper' },
    better: {
      cs: 'Superwhisper má jednorázovou doživotní licenci (249,99 $), hodně režimů a nastavení a dlouhou historii na Macu. Pokud chcete platit jen jednou a hrát si s režimy, je to silná volba.',
      en: 'Superwhisper offers a lifetime licence ($249.99), many modes and settings and a long track record on the Mac. If you want to pay once and enjoy tweaking modes, it is a strong pick.',
    },
    pickHlas: {
      cs: 'Hlas je malý (4 MB, v klidu asi 60 MB RAM) a lokální přepis je zdarma bez limitu. Neomezený cloudový přepis bez klíčů stojí 35 € ročně proti 84,99 $ ročně u Superwhisper Pro, tedy asi o 54 % méně. Hlas běží i na Windows.',
      en: 'Hlas is tiny (4 MB, about 60 MB of RAM when idle) and local transcription is free with no limit. Unlimited cloud transcription without keys is €35 a year against $84.99 a year for Superwhisper Pro, about 54 % less. Hlas also runs on Windows.',
    },
  },
  {
    key: 'Willow', plans: [{ n: 'Willow Pro', y: 130.29 }], slug: 'hlas-vs-willow',
    offline: null,
    better: {
      cs: 'Willow je cloudová diktovací služba se zkušební verzí a tarifem Pro. Pokud vám vyhovuje její styl a nevadí 12 $ měsíčně při roční platbě, zůstaňte u ní.',
      en: 'Willow is a cloud dictation service with a trial and a Pro plan. If you like how it works and $12 a month billed yearly is fine, stay with it.',
    },
    pickHlas: {
      cs: 'Hlas Cloud stojí 35 € ročně, asi o 73 % méně než Willow Pro při roční platbě. K tomu Hlas umí diktovat offline zdarma a zvuk pak neopustí počítač.',
      en: 'Hlas Cloud is €35 a year, about 73 % less than Willow Pro billed yearly. On top of that Hlas dictates offline for free, and the audio then never leaves your computer.',
    },
  },
  {
    key: 'Aqua Voice', plans: [{ n: 'Aqua Voice Pro', y: 108.58 }], slug: 'hlas-vs-aqua-voice',
    offline: null,
    better: {
      cs: 'Aqua Voice má bezplatných 2 000 slov, tarify Pro a Max a 70% slevu pro studenty. Pro studenta může vyjít levně.',
      en: 'Aqua Voice gives 2,000 free words, Pro and Max plans and 70 % off for students. For a student it can be cheap.',
    },
    pickHlas: {
      cs: 'Hlas Cloud bez limitu slov stojí 35 € ročně, asi o 68 % méně než Aqua Voice Pro při roční platbě. Lokální přepis v Hlasu je zdarma bez limitu.',
      en: 'Hlas Cloud with no word limit is €35 a year, about 68 % less than Aqua Voice Pro billed yearly. Local transcription in Hlas is free with no limit.',
    },
  },
  {
    key: 'MacWhisper', plans: [{ n: 'MacWhisper Pro', o: 64.00 }], slug: 'hlas-vs-macwhisper',
    offline: { cs: 'Ano, lokální Whisper', en: 'Yes, local Whisper' },
    better: {
      cs: 'MacWhisper je zaměřený na přepis souborů a schůzek: nahrávky, titulky, export. Pokud přepisujete hlavně hotové nahrávky, je pro to stavěný. Pro jednou zaplatíte 64 €.',
      en: 'MacWhisper focuses on transcribing files and meetings: recordings, subtitles, export. If you mostly transcribe finished recordings, it is built for that. Pro is €64 once.',
    },
    pickHlas: {
      cs: 'Hlas je stavěný na diktování: podržíte Fn, mluvíte a text se napíše tam, kde je kurzor, v jakékoli aplikaci. Lokálně zdarma, i na Windows. Umí přepsat i krátké zvukové soubory.',
      en: 'Hlas is built for dictation: hold Fn, speak, and the text lands where your cursor is, in any app. Free locally, on Windows too. It can also transcribe short audio files.',
    },
  },
  {
    key: 'VoiceInk', plans: [{ n: 'VoiceInk', o: 22.62 }], slug: 'hlas-vs-voiceink',
    offline: { cs: 'Ano, lokální modely', en: 'Yes, local models' },
    better: {
      cs: 'VoiceInk je open source a placená verze stojí 25 $ jednou za jeden Mac. Pokud chcete jednorázovou platbu a lokální přepis, je to férová nabídka.',
      en: 'VoiceInk is open source and the paid version is $25 once for one Mac. If you want a one-time payment and local transcription, it is a fair deal.',
    },
    pickHlas: {
      cs: 'Hlas je lokálně zdarma úplně, bez jednorázové platby, a běží i na Windows. Kdo nechce stahovat model ani řešit klíče, má Hlas Cloud za 35 € ročně. Čeština a slovenština mají v Hlasu vlastní ladění.',
      en: 'Hlas is completely free locally, with no one-time fee, and it runs on Windows too. If you do not want to download a model or deal with keys, Hlas Cloud is €35 a year. Czech and Slovak get extra tuning in Hlas.',
    },
  },
  {
    key: 'Spokenly', plans: [{ n: 'Spokenly Pro', y: 130.29 }, { n: 'Spokenly Local+', o: 26.24 }], slug: 'hlas-vs-spokenly',
    offline: { cs: 'Ano, lokální modely', en: 'Yes, local models' },
    better: {
      cs: 'Spokenly běží na Macu, Windows, Linuxu, iOS i Androidu a má jednorázovou licenci Local+ za 29 $. Pokud diktujete i z telefonu, pokryje víc zařízení.',
      en: 'Spokenly runs on Mac, Windows, Linux, iOS and Android and has a one-time Local+ licence for $29. If you also dictate on your phone, it covers more devices.',
    },
    pickHlas: {
      cs: 'Hlas je lokálně zdarma bez jednorázové platby. Neomezený cloud stojí 35 € ročně proti 144 $ ročně u Spokenly Pro, tedy asi o 73 % méně.',
      en: 'Hlas is free locally with no one-time fee. Unlimited cloud is €35 a year against $144 a year for Spokenly Pro, about 73 % less.',
    },
  },
];

export function vsPages(ctx) {
  const { COMPETITORS, shell, qa, faqLd, pair, esc, DMG, CMPV } = ctx;
  const hlas = COMPETITORS.find((c) => c.name === 'Hlas');
  const fmt = (n, cs) => (cs ? n.toFixed(2).replace('.', ',') : n.toFixed(2));
  const csBase = '/srovnani/';
  const enBase = '/en/compare/';
  const cta = (cs) => `<p class="doc-cta"><a class="btn btn-light" href="${DMG}" data-ev="download-mac">${cs ? 'Stáhnout Hlas zdarma' : 'Download Hlas for free'}</a> <a class="btn btn-glass" href="${cs ? '/#pricing' : '/en/#pricing'}">${cs ? 'Hlas Cloud za 35 € ročně' : 'Hlas Cloud, €35 a year'}</a></p>`;

  for (const v of VS) {
    const c = COMPETITORS.find((x) => x.name === v.key);
    const year = num(c.year);
    const save = Math.round(((year - HLAS_YEAR) / year) * 100);
    const once = /jednou/.test(c.year); // one-time licence: compare free local use, not yearly price
    for (const code of ['cs', 'en']) {
      const cs = code === 'cs';
      const row = (label, a, b) => (b == null ? '' : `<tr><th scope="row">${label}</th><td>${a}</td><td>${b}</td></tr>`);
      const table = `<div class="doc-table"><table><thead><tr><th></th><th>Hlas</th><th>${esc(v.key)}</th></tr></thead><tbody>
${row(cs ? 'Zdarma' : 'Free', esc(hlas.free[code]), esc(c.free[code]))}
${row(cs ? 'Placený tarif' : 'Paid plan', esc(hlas.paid[code]), esc(c.paid[code]))}
${row(cs ? 'Za rok v € bez DPH' : 'Per year in € without VAT', fmt(HLAS_YEAR, cs), esc(cs ? c.year : c.yearEn))}
${row(cs ? 'Přepis offline' : 'Offline transcription', cs ? 'Ano, whisper.cpp v počítači' : 'Yes, whisper.cpp on your computer', v.offline ? esc(v.offline[code]) : null)}
${row(cs ? 'Poznámka' : 'Note', esc(hlas.note[code]), esc(c.note[code]))}
</tbody></table></div>`;
      const items = cs ? [
        [`Je Hlas levnější než ${v.key}?`, once ? `Pro lokální diktování ano: Hlas je zdarma bez limitu, ${v.key} stojí ${c.paid.cs}. Jednorázová licence se vyplatí, když chcete zaplatit jen jednou. Hlas Cloud za 35 € ročně je pro ty, kdo nechtějí stahovat model ani řešit API klíče.` : `Ano. Hlas Cloud stojí 35 € ročně bez DPH, ${v.key} vychází na ${c.year} € ročně (${c.paid.cs}). To je zhruba o ${save} % méně. Lokální přepis v Hlasu je navíc zdarma bez limitu.`],
        [`Kdy je lepší ${v.key}?`, v.better.cs],
        [`Proč přejít na Hlas?`, v.pickHlas.cs],
        ['Umí Hlas česky?', 'Ano. Čeština, slovenština a angličtina mají v Hlasu vlastní ladění (slovník, mluvené symboly, zalomení řádků). Dalších 60+ jazyků běží přes Whisper large-v3 bez dalšího ladění.'],
      ] : [
        [`Is Hlas cheaper than ${v.key}?`, once ? `For local dictation, yes: Hlas is free with no limit, ${v.key} costs ${c.paid.en}. A one-time licence pays off if you want to pay only once. Hlas Cloud at €35 a year is for people who do not want to download a model or deal with API keys.` : `Yes. Hlas Cloud is €35 a year without VAT, ${v.key} comes to €${c.yearEn} a year (${c.paid.en}). That is about ${save} % less. Local transcription in Hlas is free with no limit on top.`],
        [`When is ${v.key} the better pick?`, v.better.en],
        ['Why switch to Hlas?', v.pickHlas.en],
        ['Which languages does Hlas support?', 'Czech, Slovak and English get extra tuning (vocabulary, spoken symbols, line breaks). 60+ more languages run through Whisper large-v3 without extra tuning.'],
      ];
      shell({
        code,
        path: (cs ? csBase : enBase) + v.slug + '/',
        alternates: pair(csBase + v.slug + '/', enBase + v.slug + '/'),
        title: cs ? `Hlas vs ${v.key}: cena a funkce 2026, levnější alternativa | Hlas` : `Hlas vs ${v.key}: price and features 2026, cheaper alternative | Hlas`,
        description: once ? (cs ? `${v.key} za ${c.paid.cs}, nebo Hlas zdarma pro lokální diktování a Hlas Cloud za 35 € ročně. Srovnání ceny, offline režimu a kdy je lepší která aplikace.` : `${v.key} at ${c.paid.en}, or Hlas free for local dictation and Hlas Cloud at €35 a year. Price, offline mode and when each app is the better pick.`) : (cs ? `${v.key} za ${c.year} € ročně, nebo Hlas Cloud za 35 € (o ${save} % méně) a lokální diktování zdarma. Srovnání ceny, offline režimu a kdy je lepší která aplikace.` : `${v.key} at €${c.yearEn} a year, or Hlas Cloud at €35 (${save} % less) plus free local dictation. Price, offline mode and when each app is the better pick.`),
        h1: `Hlas vs ${v.key}`,
        lead: once ? (cs ? `${esc(v.key)} stojí <b>${esc(c.paid.cs)}</b>. Hlas je pro lokální diktování <b>zdarma</b> a neomezený cloud bez klíčů stojí 35 € ročně. Níž je férové srovnání včetně toho, kdy je lepší ${esc(v.key)}.` : `${esc(v.key)} costs <b>${esc(c.paid.en)}</b>. Hlas is <b>free</b> for local dictation, and unlimited cloud without keys is €35 a year. Below is a fair comparison, including when ${esc(v.key)} is the better pick.`) : cs ? `Hlas Cloud stojí <b>35 € ročně</b>, ${esc(v.key)} vychází na <b>${esc(c.year)} € ročně</b>. To je zhruba o ${save} % méně, a lokální diktování v Hlasu je navíc zdarma. Níž je férové srovnání včetně toho, kdy je lepší ${esc(v.key)}.` : `Hlas Cloud costs <b>€35 a year</b>, ${esc(v.key)} comes to <b>€${esc(c.yearEn)} a year</b>. That is about ${save} % less, and local dictation in Hlas is free on top. Below is a fair comparison, including when ${esc(v.key)} is the better pick.`,
        body: (() => {
          const nm = (x) => (typeof x === 'string' ? x : x[code]);
          const rows = [
            { name: cs ? 'Hlas lokálně' : 'Hlas local', me: true, y: 0 },
            { name: 'Hlas Cloud', me: true, y: HLAS_YEAR },
            ...v.plans.map((pl) => ({ name: nm(pl.n), y: pl.y, o: pl.o })),
          ];
          const main = v.plans[0];
          const otherBig = main.o != null ? `${eur(main.o, cs)} €` : `${eur(main.y, cs)} €`;
          const otherSub = main.o != null ? (cs ? 'jednou za licenci' : 'once, for a licence') : (cs ? 'ročně' : 'a year');
          const saveYear = main.y ? main.y - HLAS_YEAR : 0;
          const hasOnce = v.plans.some((pl) => pl.o != null);
          const off = v.offline ? (/^(Ano|Yes)/.test(v.offline[code]) ? ['yes', v.offline[code]] : ['no', v.offline[code]]) : ['dash', cs ? 'Výrobce neuvádí' : 'Not stated by the maker'];
          const feats = [
            [cs ? 'Přepis offline, zvuk neopustí počítač' : 'Offline, audio stays on your computer', ['yes', cs ? 'Ano, whisper.cpp' : 'Yes, whisper.cpp'], off],
            [cs ? 'Bezplatná verze' : 'Free version', ['yes', cs ? 'Ano, bez limitu' : 'Yes, no limit'], ['yes', c.free[code]]],
            [cs ? 'Jednorázová licence' : 'One-time licence', ['dash', cs ? 'Není potřeba, lokálně zdarma' : 'Not needed, free locally'], hasOnce ? ['yes', v.plans.filter((pl) => pl.o != null).map((pl) => eur(pl.o, cs) + ' €').join(', ')] : ['dash', cs ? 'Jen předplatné' : 'Subscription only']],
            [cs ? 'Cloud za rok' : 'Cloud per year', ['yes', '35 €'], v.plans.some((pl) => pl.y) ? ['yes', eur(v.plans.find((pl) => pl.y).y, cs) + ' €'] : ['dash', cs ? 'Nenabízí předplatné' : 'No subscription']],
            [cs ? 'Ladění pro češtinu a slovenštinu' : 'Tuned for Czech and Slovak', ['yes', cs ? 'Slovník, symboly, zalomení' : 'Vocabulary, symbols, line breaks'], ['dash', cs ? 'Obecný model' : 'General model']],
          ];
          return `<div class="vs-cards">
  <div class="vs-card me"><p class="vs-k">Hlas</p><p class="vs-big">0 €</p><p class="vs-sub">${cs ? 'lokálně, navždy' : 'locally, forever'}</p><p class="vs-alt">Hlas Cloud <b>35 €</b> ${cs ? 'ročně' : 'a year'}</p></div>
  <span class="vs-badge">VS</span>
  <div class="vs-card"><p class="vs-k">${esc(v.key)}</p><p class="vs-big">${otherBig}</p><p class="vs-sub">${otherSub}</p><p class="vs-alt">${esc(c.free[code])}</p></div>
</div>
${saveYear > 0 ? `<p class="vs-save">${cs ? `S Hlas Cloud ušetříš <b>${eur(saveYear, cs)} € ročně</b>, za 3 roky <b>${eur(saveYear * 3, cs)} €</b>.` : `With Hlas Cloud you save <b>€${eur(saveYear, cs)} a year</b>, <b>€${eur(saveYear * 3, cs)}</b> over 3 years.`}</p>` : ''}
<h2>${cs ? 'Kolik zaplatíš celkem' : 'What you pay in total'}</h2>
${costChart(rows, cs, { title: cs ? `Hlas a ${v.key}: celkové náklady` : `Hlas and ${v.key}: total cost` })}
<h2>${cs ? 'Co umí' : 'What you get'}</h2>
${featureGrid(v.key, feats, cs)}
<h2>${cs ? 'Jak Hlas funguje' : 'How Hlas works'}</h2>
${howItWorks(cs)}
<h2>${cs ? 'Kterou vybrat' : 'Which one to pick'}</h2>
${verdict(v.key, v.better[code], v.pickHlas[code], cs)}
<h2>${cs ? 'Časté otázky' : 'Questions'}</h2>
${faqAccordion(items)}
<details class="more"><summary>${cs ? 'Podrobná tabulka a zdroje cen' : 'Detailed table and price sources'}</summary>${table}
<p class="doc-note">${cs ? `Ceny bez DPH z oficiálních ceníků, ověřeno 14. a 15. 11. 2026. Přepočet kurzem ECB z 13. 11. 2026, 1 $ = 0,90481 €. <a href="${c.url}" rel="nofollow noopener">Ceník ${esc(v.key)}</a>.` : `Prices without VAT from the official pricing pages, checked 14-15 November 2026. Converted at the ECB rate of 13 November 2026, $1 = €0.90481. <a href="${c.url}" rel="nofollow noopener">${esc(v.key)} pricing</a>.`}</p></details>
${ctaBand(cs, DMG)}
<h2>${cs ? 'Další srovnání' : 'More comparisons'}</h2>
<div class="chips">${VS.filter((x) => x !== v).map((x) => `<a class="chip" href="${(cs ? csBase : enBase) + x.slug}/">Hlas vs ${esc(x.key)}</a>`).join('')}<a class="chip" href="${cs ? '/nejlevnejsi-diktovani/' : '/en/cheapest-dictation-app/'}">${cs ? 'Nejlevnější diktování' : 'Cheapest dictation'}</a><a class="chip" href="${cs ? csBase : enBase}">${cs ? 'Všechny aplikace' : 'All apps'}</a></div>
<script src="/compare.js?v=${CMPV}" defer></script>`;
        })(),
        jsonld: [faqLd(items)],
      });
    }
  }

  /* ---------- cheapest dictation app ---------- */
  for (const code of ['cs', 'en']) {
    const cs = code === 'cs';
    const groups = [
      [cs ? 'Zdarma' : 'Free', [
        ['Hlas', cs ? 'Lokální přepis bez limitu, nebo vlastní API klíč. Mac a Windows.' : 'Local transcription with no limit, or your own API key. Mac and Windows.', '0'],
        ['Šeptem', cs ? 'Zdarma, platíte jen Groqu za vlastní klíč. Česká, beta, Mac.' : 'Free, you only pay Groq for your own key. Czech, beta, Mac.', '0'],
        ['VoiceInk', cs ? 'Open source, když si ho sestavíte sami.' : 'Open source if you build it yourself.', '0'],
      ]],
      [cs ? 'Jednorázově' : 'One-time', [
        ['VoiceInk', cs ? '25 $ za 1 Mac' : '$25 for 1 Mac', cs ? '22,62' : '22.62'],
        ['Spokenly Local+', cs ? '29 $ jednou' : '$29 once', cs ? '26,24' : '26.24'],
        ['MacWhisper Pro', cs ? '64 € jednou, hlavně přepis souborů' : '€64 once, mainly file transcription', cs ? '64,00' : '64.00'],
        ['Superwhisper', cs ? '249,99 $ doživotně' : '$249.99 lifetime', cs ? '226,19' : '226.19'],
      ]],
      [cs ? 'Předplatné za rok' : 'Subscription per year', [
        ['Hlas Cloud', cs ? 'Neomezeně (férově 3 h denně), bez klíčů a modelu' : 'Unlimited (fair use 3 h a day), no keys or model', cs ? '35,00' : '35.00'],
        ['Superwhisper Pro', '84,99 $', cs ? '76,90' : '76.90'],
        ['Aqua Voice Pro', cs ? '10 $ měsíčně ročně' : '$10 a month yearly', cs ? '108,58' : '108.58'],
        ['Wispr Flow', cs ? '12 $ měsíčně ročně' : '$12 a month yearly', cs ? '130,29' : '130.29'],
        ['Willow Pro', cs ? '12 $ měsíčně ročně' : '$12 a month yearly', cs ? '130,29' : '130.29'],
        ['Spokenly Pro', cs ? '144 $ ročně' : '$144 a year', cs ? '130,29' : '130.29'],
      ]],
    ];
    const tables = groups.map(([label, rows]) => `<h2>${esc(label)}</h2><div class="doc-table"><table><thead><tr><th>${cs ? 'Aplikace' : 'App'}</th><th>${cs ? 'Co dostanete' : 'What you get'}</th><th>${cs ? '€ bez DPH' : '€ without VAT'}</th></tr></thead><tbody>${rows.map(([n, d, p]) => `<tr${n.startsWith('Hlas') ? ' class="me"' : ''}><th scope="row">${esc(n)}</th><td>${esc(d)}</td><td>${esc(p)}</td></tr>`).join('')}</tbody></table></div>`).join('\n');
    const items = cs ? [
      ['Jaká je nejlevnější aplikace na diktování?', 'Úplně zdarma je lokální diktování: Hlas (Mac a Windows) přepisuje přes Whisper přímo v počítači bez limitu a bez účtu. Nejlevnější neomezené předplatné bez API klíčů je Hlas Cloud za 35 € ročně. Z jednorázových licencí je nejlevnější VoiceInk za 25 $.'],
      ['Jde diktovat česky zdarma?', 'Ano. Hlas je zdarma a čeština v něm má vlastní ladění: primovací prompty, slovník, mluvené symboly a zalomení řádků. Lokální model funguje i bez internetu.'],
      ['Kolik stojí přepis přes vlastní API klíč?', 'Groq účtuje model whisper-large-v3-turbo asi 0,04 $ za hodinu zvuku. Hodina diktování denně tak vyjde zhruba na 1,20 $ měsíčně. Hlas vlastní klíč Groq i OpenAI podporuje zdarma.'],
      ['Proč je Hlas Cloud tak levný?', 'Hlas je malá nativní aplikace bez vlastní infrastruktury navíc: zvuk jde přes náš server na Cloudflare rovnou ke Groq. Nic neukládáme a neplatíme za drahé vlastní modely, takže cena může zůstat nízko.'],
    ] : [
      ['What is the cheapest dictation app?', 'Fully free is local dictation: Hlas (Mac and Windows) transcribes with Whisper on your computer, with no limit and no account. The cheapest unlimited subscription without API keys is Hlas Cloud at €35 a year. The cheapest one-time licence is VoiceInk at $25.'],
      ['Is there free speech to text for Mac and Windows?', 'Yes. Hlas is free for local use on Mac and Windows and works offline. Czech, Slovak and English get extra tuning; 60+ more languages run through Whisper large-v3.'],
      ['How much does transcription with my own API key cost?', 'Groq charges about $0.04 per hour of audio for whisper-large-v3-turbo. An hour of dictation a day comes to roughly $1.20 a month. Hlas supports your own Groq or OpenAI key for free.'],
      ['Why is Hlas Cloud so cheap?', 'Hlas is a small native app with no extra infrastructure: audio goes through our server on Cloudflare straight to Groq. We store nothing and do not pay for expensive custom models, so the price can stay low.'],
    ];
    shell({
      code,
      path: cs ? '/nejlevnejsi-diktovani/' : '/en/cheapest-dictation-app/',
      alternates: pair('/nejlevnejsi-diktovani/', '/en/cheapest-dictation-app/'),
      title: cs ? 'Nejlevnější aplikace na diktování a přepis hlasu 2026 | Hlas' : 'Cheapest dictation and speech-to-text app 2026 | Hlas',
      description: cs ? 'Diktování zdarma, jednorázově, nebo předplatné? Srovnání cen Hlas, Superwhisper, Wispr Flow, VoiceInk, MacWhisper a dalších. Nejlevnější neomezený cloud: 35 € ročně.' : 'Free, one-time or subscription? Prices of Hlas, Superwhisper, Wispr Flow, VoiceInk, MacWhisper and others. Cheapest unlimited cloud: €35 a year.',
      h1: cs ? 'Nejlevnější aplikace na diktování' : 'The cheapest dictation app',
      lead: cs ? 'Diktovat jde <b>úplně zdarma</b> (lokální Whisper), <b>jednou za licenci</b>, nebo <b>předplatným</b>. Nejlevnější neomezený cloud bez API klíčů je Hlas Cloud za 35 € ročně. Tady jsou všechny možnosti seřazené podle ceny.' : 'You can dictate <b>for free</b> (local Whisper), <b>with a one-time licence</b> or <b>on a subscription</b>. The cheapest unlimited cloud without API keys is Hlas Cloud at €35 a year. Here are all the options, sorted by price.',
      body: `<div class="stats3">
  <div class="st me"><b>0 €</b><span>${cs ? 'Nejlevnější vůbec: lokální diktování v Hlasu, bez limitu' : 'Cheapest of all: local dictation in Hlas, no limit'}</span></div>
  <div class="st"><b>${cs ? '22,62 €' : '€22.62'}</b><span>${cs ? 'Nejlevnější jednorázová licence: VoiceInk (25 $)' : 'Cheapest one-time licence: VoiceInk ($25)'}</span></div>
  <div class="st me"><b>${cs ? '35 € / rok' : '€35 / year'}</b><span>${cs ? 'Nejlevnější neomezený cloud bez API klíčů: Hlas Cloud' : 'Cheapest unlimited cloud without API keys: Hlas Cloud'}</span></div>
</div>
<h2>${cs ? 'Všechny aplikace podle ceny' : 'Every app by price'}</h2>
${costChart([
  { name: cs ? 'Hlas lokálně' : 'Hlas local', me: true, y: 0 },
  { name: 'Hlas Cloud', me: true, y: 35 },
  { name: 'VoiceInk', o: 22.62 }, { name: 'Spokenly Local+', o: 26.24 }, { name: 'MacWhisper Pro', o: 64 },
  { name: cs ? 'Superwhisper doživotně' : 'Superwhisper lifetime', o: 226.19 }, { name: 'Superwhisper Pro', y: 76.9 },
  { name: 'Aqua Voice Pro', y: 108.58 }, { name: 'Wispr Flow', y: 130.29 }, { name: 'Willow Pro', y: 130.29 }, { name: 'Spokenly Pro', y: 130.29 },
], cs, { title: cs ? 'Celkové náklady podle aplikace' : 'Total cost by app', start: 3 })}
<h2>${cs ? 'Vlastní klíč, nebo Hlas Cloud?' : 'Own key or Hlas Cloud?'}</h2>
<p>${cs ? 'Vlastní API klíč je při běžném diktování levnější než jakékoli předplatné. Hlas Cloud se vyplatí, když diktuješ hodně (od zhruba 2,7 hodiny denně je levnější) nebo nechceš řešit klíče.' : 'Your own API key is cheaper than any subscription for everyday dictation. Hlas Cloud pays off when you dictate a lot (from about 2.7 hours a day it is cheaper) or do not want to deal with keys.'}</p>
${keyCalculator(cs)}
<h2>${cs ? 'Jak Hlas funguje' : 'How Hlas works'}</h2>
${howItWorks(cs)}
<h2>${cs ? 'Časté otázky' : 'Questions'}</h2>
${faqAccordion(items)}
<details class="more"><summary>${cs ? 'Tabulky podle typu licence a zdroje cen' : 'Tables by licence type and price sources'}</summary>${tables}
<p class="doc-note">${cs ? 'Ceny bez DPH z oficiálních ceníků, ověřeno 14. a 15. 11. 2026, přepočet kurzem ECB z 13. 11. 2026 (1 $ = 0,90481 €).' : 'Prices without VAT from the official pricing pages, checked 14-15 November 2026, converted at the ECB rate of 13 November 2026 ($1 = €0.90481).'}</p></details>
${ctaBand(cs, DMG)}
<h2>${cs ? 'Srovnání po jednom' : 'Head to head'}</h2>
<div class="chips">${VS.map((v) => `<a class="chip" href="${(cs ? csBase : enBase) + v.slug}/">Hlas vs ${esc(v.key)}</a>`).join('')}</div>
<script src="/compare.js?v=${CMPV}" defer></script>`,
      jsonld: [faqLd(items)],
    });
  }
}

export const vsLinks = (cs) => `<h2>${cs ? 'Srovnání po jednom' : 'Head to head'}</h2>
<ul>${VS.map((v) => `<li><a href="${(cs ? '/srovnani/' : '/en/compare/') + v.slug}/">Hlas vs ${v.key}</a></li>`).join('')}<li><a href="${cs ? '/nejlevnejsi-diktovani/' : '/en/cheapest-dictation-app/'}">${cs ? 'Nejlevnější aplikace na diktování' : 'The cheapest dictation app'}</a></li></ul>`;
