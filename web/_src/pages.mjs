import { vsPages, vsLinks } from './vs.mjs';
// Content pages (Czech and English). Every page answers its question in the
// first sentence under each heading, so people and AI assistants can quote it.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// Prices checked on 15 November 2026 on each vendor's own pricing page. ECB rate 13 November 2026: $1 = €0.90481.
const COMPETITORS = [
  { name: 'Hlas', free: { cs: 'Lokální přepis i vlastní klíče, bez limitu', en: 'Local transcription and your own keys, no limit' }, paid: { cs: 'Hlas Cloud 35 € ročně + DPH', en: 'Hlas Cloud €35 a year + VAT' }, year: '35,00', yearEn: '35.00', note: { cs: 'Bez klíčů a stahování modelu, férové užívání 3 h denně. Mac a Windows (beta).', en: 'No keys or model download, fair use 3 h a day. Mac and Windows (beta).' }, url: '/' },
  { name: 'Superwhisper', free: { cs: 'Neomezený lokální Whisper, 3 000 slov Pro zdarma', en: 'Unlimited local Whisper, 3,000 Pro words free' }, paid: { cs: '8,49 $ měsíčně, 84,99 $ ročně, 249,99 $ jednou', en: '$8.49 a month, $84.99 a year, $249.99 once' }, year: '76,90', yearEn: '76.90', note: { cs: 'Vrácení do 30 dní, studenti a neziskovky 40 %.', en: '30-day refund, 40 % off for students and nonprofits.' }, url: 'https://superwhisper.com/docs/billing/plans' },
  { name: 'Wispr Flow', free: { cs: 'Free s týdenními limity', en: 'Free plan with weekly limits' }, paid: { cs: '15 $ měsíčně, 12 $ měsíčně při roční platbě', en: '$15 a month, $12 a month billed yearly' }, year: '130,29', yearEn: '130.29', note: { cs: 'Studenti 50 %, cloudová služba.', en: '50 % off for students, cloud service.' }, url: 'https://wisprflow.ai/pricing' },
  { name: 'Willow', free: { cs: 'Zkušební verze', en: 'Trial' }, paid: { cs: 'Pro 12 $ měsíčně při roční platbě', en: 'Pro $12 a month billed yearly' }, year: '130,29', yearEn: '130.29', note: { cs: 'Cena ověřena 14. 11. 2026.', en: 'Price checked 14 November 2026.' }, url: 'https://willowvoice.com' },
  { name: 'Aqua Voice', free: { cs: '2 000 slov', en: '2,000 words' }, paid: { cs: 'Pro 10 $ měsíčně při roční platbě nebo 12 $ měsíčně, Max 19 $ nebo 24 $', en: 'Pro $10 a month billed yearly or $12 monthly, Max $19 or $24' }, year: '108,58', yearEn: '108.58', note: { cs: 'Studenti 70 %.', en: '70 % off for students.' }, url: 'https://withaqua.com/pricing' },
  { name: 'Spokenly', free: { cs: 'Lokální modely, vlastní klíče', en: 'Local models, your own keys' }, paid: { cs: 'Local+ 29 $ jednou, Pro 12 $ měsíčně (144 $ ročně)', en: 'Local+ $29 once, Pro $12 a month ($144 a year)' }, year: '130,29 (Pro), 26,24 jednou', yearEn: '130.29 (Pro), 26.24 once', note: { cs: 'Mac, Windows, Linux, iOS, Android.', en: 'Mac, Windows, Linux, iOS, Android.' }, url: 'https://spokenly.app/cs' },
  { name: 'VoiceInk', free: { cs: 'Open source', en: 'Open source' }, paid: { cs: '25 $ jednou (1 Mac), 39 $ (2), 49 $ (3)', en: '$25 once (1 Mac), $39 (2), $49 (3)' }, year: '22,62 jednou', yearEn: '22.62 once', note: { cs: 'Apple Silicon, macOS 14.4+, vrácení do 14 dní.', en: 'Apple Silicon, macOS 14.4+, 14-day refund.' }, url: 'https://tryvoiceink.com/' },
  { name: 'MacWhisper', free: { cs: 'Zdarma verze', en: 'Free version' }, paid: { cs: 'Pro 64 € jednou', en: 'Pro €64 once' }, year: '64,00 jednou', yearEn: '64.00 once', note: { cs: 'Důraz na přepis souborů a schůzek.', en: 'Focused on transcribing files and meetings.' }, url: 'https://www.macwhisper.com' },
  { name: 'Šeptem', free: { cs: 'Zdarma bez časového limitu', en: 'Free, no time limit' }, paid: { cs: 'Žádný, platíte Groqu přímo svým klíčem', en: 'None, you pay Groq directly with your key' }, year: '0', yearEn: '0', note: { cs: 'Česká, beta, bez notarizace, má zápisy ze schůzek.', en: 'Czech, beta, not notarized, has meeting notes.' }, url: 'https://septem.inflexion.cz/' },
];

const CSS_DOC = '';

export function contentPages(ctx) {
  const { locales, head, footer, langMenu, homePath, LANGS, SITE, UPDATED, GITHUB, DMG, esc, logo } = ctx;
  const pages = [];

  function shell({ code, path, title, description, h1, lead, body, alternates, jsonld = [] }) {
    const t = locales[code];
    const hreflang = code === 'cs' ? 'cs' : 'en';
    const crumbs = { '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: [{ '@type': 'ListItem', position: 1, name: 'Hlas', item: `${SITE}${homePath(code)}` }, { '@type': 'ListItem', position: 2, name: h1, item: `${SITE}${path}` }] };
    const html = `${head({ code, hreflang, dir: 'ltr', title, description, path, alternates, jsonld: [crumbs, ...jsonld] })}
<header class="nav scrolled" id="nav">
  <a class="brand" href="${homePath(code)}" aria-label="Hlas">${logo()}<span>HLAS</span></a>
  <nav class="nav-links"><a href="${homePath(code)}#features">${esc(t.nav.features)}</a><a href="${homePath(code)}#pricing">${esc(t.nav.pricing)}</a></nav>
  ${langMenu(code, locales, t.nav.language)}
  <a class="btn btn-light btn-sm" href="${DMG}">${esc(t.nav.download)}</a>
</header>
<main class="doc wrap">
  <p class="doc-crumb"><a href="${homePath(code)}">Hlas</a> / ${esc(h1)}</p>
  <h1>${esc(h1)}</h1>
  <p class="doc-lead">${lead}</p>
  ${body}
  <p class="doc-updated">${code === 'cs' ? 'Aktualizováno' : 'Updated'} ${code === 'cs' ? '15. 11. 2026' : '15 November 2026'}</p>
</main>
${footer(t, code)}
</body>
</html>
`;
    pages.push({ path, html, alternates });
  }
  const pair = (csPath, enPath) => [['cs', csPath], ['en', enPath], ['x-default', enPath]];
  const faqLd = (items) => ({ '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: items.map(([q, a]) => ({ '@type': 'Question', name: q, acceptedAnswer: { '@type': 'Answer', text: a.replace(/<[^>]+>/g, '') } })) });
  const qa = (items) => items.map(([q, a]) => `<h2>${esc(q)}</h2><p>${a}</p>`).join('\n');

  /* ---------- comparison ---------- */
  for (const code of ['cs', 'en']) {
    const cs = code === 'cs';
    const rows = COMPETITORS.map((c) => `<tr${c.name === 'Hlas' ? ' class="me"' : ''}><th scope="row">${c.url.startsWith('http') ? `<a href="${c.url}" rel="nofollow noopener">${esc(c.name)}</a>` : esc(c.name)}</th><td>${esc(c.free[code])}</td><td>${esc(c.paid[code])}</td><td>${esc(cs ? c.year : c.yearEn)}</td><td>${esc(c.note[code])}</td></tr>`).join('');
    const items = cs ? [
      ['Je Hlas nejlevnější diktovací aplikace?', 'Ne vždy. Hlas Cloud za 35 € ročně je levnější než roční předplatné Superwhisperu (76,90 €), Wispr Flow a Willow (130,29 €) i Aqua Voice (108,58 €). Jednorázové licence VoiceInk (22,62 €) a Spokenly Local+ (26,24 €) vyjdou levněji, a Šeptem i lokální Hlas jsou zdarma.'],
      ['Kdy je lepší Superwhisper?', 'Když chcete jednorázovou doživotní licenci, iOS aplikaci nebo módy s vlastními prompty. Hlas je menší (4 MB), v klidu bere méně paměti a česky má vlastní ladění.'],
      ['Kdy je lepší Wispr Flow?', 'Když potřebujete synchronizaci mezi více zařízeními a týmové funkce. Wispr Flow běží v cloudu, Hlas umí přepisovat i offline přímo v počítači.'],
      ['Kdy je lepší Šeptem?', 'Když chcete zápisy ze schůzek nebo Mac s Intelem. Hlas má lokální režim bez internetu, je podepsaný a notarizovaný Applem a běží i na Windows.'],
      ['Kdy je lepší MacWhisper?', 'Když hlavně přepisujete dlouhé nahrávky a schůzky. Hlas je stavěný na diktování do kurzoru, zvukové soubory umí do 10 minut.'],
    ] : [
      ['Is Hlas the cheapest dictation app?', 'Not always. Hlas Cloud at €35 a year costs less than the yearly plans of Superwhisper (€76.90), Wispr Flow and Willow (€130.29) and Aqua Voice (€108.58). One-time licences of VoiceInk (€22.62) and Spokenly Local+ (€26.24) are cheaper, and Šeptem and local Hlas are free.'],
      ['When is Superwhisper the better choice?', 'When you want a lifetime licence, an iOS app or modes with custom prompts. Hlas is smaller (4 MB), uses less memory when idle and has extra tuning for Czech and Slovak.'],
      ['When is Wispr Flow the better choice?', 'When you need sync across devices and team features. Wispr Flow runs in the cloud; Hlas can also transcribe offline on your computer.'],
      ['When is MacWhisper the better choice?', 'When you mostly transcribe long recordings and meetings. Hlas is built for dictating into the cursor and handles audio files up to 10 minutes.'],
    ];
    shell({
      code, path: cs ? '/srovnani/' : '/en/compare/', alternates: pair('/srovnani/', '/en/compare/'),
      title: cs ? 'Srovnání diktovacích aplikací pro Mac 2026: ceny | Hlas' : 'Mac dictation apps compared 2026: prices | Hlas',
      description: cs ? 'Hlas, Superwhisper, Wispr Flow, Willow, Aqua Voice, Spokenly, VoiceInk, MacWhisper a Šeptem: ceny, bezplatné verze a v čem je která lepší. Ověřeno 15. 11. 2026.' : 'Hlas, Superwhisper, Wispr Flow, Willow, Aqua Voice, Spokenly, VoiceInk, MacWhisper and Šeptem: prices, free plans and where each one wins. Checked 15 November 2026.',
      h1: cs ? 'Srovnání diktovacích aplikací pro Mac' : 'Mac dictation apps compared',
      lead: cs ? 'Hlas Cloud za 35 € ročně je o 54 až 73 % levnější než roční předplatné Superwhisperu, Wispr Flow a Willow. Jednorázové licence a bezplatné aplikace ale existují taky, proto je tu máme všechny.' : 'Hlas Cloud at €35 a year is 54 to 73 % cheaper than the yearly plans of Superwhisper, Wispr Flow and Willow. One-time licences and free apps exist too, so they are all listed here.',
      body: `<div class="doc-table"><table><thead><tr><th>${cs ? 'Aplikace' : 'App'}</th><th>${cs ? 'Zdarma' : 'Free'}</th><th>${cs ? 'Placený tarif' : 'Paid plan'}</th><th>${cs ? 'Za rok v €' : 'Per year in €'}</th><th>${cs ? 'Poznámka' : 'Note'}</th></tr></thead><tbody>${rows}</tbody></table></div>
<p class="doc-note">${cs ? 'Ceny bez DPH, načtené z oficiálních ceníků 15. 11. 2026 (Willow 14. 11. 2026). Přepočet kurzem ECB z 13. 11. 2026, 1 $ = 0,90481 €. Roční ekvivalent Wispr Flow a Spokenly Pro je 12 $ krát 12. Najdete-li chybu, napište nám na GitHub.' : 'Prices without VAT, taken from the official pricing pages on 15 November 2026 (Willow on 14 November 2026). Converted at the ECB rate of 13 November 2026, $1 = €0.90481. The yearly figure for Wispr Flow and Spokenly Pro is $12 times 12. Spot a mistake? Tell us on GitHub.'}</p>
${vsLinks(cs)}
${qa(items)}`,
      jsonld: [faqLd(items)],
    });
  }

  /* ---------- privacy ---------- */
  for (const code of ['cs', 'en']) {
    const cs = code === 'cs';
    const items = cs ? [
      ['Co Hlas posílá z počítače v lokálním režimu?', 'Nic. Přepis běží přes whisper.cpp přímo v počítači, bez účtu a bez telemetrie. Jedinou síťovou akcí je jednorázové stažení modelu a kontrola aktualizací přes Sparkle, na kterou se aplikace jednou zeptá.'],
      ['Co se děje s vlastním API klíčem?', 'Zvuk jde přímo k poskytovateli, kterého jste vybrali (Groq, OpenAI, Soniox nebo Fish Audio), a řídí se jeho podmínkami. Klíč je uložený v systémové klíčence a přes naše servery nejde.'],
      ['Co se děje s Hlas Cloud?', 'Zvuk jde z aplikace přes náš server na Cloudflare ke Groq, který ho přepíše a vrátí text. Náš server zvuk ani text neukládá. Ukládáme jen to, co je nutné pro předplatné: identifikátor zákazníka ve Stripe, e-mail, šifrovaný licenční klíč a počet sekund zvuku za den kvůli férovému užívání.'],
      ['Měříte návštěvnost?', 'Návštěvnost měří Cloudflare Web Analytics. Neukládá cookies ani IP adresu a nesleduje tě napříč weby. Navíc, když na webu klikneš na stažení nebo předplatné, náš server přičte jedničku k počítadlu tlačítka a jazyka stránky, bez jakéhokoli identifikátoru. Google Analytics a reklamní pixely (Google, Meta) se načtou jen tehdy, když jim v liště dole na stránce dáš souhlas; volbu změníš odkazem Cookies v patičce. U zkušební verze Hlas Cloud si aplikace vytvoří náhodné ID instalace, aby šla zkouška spustit jen jednou; ukládáme z něj jen otisk (hash). Stejný otisk slouží k limitu 5 počítačů na jedno předplatné.'],
      ['Kdo zpracovává údaje?', 'Správcem je Eden Makers s.r.o., IČO 24518344, Plzeňská 3352/156, 150 00 Praha. Zpracovateli jsou Stripe (platby a faktury), Cloudflare (server, databáze a měření návštěvnosti bez cookies) a Groq (přepis zvuku v Hlas Cloud). S tvým souhlasem také Google (Analytics, Ads) a Meta (reklamní pixel).'],
      ['Používá web cookies?', 'Bez tvého souhlasu ne: měření návštěvnosti přes Cloudflare cookies nepoužívá. Google Analytics a reklamní pixely, které cookies používají, se načtou jen se souhlasem. Platební stránka Stripe má vlastní podmínky.'],
    ] : [
      ['What does Hlas send from my computer in local mode?', 'Nothing. Transcription runs through whisper.cpp on your computer, with no account and no telemetry. The only network actions are the one-time model download and the Sparkle update check, which the app asks about once.'],
      ['What happens with my own API key?', 'Audio goes straight to the provider you picked (Groq, OpenAI, Soniox or Fish Audio) under their terms. The key is stored in the system keychain and never passes through our servers.'],
      ['What happens with Hlas Cloud?', 'Audio goes from the app through our server on Cloudflare to Groq, which transcribes it and returns the text. Our server stores neither the audio nor the text. We only keep what the subscription needs: the Stripe customer ID, your email, an encrypted licence key and the seconds of audio per day for fair use.'],
      ['Do you track visitors?', 'Visits are measured with Cloudflare Web Analytics. It sets no cookies, stores no IP address and does not follow you across sites. When you click download or subscribe, our server also adds one to a counter for that button and the page language, with no identifier. Google Analytics and ad pixels (Google, Meta) load only if you allow them in the bar at the bottom of the page; change your choice with the Cookies link in the footer. For the Hlas Cloud trial the app creates a random install ID so a trial can start only once; we keep only a hash of it. The same hash enforces the limit of 5 computers per subscription.'],
      ['Who processes the data?', 'The controller is Eden Makers s.r.o., company ID 24518344, Plzeňská 3352/156, 150 00 Prague, Czech Republic. Processors are Stripe (payments and invoices), Cloudflare (server, database and cookieless visit measurement) and Groq (audio transcription in Hlas Cloud). With your consent also Google (Analytics, Ads) and Meta (ad pixel).'],
      ['Does the website use cookies?', 'Not without your consent: the Cloudflare visit measurement uses no cookies. Google Analytics and ad pixels, which do use cookies, load only if you allow them. The Stripe checkout page has its own terms.'],
    ];
    shell({
      code, path: cs ? '/soukromi/' : '/en/privacy/', alternates: pair('/soukromi/', '/en/privacy/'),
      title: cs ? 'Soukromí: diktování offline bez účtu | Hlas' : 'Privacy: offline dictation without an account | Hlas',
      description: cs ? 'V lokálním režimu Hlas nic neposílá. S Hlas Cloud jde zvuk přes náš server ke Groq a neukládá se. Kdo je správce a zpracovatel.' : 'In local mode Hlas sends nothing. With Hlas Cloud, audio goes through our server to Groq and is not stored. Who controls and processes data.',
      h1: cs ? 'Soukromí' : 'Privacy',
      lead: cs ? 'Hlas má dvě vrstvy: lokální režim, ve kterém zvuk nikdy neopustí počítač, a Hlas Cloud, ve kterém se zvuk přepisuje u Groq a nikde se neukládá. Toto je srozumitelné shrnutí, plné zásady a obchodní podmínky připravujeme s právníkem.' : 'Hlas has two layers: local mode, where audio never leaves your computer, and Hlas Cloud, where audio is transcribed by Groq and stored nowhere. This is a plain-language summary; the full policy and terms are being prepared with a lawyer.',
      body: qa(items) + `<p><a href="${GITHUB}/blob/master/Resources/Legal/Privacy.txt">${cs ? 'Text zásad přibalený v aplikaci' : 'Policy text bundled in the app'}</a></p>`,
      jsonld: [faqLd(items)],
    });
  }

  /* ---------- FAQ ---------- */
  for (const code of ['cs', 'en']) {
    const cs = code === 'cs';
    const t = locales[code];
    const extra = cs ? [
      ['Potřebuju účet?', 'Pro lokální režim ne. Účet nepotřebuje ani Hlas Cloud: po zaplacení dostanete licenční klíč, který jedním kliknutím vložíte do aplikace.'],
      ['Jak se Hlas Cloud aktivuje?', 'Po platbě se otevře stránka s licenčním klíčem a tlačítkem Otevřít Hlas. Klíč se vloží do Nastavení a Hlas se přepne na Hlas Cloud. Předplatné spravujete v zákaznickém portálu Stripe.'],
      ['Funguje Hlas Cloud na Windows?', 'Ano, od verze 0.6.0. Jedna licence platí až na 5 počítačích, Mac i Windows dohromady.'],
      ['Je zdrojový kód veřejný?', 'Ano, celý zdrojový kód je na GitHubu. Licenci zdrojového kódu teprve upřesňujeme.'],
    ] : [
      ['Do I need an account?', 'Not for local mode. Hlas Cloud needs no account either: after payment you get a licence key that goes into the app with one click.'],
      ['How is Hlas Cloud activated?', 'After payment a page shows your licence key and an Open Hlas button. The key goes into Settings and Hlas switches to Hlas Cloud. Manage the subscription in the Stripe customer portal.'],
      ['Does Hlas Cloud work on Windows?', 'Yes, from version 0.6.0. One licence works on up to 5 computers, Mac and Windows together.'],
      ['Is the source code public?', 'Yes, the full source code is on GitHub. The source licence is still being finalised.'],
    ];
    const items = t.faq.items.map((i) => [i.q, i.a]).concat(extra);
    shell({
      code, path: cs ? '/faq/' : '/en/faq/', alternates: pair('/faq/', '/en/faq/'),
      title: cs ? 'Časté otázky: cena, soukromí, jazyky | Hlas' : 'FAQ: price, privacy, languages | Hlas',
      description: cs ? 'Odpovědi na otázky o Hlasu: cena a faktury, offline režim, RAM, Intel, Windows, Claude Code a Cursor, kam jde zvuk a jak neomezený je Hlas Cloud.' : 'Answers about Hlas: price and invoices, offline mode, RAM, Intel, Windows, Claude Code and Cursor, where audio goes and how unlimited Hlas Cloud is.',
      h1: cs ? 'Časté otázky' : 'Frequently asked questions',
      lead: cs ? 'Hlas je 4MB diktovací aplikace pro Mac a Windows. Zdarma přepisuje offline přímo v počítači, Hlas Cloud za 35 € ročně přepisuje bez klíčů a bez stahování modelu.' : 'Hlas is a 4 MB dictation app for Mac and Windows. For free it transcribes offline on your computer; Hlas Cloud at €35 a year transcribes without keys or a model download.',
      body: qa(items.map(([q, a]) => [q, esc(a)])),
      jsonld: [faqLd(items)],
    });
  }

  /* ---------- about ---------- */
  for (const code of ['cs', 'en']) {
    const cs = code === 'cs';
    const facts = cs ? [['Název', 'Hlas'], ['Verze', '0.5.0 ze 4. 11. 2026'], ['Systémy', 'macOS 15+ na Apple Silicon, Windows 10 a 11 (beta)'], ['Velikost', '4 MB, v klidu asi 60 MB RAM'], ['Cena', 'Zdarma, Hlas Cloud 35 € ročně + DPH'], ['Jazyky', 'Čeština, slovenština a angličtina s laděním, 60+ dalších přes Whisper'], ['Autor', 'Gedeon Drapák'], ['Firma', 'Eden Makers s.r.o., IČO 24518344, Praha'], ['Zdrojový kód', 'github.com/GedeonDrapak/hlas']]
      : [['Name', 'Hlas'], ['Version', '0.5.0, 4 November 2026'], ['Platforms', 'macOS 15+ on Apple Silicon, Windows 10 and 11 (beta)'], ['Size', '4 MB, about 60 MB RAM when idle'], ['Price', 'Free, Hlas Cloud €35 a year + VAT'], ['Languages', 'Czech, Slovak and English with extra tuning, 60+ more via Whisper'], ['Author', 'Gedeon Drapák'], ['Company', 'Eden Makers s.r.o., company ID 24518344, Prague'], ['Source code', 'github.com/GedeonDrapak/hlas']];
    const table = `<div class="doc-table"><table><tbody>${facts.map(([a, b]) => `<tr><th scope="row">${esc(a)}</th><td>${esc(b)}</td></tr>`).join('')}</tbody></table></div>`;
    shell({
      code, path: cs ? '/o-nas/' : '/en/about/', alternates: pair('/o-nas/', '/en/about/'),
      title: cs ? 'O Hlasu: kdo za ním stojí | Hlas' : 'About Hlas: who makes it | Hlas',
      description: cs ? 'Hlas vytvořil v Praze Gedeon Drapák, režisér a AI video expert, se studiem Eden Makers. Fakta o aplikaci, firmě a kontakt.' : 'Hlas is made in Prague by Gedeon Drapák, AI video expert and director, with the studio Eden Makers. Facts about the app, the company and contact.',
      h1: cs ? 'O Hlasu' : 'About Hlas',
      lead: cs ? 'Hlas vznikl, protože žádná diktovací aplikace neuměla pořádně česky. Postavil ho Gedeon Drapák v Praze a vydává ho firma Eden Makers s.r.o.' : 'Hlas exists because no dictation app handled Czech properly. Gedeon Drapák built it in Prague and Eden Makers s.r.o. publishes it.',
      body: `<h2>${cs ? 'Fakta na jednom místě' : 'Facts in one place'}</h2>${table}
<h2>${cs ? 'Kdo za Hlasem stojí?' : 'Who is behind Hlas?'}</h2><p>${cs ? 'Gedeon Drapák, AI video expert a režisér z Prahy (<a href="https://gedeondrapak.com">gedeondrapak.com</a>), a studio <a href="https://edenmakers.ai">Edenmakers</a>, které vytváří AI filmy a reklamy.' : 'Gedeon Drapák, an AI video expert and director from Prague (<a href="https://gedeondrapak.com">gedeondrapak.com</a>), and the studio <a href="https://edenmakers.ai">Edenmakers</a>, which makes AI films and ads.'}</p>
<h2>${cs ? 'Jak nás kontaktovat?' : 'How do I contact you?'}</h2><p>${cs ? `Chyby a nápady pište na <a href="${GITHUB}/issues">GitHub</a>. Fakturační údaje: Eden Makers s.r.o., IČO 24518344, DIČ CZ24518344, Plzeňská 3352/156, 150 00 Praha.` : `Report bugs and ideas on <a href="${GITHUB}/issues">GitHub</a>. Billing details: Eden Makers s.r.o., company ID 24518344, VAT ID CZ24518344, Plzeňská 3352/156, 150 00 Prague, Czech Republic.`}</p>`,
      jsonld: [{ '@context': 'https://schema.org', '@type': 'Organization', name: 'Eden Makers s.r.o.', url: 'https://edenmakers.ai', address: { '@type': 'PostalAddress', streetAddress: 'Plzeňská 3352/156', postalCode: '150 00', addressLocality: 'Praha', addressCountry: 'CZ' }, founder: { '@type': 'Person', name: 'Gedeon Drapák', url: 'https://gedeondrapak.com', jobTitle: 'AI Video Expert & Director' } }],
    });
  }

  /* ---------- press ---------- */
  for (const code of ['cs', 'en']) {
    const cs = code === 'cs';
    const quotes = cs ? ['Hlas je 4MB diktovací aplikace pro Mac a Windows, která píše česky s háčky a čárkami tam, kam míří kurzor.', 'Lokální režim je zdarma a funguje bez internetu. Hlas Cloud stojí 35 € ročně, o 54 až 73 % méně než roční předplatné Superwhisperu, Wispr Flow nebo Willow.', 'V klidu bere Hlas asi 60 MB RAM, 11 sekund řeči přepíše na Apple Silicon za 1,7 sekundy.']
      : ['Hlas is a 4 MB dictation app for Mac and Windows that types where your cursor is, with extra tuning for Czech and Slovak.', 'Local mode is free and works offline. Hlas Cloud costs €35 a year, 54 to 73 % less than the yearly plans of Superwhisper, Wispr Flow or Willow.', 'Idle, Hlas uses about 60 MB of RAM; on Apple Silicon it transcribes 11 seconds of speech in 1.7 seconds.'];
    shell({
      code, path: cs ? '/press/' : '/en/press/', alternates: pair('/press/', '/en/press/'),
      title: cs ? 'Press kit: fakta, citace a obrázky | Hlas' : 'Press kit: facts, quotes and images | Hlas',
      description: cs ? 'Vše pro novináře o Hlasu: jedna věta, klíčová čísla, citovatelné věty, obrázky a kontakt.' : 'Everything journalists need about Hlas: one-liner, key numbers, quotable lines, images and contact.',
      h1: cs ? 'Pro média' : 'Press kit',
      lead: cs ? 'Hlas je nejlehčí diktování pro Mac a Windows, které rozumí češtině: zdarma a offline, nebo v cloudu za 35 € ročně bez klíčů.' : 'Hlas is the lightest dictation app for Mac and Windows that understands Czech: free and offline, or in the cloud for €35 a year with no keys.',
      body: `<h2>${cs ? 'Citovatelné věty' : 'Quotable lines'}</h2><ul>${quotes.map((q) => `<li>${esc(q)}</li>`).join('')}</ul>
<h2>${cs ? 'Obrázky' : 'Images'}</h2><p><a href="/assets/og.jpg">${cs ? 'Náhledový obrázek 1200 x 630' : 'Preview image 1200 x 630'}</a> · <a href="/assets/hero.jpg">${cs ? 'Hlavní obrázek webu' : 'Website hero image'}</a></p>
<h2>${cs ? 'Kontakt' : 'Contact'}</h2><p>${cs ? 'Gedeon Drapák, <a href="https://gedeondrapak.com">gedeondrapak.com</a>. Novinky v aplikaci najdete v <a href="/changelog/">changelogu</a>.' : 'Gedeon Drapák, <a href="https://gedeondrapak.com">gedeondrapak.com</a>. App news is in the <a href="/changelog/">changelog</a>.'}</p>`,
    });
  }

  /* ---------- changelog (English, from CHANGELOG.md) ---------- */
  {
    const md = readFileSync(join(ROOT, 'CHANGELOG.md'), 'utf8');
    const html = md.split('\n').filter((l) => !l.startsWith('# ')).map((l) => {
      if (l.startsWith('## ')) return `<h2>${esc(l.slice(3))}</h2>`;
      if (l.startsWith('- ')) return `<li>${esc(l.slice(2)).replace(/`([^`]+)`/g, '<code>$1</code>')}</li>`;
      return '';
    }).join('\n').replace(/(<li>[\s\S]*?<\/li>)(?=\n<h2>|\s*$)/g, (m) => m).replace(/((?:<li>.*<\/li>\n?)+)/g, '<ul>$1</ul>');
    shell({
      code: 'en', path: '/changelog/', alternates: [['en', '/changelog/'], ['x-default', '/changelog/']],
      title: 'Changelog: what is new in Hlas',
      description: 'Every Hlas release with its changes: automatic updates, filler removal, spoken symbols, vocabulary, Windows and more.',
      h1: 'Changelog',
      lead: 'The current version is 0.5.0 from 4 November 2026. Every release is also on GitHub with its download.',
      body: html,
    });
  }

  /* ---------- languages hub ---------- */
  {
    const tuned = new Set(['cs', 'sk', 'en']);
    const rows = LANGS.filter(([c]) => locales[c]).map(([c, h]) => `<tr><th scope="row"><a href="${homePath(c)}" hreflang="${h}">${esc(locales[c].langName)}</a></th><td>${esc(locales[c].langNameEn)}</td><td>${tuned.has(c) ? 'Extra tuning (priming prompt)' : 'Whisper large-v3, no extra tuning yet'}</td><td>${esc(locales[c].meta.kw || locales[c].meta.title)}</td></tr>`).join('');
    shell({
      code: 'en', path: '/en/small-languages-dictation/', alternates: [['en', '/en/small-languages-dictation/'], ['x-default', '/en/small-languages-dictation/']],
      title: 'Dictation for smaller languages on Mac and Windows | Hlas',
      description: 'Hlas started with Czech and works in 60+ languages. See which languages have extra tuning, which run on plain Whisper large-v3, and help us test yours.',
      h1: 'Dictation for smaller languages',
      lead: 'Hlas was built in Prague for Czech, a language big dictation apps treat as an afterthought. Czech, Slovak and English have extra tuning; every other language below runs on Whisper large-v3 as is.',
      body: `<h2>Which languages does Hlas support?</h2><p>More than 60, everything Whisper large-v3 can transcribe. Each language below has its own page written natively, not machine-switched.</p>
<div class="doc-table"><table><thead><tr><th>Language</th><th>English name</th><th>Status</th><th>Page focus</th></tr></thead><tbody>${rows}</tbody></table></div>
<h2>Why are only three languages tuned?</h2><p>Tuning means a priming prompt and tests with native speakers, and we only ship it where we can check the result ourselves. If you speak one of these languages, <a href="${GITHUB}/issues">tell us on GitHub</a> how Hlas does and which words it gets wrong.</p>`,
    });
  }

  /* ---------- keyword landing pages ---------- */
  shell({
    code: 'cs', path: '/diktovani-cesky-mac/', alternates: [['cs', '/diktovani-cesky-mac/'], ['en', '/en/czech-dictation-mac/'], ['x-default', '/en/czech-dictation-mac/']],
    title: 'Jak diktovat česky na Macu: návod a aplikace | Hlas',
    description: 'Jak diktovat česky na Macu: vestavěné diktování v macOS, nebo Hlas s modelem Whisper, který funguje offline, píše diakritiku a zná váš slovník.',
    h1: 'Jak diktovat česky na Macu',
    lead: 'Na Macu můžete diktovat česky vestavěným diktováním v macOS, nebo aplikací Hlas, která přepisuje modelem Whisper přímo v počítači, i bez internetu, a píše do jakékoli aplikace.',
    body: `<h2>Jak zapnout vestavěné diktování v macOS?</h2><p>Nastavení systému, Klávesnice, Diktování: zapněte ho a jako jazyk přidejte češtinu. Diktování spustíte dvojím stiskem klávesy Fn nebo klávesou s mikrofonem.</p>
<h2>Jak diktovat česky s Hlasem?</h2><p><a href="${DMG}">Stáhněte Hlas</a>, při prvním spuštění povolte mikrofon a zpřístupnění a v průvodci vyberte lokální model. Pak podržte Fn, mluvte a pusťte: text přistane tam, kde máte kurzor.</p>
<h2>Proč nefunguje vestavěné diktování?</h2><p>Nejčastěji chybí oprávnění pro mikrofon, je obsazená klávesa Fn jinou zkratkou, nebo je jako vstup vybraný Bluetooth mikrofon, který při nahrávání přepne do horší kvality. Hlas nezávisí na systémovém diktování, takže funguje, i když vestavěné ne.</p>
<h2>Jak naučit diktování jména a značky?</h2><p>V Hlasu je přidejte do slovníku spolu s tím, jak je model slyší špatně, třeba Seedance a „sídens“. Od té doby je Hlas napíše správně.</p>
<h2>Funguje to bez internetu?</h2><p>S lokálním modelem ano. Model má 547 MB, stáhne se jednou a přepis pak běží celý ve vašem počítači.</p>`,
  });
  shell({
    code: 'en', path: '/en/czech-dictation-mac/', alternates: [['cs', '/diktovani-cesky-mac/'], ['en', '/en/czech-dictation-mac/'], ['x-default', '/en/czech-dictation-mac/']],
    title: 'How to dictate in Czech on a Mac | Hlas',
    description: 'Dictate in Czech on a Mac with built-in macOS dictation or with Hlas, which runs Whisper offline, keeps Czech diacritics and learns your vocabulary.',
    h1: 'How to dictate in Czech on a Mac',
    lead: 'You can dictate Czech on a Mac with built-in macOS dictation, or with Hlas, which transcribes with Whisper on your computer, also offline, and types into any app.',
    body: `<h2>Who is this for?</h2><p>Foreigners writing in Czech, companies with Czech teams and anyone who switches between Czech and English. Hlas keeps háčky and čárky in place thanks to a Czech priming prompt.</p>
<h2>How do I start?</h2><p><a href="${DMG}">Download Hlas</a>, allow the microphone and Accessibility, pick the local model, then hold Fn, speak and release.</p>
<h2>Can I mix Czech and English?</h2><p>Yes. Pin both languages or leave Hlas on auto-detect; English terms inside Czech sentences stay intact, and you can add names to the vocabulary.</p>`,
  });
  shell({
    code: 'cs', path: '/pro/programatory/', alternates: [['cs', '/pro/programatory/'], ['en', '/en/developers/'], ['x-default', '/en/developers/']],
    title: 'Diktování promptů do Claude Code a Cursoru česky | Hlas',
    description: 'Diktujte prompty do Claude Code, Cursoru a terminálu česky i anglicky. Mluvené symboly, slovník pro názvy knihoven a 60 MB RAM v klidu.',
    h1: 'Diktování pro programátory',
    lead: 'Hlas diktuje prompty do Claude Code, Cursoru, terminálu i ChatGPT, česky i anglicky, a mluvené symboly jako zavináč nebo podtržítko převede na znaky.',
    body: `<h2>Proč diktovat prompty?</h2><p>Mluvíte zhruba třikrát rychleji, než píšete, a delší prompty s kontextem dávají lepší výsledky. Hlas píše do kterékoli aplikace, kde je kurzor.</p>
<h2>Jak napsat názvy knihoven správně?</h2><p>Přidejte je do slovníku i s tím, jak je model slyší, třeba Kubernetes a „kubernetis“. Hlas je pak napíše přesně.</p>
<h2>Jaké symboly jde vyslovit?</h2><p>V Labs zapněte mluvené symboly: zavináč, podtržítko, lomítko, mřížka, závorky, dvojtečka a další, plus „tečka com“ pro domény. Funguje česky a anglicky.</p>
<h2>Zpomalí to počítač?</h2><p>Ne. V klidu Hlas bere asi 60 MB RAM a model se po 3 minutách ticha uvolní. S Hlas Cloud se žádný model nenačítá vůbec.</p>`,
  });
  shell({
    code: 'en', path: '/en/developers/', alternates: [['cs', '/pro/programatory/'], ['en', '/en/developers/'], ['x-default', '/en/developers/']],
    title: 'Dictate prompts into Claude Code and Cursor | Hlas',
    description: 'Dictate prompts into Claude Code, Cursor and the terminal. Spoken symbols, a vocabulary for library names and 60 MB of RAM when idle.',
    h1: 'Dictation for developers',
    lead: 'Hlas dictates prompts into Claude Code, Cursor, the terminal and ChatGPT, and turns spoken symbols like "at sign" or "underscore" into characters.',
    body: `<h2>Why dictate prompts?</h2><p>You speak about three times faster than you type, and longer prompts with context get better results. Hlas types into any app with a cursor.</p>
<h2>How do I get library names right?</h2><p>Add them to the vocabulary with how the model mishears them, for example Kubernetes and "cooper netties". Hlas then writes them exactly.</p>
<h2>Which symbols can I say?</h2><p>Turn on spoken symbols in Labs: at sign, underscore, slash, hashtag, parentheses, colon and more, plus "dot com" for domains. Works in English and Czech.</p>
<h2>Will it slow my machine down?</h2><p>No. Idle, Hlas uses about 60 MB of RAM and the model unloads after 3 minutes of silence. Hlas Cloud loads no model at all.</p>`,
  });
  shell({
    code: 'cs', path: '/diktovani-windows/', alternates: [['cs', '/diktovani-windows/'], ['x-default', '/diktovani-windows/']],
    title: 'Diktování česky na Windows: Hlas beta | Hlas',
    description: 'Hlas pro Windows 10 a 11 je v betě: lokální Whisper i vlastní API klíč. Co funguje, co zatím chybí a proč Windows varuje před instalátorem.',
    h1: 'Diktování česky na Windows',
    lead: 'Hlas pro Windows 10 a 11 je v betě. Umí lokální model Whisper i vlastní API klíč, Hlas Cloud zatím ne, a instalátor ještě není podepsaný.',
    body: `<h2>Proč Windows varuje před instalátorem?</h2><p>Instalátor zatím nemá podpis kódu, proto SmartScreen ukáže varování. Klikněte na Další informace a Přesto spustit. Podpis přidáme před veřejným startem.</p>
<h2>Co na Windows funguje?</h2><p>Diktování klávesovou zkratkou do jakékoli aplikace, lokální model Whisper, vlastní klíče Groq a OpenAI, slovník a historie. Aplikace je nativní, napsaná v Rustu.</p>
<h2>Funguje na Windows Hlas Cloud?</h2><p>Ano, od verze 0.6.0. V Nastavení na stránce Hlas Cloud spustíte 7denní zkoušku zdarma nebo vložíte licenční klíč. Jedna licence platí až na 5 počítačích.</p>
<p><a class="btn btn-light" href="${ctx.EXE}">Stáhnout Hlas pro Windows (beta)</a></p>`,
  });

  /* ---------- Slovak landing ---------- */
  if (locales.sk) {
    const t = locales.sk;
    const html = `${head({ code: 'sk', hreflang: 'sk', dir: 'ltr', title: 'Diktovanie po slovensky na Macu: návod | Hlas', description: 'Ako diktovať po slovensky na Macu: vstavané diktovanie v macOS alebo Hlas s modelom Whisper, ktorý funguje offline a má ladenie pre slovenčinu.', path: '/sk/diktovanie-slovensky-mac/', alternates: [['sk', '/sk/diktovanie-slovensky-mac/'], ['x-default', '/en/czech-dictation-mac/']] })}
<header class="nav scrolled" id="nav"><a class="brand" href="/sk/" aria-label="Hlas">${logo()}<span>HLAS</span></a><nav class="nav-links"><a href="/sk/#features">${esc(t.nav.features)}</a><a href="/sk/#pricing">${esc(t.nav.pricing)}</a></nav>${langMenu('sk', locales, t.nav.language)}<a class="btn btn-light btn-sm" href="${DMG}">${esc(t.nav.download)}</a></header>
<main class="doc wrap">
<p class="doc-crumb"><a href="/sk/">Hlas</a> / Diktovanie po slovensky na Macu</p>
<h1>Ako diktovať po slovensky na Macu</h1>
<p class="doc-lead">Na Macu môžete diktovať po slovensky vstavaným diktovaním v macOS alebo aplikáciou Hlas, ktorá prepisuje modelom Whisper priamo v počítači, aj bez internetu, a má pre slovenčinu vlastný úvodný prompt.</p>
<h2>Má Hlas ladenie pre slovenčinu?</h2><p>Áno. Slovenčina má rovnako ako čeština a angličtina vlastný úvodný prompt, ktorý drží diakritiku, čiarky a veľké písmená na mieste.</p>
<h2>Ako začať?</h2><p><a href="${DMG}">Stiahnite Hlas</a>, povoľte mikrofón a sprístupnenie a vyberte lokálny model. Potom podržte Fn, hovorte a pustite.</p>
<h2>Funguje to bez internetu?</h2><p>S lokálnym modelom áno. Model má 547 MB, stiahne sa raz a prepis potom beží celý vo vašom počítači.</p>
<p class="doc-updated">Aktualizované 15. 11. 2026</p>
</main>
${footer(t, 'sk')}
</body>
</html>
`;
    pages.push({ path: '/sk/diktovanie-slovensky-mac/', html, alternates: [['sk', '/sk/diktovanie-slovensky-mac/']] });
  }

  vsPages({ COMPETITORS, shell, qa, faqLd, pair, esc, DMG });
  return pages;
}
