// Static site generator for hlas.dev.
// Renders one native homepage per language from _src/locales/<code>.json,
// plus the Czech and English content pages, sitemap.xml, robots.txt and llms.txt.
// Run: node web/_src/build.mjs   (no dependencies)
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { contentPages } from './pages.mjs';
import { createHash } from 'node:crypto';

const SRC = dirname(fileURLToPath(import.meta.url));
const OUT = join(SRC, '..');
const SITE = 'https://hlas.dev';
const hashOf = (f) => createHash('sha256').update(readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', f))).digest('hex').slice(0, 8);
const CSSV = hashOf('styles.css');
const JSV = hashOf('app.js');
const ORBV = hashOf('orb.js');
const UPDATED = '2026-11-15';
const VERSION = '0.6.0';
const DMG = 'https://github.com/GedeonDrapak/hlas/releases/latest/download/Hlas-mac-arm64.dmg';
const EXE = 'https://github.com/GedeonDrapak/hlas/releases/latest/download/Hlas-windows-x64-setup.exe';
const CHECKOUT = 'https://buy.stripe.com/5kQ8wIdAe58W1YB1zI3Je00';
const EVENTS = 'https://api.hlas.dev/v1/event';
const PORTAL = 'https://billing.stripe.com/p/login/5kQ8wIdAe58W1YB1zI3Je00';
const GITHUB = 'https://github.com/GedeonDrapak/hlas';

// code, hreflang, text direction. Czech lives at the root, every other language in /<code>/.
export const LANGS = [
  ['cs', 'cs', 'ltr'], ['en', 'en', 'ltr'], ['sk', 'sk', 'ltr'], ['pl', 'pl', 'ltr'], ['hu', 'hu', 'ltr'],
  ['de', 'de', 'ltr'], ['fr', 'fr', 'ltr'], ['es', 'es', 'ltr'], ['pt', 'pt', 'ltr'], ['it', 'it', 'ltr'],
  ['nl', 'nl', 'ltr'], ['ro', 'ro', 'ltr'], ['uk', 'uk', 'ltr'], ['ru', 'ru', 'ltr'], ['bg', 'bg', 'ltr'],
  ['sr', 'sr-Latn', 'ltr'], ['hr', 'hr', 'ltr'], ['sl', 'sl', 'ltr'], ['el', 'el', 'ltr'], ['tr', 'tr', 'ltr'],
  ['sv', 'sv', 'ltr'], ['da', 'da', 'ltr'], ['nb', 'nb', 'ltr'], ['fi', 'fi', 'ltr'], ['lt', 'lt', 'ltr'],
  ['lv', 'lv', 'ltr'], ['et', 'et', 'ltr'], ['ca', 'ca', 'ltr'], ['ja', 'ja', 'ltr'], ['ko', 'ko', 'ltr'],
  ['zh', 'zh-Hans', 'ltr'], ['hi', 'hi', 'ltr'], ['bn', 'bn', 'ltr'], ['th', 'th', 'ltr'], ['vi', 'vi', 'ltr'],
  ['id', 'id', 'ltr'], ['ms', 'ms', 'ltr'], ['ar', 'ar', 'rtl'], ['he', 'he', 'rtl'], ['fa', 'fa', 'rtl'],
];
export const homePath = (code) => (code === 'cs' ? '/' : `/${code}/`);
const ogLocale = { cs: 'cs_CZ', en: 'en_US', sk: 'sk_SK', pl: 'pl_PL', hu: 'hu_HU', de: 'de_DE', fr: 'fr_FR', es: 'es_ES', pt: 'pt_BR', it: 'it_IT', nl: 'nl_NL', ro: 'ro_RO', uk: 'uk_UA', ru: 'ru_RU', bg: 'bg_BG', sr: 'sr_RS', hr: 'hr_HR', sl: 'sl_SI', el: 'el_GR', tr: 'tr_TR', sv: 'sv_SE', da: 'da_DK', nb: 'nb_NO', fi: 'fi_FI', lt: 'lt_LT', lv: 'lv_LV', et: 'et_EE', ca: 'ca_ES', ja: 'ja_JP', ko: 'ko_KR', zh: 'zh_CN', hi: 'hi_IN', bn: 'bn_BD', th: 'th_TH', vi: 'vi_VN', id: 'id_ID', ms: 'ms_MY', ar: 'ar_AR', he: 'he_IL', fa: 'fa_IR' };
// Scripts Satoshi does not cover get the system font stack.
const systemFont = new Set(['uk', 'ru', 'bg', 'el', 'ja', 'ko', 'zh', 'hi', 'bn', 'th', 'ar', 'he', 'fa', 'vi']);

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const strip = (s) => String(s).replace(/<[^>]+>/g, '');
const json = (o) => JSON.stringify(o).replace(/</g, '\\u003c');

export function loadLocales() {
  const out = {};
  for (const [code] of LANGS) {
    const p = join(SRC, 'locales', `${code}.json`);
    if (!existsSync(p)) continue;
    try { out[code] = JSON.parse(readFileSync(p, 'utf8')); } catch (e) { console.warn(`skip ${code}: ${e.message}`); }
  }
  return out;
}

const logo = (n = 22) => `<svg width="${n}" height="${n}" viewBox="0 0 34 34" aria-hidden="true"><rect x="4" y="9" width="7" height="16" rx="3.5" fill="#00E67A"/><rect x="15" y="3" width="7" height="28" rx="3.5" fill="#EDEDED"/><circle cx="29" cy="17" r="3.5" fill="#00E67A"/></svg>`;
const apple = `<svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.8-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7 2-1.1 2.8-2.3c.9-1.3 1.2-2.5 1.3-2.6-.1 0-2.5-1-2.5-3.8zM14.1 5.8c.6-.8 1.1-1.9 1-3-1 0-2.1.6-2.8 1.4-.6.7-1.2 1.8-1 2.9 1.1.1 2.2-.5 2.8-1.3z"/></svg>`;
const win = `<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 5.5l7.5-1v7.2H3zM11.5 4.3L21 3v8.7h-9.5zM3 12.7h7.5v7.2L3 18.8zM11.5 12.7H21V21l-9.5-1.3z"/></svg>`;

// Links in the footer and the language menu. Content pages only exist in cs and en.
export function siteLinks(code) {
  const cs = code === 'cs';
  return {
    compare: cs ? '/srovnani/' : '/en/compare/',
    privacy: cs ? '/soukromi/' : '/en/privacy/',
    faq: cs ? '/faq/' : '/en/faq/',
    about: cs ? '/o-nas/' : '/en/about/',
    press: cs ? '/press/' : '/en/press/',
    changelog: '/changelog/',
    languages: '/en/small-languages-dictation/',
  };
}

// Site name "Hlas" above the result in Google comes from this.
const WEBSITE_LD = { '@context': 'https://schema.org', '@type': 'WebSite', name: 'Hlas', alternateName: 'hlas.dev', url: 'https://hlas.dev/' };

export function head({ code, hreflang, dir, title, description, path, alternates, ogTitle, ogDescription, jsonld = [] }) {
  const alt = (alternates || []).map(([h, p]) => `<link rel="alternate" hreflang="${h}" href="${SITE}${p}">`).join('\n');
  return `<!doctype html>
<html lang="${hreflang}" dir="${dir}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<link rel="canonical" href="${SITE}${path}">
${alt}
<meta property="og:type" content="website">
<meta property="og:site_name" content="Hlas">
<meta property="og:url" content="${SITE}${path}">
<meta property="og:title" content="${esc(ogTitle || title)}">
<meta property="og:description" content="${esc(ogDescription || description)}">
<meta property="og:image" content="${SITE}/assets/${code === 'cs' || code === 'sk' ? 'og-cs.jpg' : 'og.jpg'}">
<meta property="og:image:alt" content="Hlas">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="${ogLocale[code] || 'en_US'}">
<meta name="twitter:card" content="summary_large_image">
<meta name="theme-color" content="#121212">
<link rel="icon" href="/favicon.ico" sizes="48x48">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="preload" as="font" type="font/otf" href="/assets/fonts/Satoshi-Medium.otf" crossorigin>
<link rel="stylesheet" href="/styles.css?v=${CSSV}">
${[WEBSITE_LD, ...jsonld].map((o) => `<script type="application/ld+json">${json(o)}</script>`).join('\n')}
</head>
<body class="${systemFont.has(code) ? 'sysfont' : ''}">`;
}

export function langMenu(code, locales, label) {
  const items = LANGS.filter(([c]) => locales[c]).map(([c, h]) =>
    `<a href="${homePath(c)}" hreflang="${h}" lang="${h}"${c === code ? ' aria-current="page"' : ''}>${esc(locales[c].langName)}</a>`).join('');
  return `<details class="langmenu"><summary aria-label="${esc(label)}">${code.toUpperCase()}</summary><div class="langmenu-list">${items}</div></details>`;
}

export function footer(t, code) {
  const L = siteLinks(code);
  const f = t.footer;
  return `<footer class="wrap footer">
  <span class="brand">${logo(18)}<span>HLAS</span></span>
  <span class="made">${esc(f.made)} <a href="https://gedeondrapak.com">Gedeon Drapák</a> ${esc(f.and)} <a href="https://edenmakers.ai">Edenmakers</a></span>
  <nav class="foot-links"><a href="${L.compare}">${esc(f.compare)}</a><a href="${L.faq}">${esc(f.faq)}</a><a href="${L.privacy}">${esc(f.privacy)}</a><a href="${L.about}">${esc(f.about)}</a><a href="${L.press}">${esc(f.press)}</a><a href="${L.changelog}">${esc(f.changelog)}</a><a href="${L.languages}">${esc(f.languages)}</a><a href="${GITHUB}">GitHub</a></nav>
  <p class="legal">${esc(f.trust)} Eden Makers s.r.o. · IČO 24518344 · DIČ CZ24518344 · Plzeňská 3352/156, 150 00 Praha</p>
</footer>`;
}

function softwareLd(t, code) {
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'Hlas',
    applicationCategory: 'UtilitiesApplication',
    operatingSystem: 'macOS 15 or later (Apple Silicon), Windows 10, Windows 11',
    softwareVersion: VERSION,
    dateModified: UPDATED,
    description: t.meta.description,
    inLanguage: code,
    url: `${SITE}${homePath(code)}`,
    downloadUrl: DMG,
    fileSize: '4MB',
    offers: [
      { '@type': 'Offer', name: 'Hlas', price: '0', priceCurrency: 'EUR' },
      { '@type': 'Offer', name: 'Hlas Cloud', price: '35', priceCurrency: 'EUR', description: 'Yearly subscription, price without VAT' },
    ],
    publisher: { '@type': 'Organization', name: 'Eden Makers s.r.o.', url: 'https://edenmakers.ai' },
    author: { '@type': 'Person', name: 'Gedeon Drapák', url: 'https://gedeondrapak.com' },
  };
}
const faqLd = (items) => ({ '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: items.map((i) => ({ '@type': 'Question', name: strip(i.q), acceptedAnswer: { '@type': 'Answer', text: strip(i.a) } })) });

function home(t, code, hreflang, dir, locales) {
  const L = siteLinks(code);
  const alternates = LANGS.filter(([c]) => locales[c]).map(([c, h]) => [h, homePath(c)]).concat([['x-default', '/en/']]);
  const f = t.features, p = t.perf, pr = t.pricing;
  const n = (v) => String(v).replace('.', t.dec);
  const vocabLi = f.vocab.items.map(([w, h]) => `<li><b>${esc(w)}</b><small>${esc(h)}</small></li>`).join('');
  const cloud = [['6%', '8%', '34px', 0, 'Dobrý den'], ['54%', '4%', '22px', 3, 'こんにちは'], ['2%', '36%', '26px', 2, 'привіт'], ['52%', '32%', '30px', 0, 'Ahoj'], ['10%', '62%', '28px', 1, 'Cześć'], ['56%', '62%', '22px', 4, '안녕하세요'], ['4%', '86%', '20px', 4, 'Hola'], ['44%', '86%', '24px', 2, 'Servus']];
  // Put the visitor's own greeting first in the cloud.
  const hello = { pl: 'Cześć', hu: 'Szia', de: 'Hallo', fr: 'Bonjour', es: 'Hola', pt: 'Olá', it: 'Ciao', nl: 'Hallo', ro: 'Salut', uk: 'Привіт', ru: 'Привет', bg: 'Здравей', sr: 'Zdravo', hr: 'Bok', sl: 'Živjo', el: 'Γεια σου', tr: 'Merhaba', sv: 'Hej', da: 'Hej', nb: 'Hei', fi: 'Moi', lt: 'Labas', lv: 'Sveiki', et: 'Tere', ca: 'Hola', ja: 'こんにちは', ko: '안녕하세요', zh: '你好', hi: 'नमस्ते', bn: 'নমস্কার', th: 'สวัสดี', vi: 'Xin chào', id: 'Halo', ms: 'Hai', ar: 'مرحبا', he: 'שלום', fa: 'سلام', sk: 'Ahoj', en: 'Hello', cs: 'Dobrý den' }[code];
  cloud[0][4] = hello;
  if (code !== 'cs') cloud[3][4] = 'Dobrý den';
  const marqA = ['Čeština', 'Slovenčina', 'English', 'Deutsch', 'Polski', 'Українська', 'Français', 'Español', 'Italiano', 'Magyar', 'Nederlands', 'Português'];
  const marqB = ['Svenska', 'Română', 'Hrvatski', 'Slovenščina', 'Български', 'Ελληνικά', 'Türkçe', '日本語', '한국어', 'Tiếng Việt', 'Dansk', 'Suomi'];
  const hi = (arr) => [...arr, ...arr].map((s) => `<span${s === t.langName || s === 'Čeština' ? ' class="hi"' : ''}>${esc(s)}</span>`).join('');
  const checks = (arr) => arr.map((s) => `<li>${esc(s)}</li>`).join('');
  const ld = [softwareLd(t, code), faqLd(t.faq.items)];
  const otherLangs = Object.fromEntries(LANGS.filter(([c]) => locales[c]).map(([c, h]) => [c, { path: homePath(c), name: locales[c].langName, suggest: locales[c].suggest }]));
  const client = { code, dec: t.dec, idle: t.demo.idle, busy: t.demo.busy, soon: t.toast.soon, scenes: t.demo.scenes, vocab: f.vocab.cycle, morph: p.sym.morph, checkout: CHECKOUT, events: EVENTS, langs: otherLangs };

  return `${head({ code, hreflang, dir, title: t.meta.title, description: t.meta.description, path: homePath(code), alternates, ogTitle: t.meta.ogTitle, ogDescription: t.meta.ogDescription, jsonld: ld })}
<link rel="preload" as="image" href="/assets/hero.webp" fetchpriority="high">
<a class="skip" href="#top">Hlas</a>
<header class="nav" id="nav">
  <a class="brand" href="${homePath(code)}" aria-label="Hlas">${logo()}<span>HLAS</span></a>
  <nav class="nav-links">
    <a href="#features">${esc(t.nav.features)}</a>
    <a href="#light">${esc(t.nav.performance)}</a>
    <a href="#languages">${esc(t.nav.languages)}</a>
    <a href="#pricing">${esc(t.nav.pricing)}</a>
  </nav>
  ${langMenu(code, locales, t.nav.language)}
  <a class="btn btn-light btn-sm" href="#download">${esc(t.nav.download)}</a>
</header>
<div class="suggest" id="suggest" hidden></div>

<main id="top">
<section class="hero">
  <div class="hero-bg" id="heroBg"></div>
  <div class="hero-fade"></div>
  <div class="wrap hero-inner">
    <a class="badge reveal" href="#pricing"><span class="badge-dot"></span><span>${esc(t.hero.badge)}</span><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 6l6 6-6 6"/></svg></a>
    <h1 class="split">${t.hero.h1}</h1>
    <p class="hero-sub reveal">${t.hero.sub}</p>
    <div class="cta-row reveal" id="download">
      <a class="btn btn-light" href="${DMG}" data-ev="download-mac">${apple}<span>${esc(t.hero.dlMac)}</span></a>
      <a class="btn btn-glass" href="${EXE}" data-ev="download-win">${win}<span>${esc(t.hero.dlWin)}</span></a>
    </div>
    <p class="hero-note reveal">${esc(t.hero.note)}</p>
    <p class="hero-privacy reveal"><span class="badge-dot"></span>${esc(t.hero.privacy)}</p>

    <div class="demo reveal" id="demo" aria-hidden="true">
      <div class="win">
        <div class="win-bar">
          <span class="tl"></span><span class="tl"></span><span class="tl"></span>
          <div class="tabs" id="tabs"><button class="tab on" data-i="0" tabindex="-1">Slack</button><button class="tab" data-i="1" tabindex="-1">Mail</button><button class="tab" data-i="2" tabindex="-1">${esc(t.demo.tabNotes)}</button></div>
        </div>
        <div class="vglow" id="vglow" aria-hidden="true"><i></i><i></i><i></i></div><div class="win-body"><div class="ctx" id="ctx"></div><div class="composer"><span id="typed"></span><span class="caret"></span></div></div>
      </div>
      <div class="dock">
        <button class="key" id="fnKey" type="button" tabindex="-1"><span>fn</span><svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18"/></svg></button>
        <div class="pill" id="pill"><span class="rec"></span><canvas class="orb" id="orb" aria-hidden="true"></canvas><canvas id="wave" width="360" height="68"></canvas><span class="pill-label" id="pillLabel">${esc(t.demo.idle)}</span></div>
      </div>
    </div>
  </div>
</section>

<section class="stats wrap">
  <div class="stat reveal"><b><span class="count" data-to="4">4</span> MB</b><span>${esc(t.stats.app)}</span></div>
  <div class="stat reveal"><b><span class="count" data-to="60">60</span> MB</b><span>${esc(t.stats.ram)}</span></div>
  <div class="stat reveal"><b><span class="count" data-to="1.7" data-dec="1">${n('1.7')}</span> s</b><span>${esc(t.stats.speed)}</span></div>
  <div class="stat reveal"><b><span class="count" data-to="60">60</span>+</b><span>${esc(t.stats.langs)}</span></div>
</section>

<section class="sec" id="features">
  <div class="wrap">
    <p class="eyebrow reveal">${esc(f.eyebrow)}</p>
    <h2 class="reveal">${f.h2}</h2>
    <div class="tall-grid">
      <article class="tall reveal" style="--img:url(/assets/card-mountain.webp);--tint:#8fe3ff">
        <div class="tall-art"><div class="toggle-card" id="wifi"><span>Wi-Fi</span><i class="sw"><i></i></i></div><div class="local-chip"><span class="badge-dot"></span><span>${esc(f.offline.chip)}</span></div></div>
        <h3>${esc(f.offline.h3)}</h3><p>${esc(f.offline.p)}</p><p class="strong">${esc(f.offline.strong)}</p>
      </article>
      <article class="tall reveal" style="--img:url(/assets/card-forest.webp);--tint:#4dffb0">
        <div class="tall-art"><div class="vocab"><div class="vocab-in"><span id="vocabTyped"></span><span class="caret"></span><em>${esc(f.vocab.add)}</em></div><ul id="vocabList">${vocabLi}</ul></div></div>
        <h3>${esc(f.vocab.h3)}</h3><p>${esc(f.vocab.p)}</p><p class="strong">${esc(f.vocab.strong)}</p>
      </article>
      <article class="tall reveal" style="--img:url(/assets/card-dunes.webp);--tint:#ffb86b">
        <div class="tall-art"><div class="smart" id="smart"><div class="smart-raw">${esc(f.smart.raw)}</div><div class="smart-out"><b>${esc(f.smart.title)}</b>${f.smart.out.map((s) => `<span>${esc(s)}</span>`).join('')}</div></div></div>
        <h3>${esc(f.smart.h3)}</h3><p>${esc(f.smart.p)}</p><p class="strong">${esc(f.smart.strong)}</p>
      </article>
      <article class="tall reveal" style="--img:url(/assets/card-sea.webp);--tint:#7ab8ff">
        <div class="tall-art"><div class="langcloud" id="langcloud">${cloud.map(([x, y, s, b, w]) => `<span style="--x:${x};--y:${y};--s:${s};--b:${b}px">${esc(w)}</span>`).join('')}</div></div>
        <h3>${esc(f.langs.h3)}</h3><p>${esc(f.langs.p)}</p><p class="strong">${esc(f.langs.strong)}</p>
      </article>
    </div>
    <div class="mini-grid">
      ${t.mini.map((m, i) => `<div class="mini reveal">${['<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="3" width="14" height="18" rx="3"/><path d="M9 8h6M9 12h6M9 16h3"/></svg>', '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11V5.5a1.5 1.5 0 013 0V11m0-1.5a1.5 1.5 0 013 0V11m0-.5a1.5 1.5 0 013 0V15a6 6 0 01-6 6h-1a6 6 0 01-5-2.7L3.5 14a1.5 1.5 0 012.5-1.6L9 15"/></svg>', '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="6" width="18" height="12" rx="3"/><path d="M7 10h1M11 10h1M15 10h2M8 14h8"/></svg>', '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>'][i]}<h4>${esc(m.h4)}</h4><p>${esc(m.p)}</p></div>`).join('\n      ')}
    </div>
  </div>
</section>

<section class="sec" id="light">
  <div class="wrap">
    <p class="eyebrow reveal">${esc(p.eyebrow)}</p>
    <h2 class="reveal">${p.h2}</h2>
    <div class="bento">
      <div class="cell c-ram spot reveal" id="ram">
        <div class="cell-head"><h3>${esc(p.ram.h3)}</h3><p>${esc(p.ram.p)}</p></div>
        <div class="bars">
          <div class="bar-row"><span class="bar-name">Hlas</span><div class="bar"><i class="me" style="--w:7.5%"></i></div><b>~60 MB</b></div>
          <div class="bar-row"><span class="bar-name">Superwhisper</span><div class="bar"><i style="--w:100%"></i></div><b>~800 MB</b></div>
        </div>
        <p class="foot">${esc(p.ram.foot)}</p>
      </div>
      <div class="cell c-size spot reveal"><h3>${esc(p.size.h3)}</h3><div class="size-viz"><div class="size-big"><i></i><span>1 GB+</span></div><div class="size-me"><i></i><span>4 MB</span></div></div><p>${esc(p.size.p)}</p></div>
      <div class="cell c-speed spot reveal" id="speed"><h3>${esc(p.speed.h3)}</h3><div class="race"><div class="race-row"><span>${esc(p.speed.speak)}</span><div class="track"><i class="t-speak"></i></div><b>11 s</b></div><div class="race-row"><span>${esc(p.speed.writes)}</span><div class="track"><i class="t-hlas"></i></div><b>${n('1.7')} s</b></div></div><p>${esc(p.speed.p)}</p></div>
      <div class="cell c-fill spot reveal"><h3>${esc(p.fill.h3)}</h3><p class="filler" id="filler">${p.fill.html}</p><p>${esc(p.fill.p)}</p></div>
      <div class="cell c-sym spot reveal"><h3>${esc(p.sym.h3)}</h3><div class="morph" id="morph"><span class="m-say"></span><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg><span class="m-get"></span></div><p>${esc(p.sym.p)}</p></div>
      <div class="cell c-priv spot reveal"><h3>${esc(p.priv.h3)}</h3><ul class="checks">${checks(p.priv.items)}</ul></div>
      <div class="cell c-apps spot reveal"><h3>${esc(p.apps.h3)}</h3><div class="marq"><div class="marq-in">${['Slack', 'Gmail', 'Notion', 'Cursor', 'WhatsApp', 'Figma', 'Word', 'ChatGPT', 'Claude', 'Obsidian', 'Linear', 'Messenger'].concat(['Slack', 'Gmail', 'Notion', 'Cursor', 'WhatsApp', 'Figma', 'Word', 'ChatGPT', 'Claude', 'Obsidian', 'Linear', 'Messenger']).map((a) => `<span>${a}</span>`).join('')}</div></div><p>${esc(p.apps.p)}</p></div>
    </div>
  </div>
</section>

<section class="sec langs" id="languages">
  <div class="wrap"><p class="eyebrow reveal">${esc(t.langs.eyebrow)}</p><h2 class="reveal">${t.langs.h2}</h2></div>
  <div class="lang-marq" aria-hidden="true"><div class="lm lm-a">${hi(marqA)}</div><div class="lm lm-b">${hi(marqB)}</div></div>
  <div class="wrap lang-points">${t.langs.points.map((x) => `<div class="lp reveal"><b>${esc(x.b)}</b><h4>${esc(x.h4)}</h4><p>${esc(x.p)}</p></div>`).join('')}</div>
  ${t.langs.note ? `<p class="wrap lang-note reveal">${esc(t.langs.note)} <a href="${GITHUB}/issues">GitHub</a></p>` : ''}
</section>

<section class="sec" id="pricing">
  <div class="wrap">
    <p class="eyebrow reveal">${esc(pr.eyebrow)}</p>
    <h2 class="reveal">${pr.h2}</h2>
    <div class="plans">
      <div class="plan spot reveal">
        <p class="plan-name">${esc(pr.free.name)}</p>
        <p class="price">0 €<small>${esc(pr.free.forever)}</small></p>
        <p class="plan-sub">${esc(pr.free.sub)}</p>
        <ul class="checks">${checks(pr.free.items)}</ul>
        <a class="btn btn-glass" href="#download">${esc(pr.free.cta)}</a>
      </div>
      <div class="plan plan-pro spot reveal">
        <span class="beam" aria-hidden="true"></span>
        ${pr.cloud.tag ? `<span class="plan-tag">${esc(pr.cloud.tag)}</span>` : ''}
        <p class="plan-name">Hlas Cloud</p>
        <p class="price">35 €<small>${esc(pr.cloud.per)}</small></p>
        <p class="plan-sub">${esc(pr.cloud.sub)}</p>
        ${pr.cloud.presale ? `<p class="presale">${esc(pr.cloud.presale)}</p>` : ''}
        ${pr.cloud.trial ? `<p class="presale">${esc(pr.cloud.trial)}</p>` : ''}
        <ul class="checks">${checks(pr.cloud.items)}</ul>
        <a class="btn btn-brand" href="${CHECKOUT}" id="buy" rel="noopener" data-ev="checkout">${esc(pr.cloud.cta)}</a>
        ${pr.cloud.region ? `<p class="vat">${esc(pr.cloud.region)}</p>` : ''}
        <p class="vat">${esc(pr.cloud.vat)} <a href="${L.privacy}">${esc(t.footer.privacy)}</a></p>
        <a class="manage" href="${PORTAL}" data-ev="manage">${esc(pr.cloud.manage)}</a>
      </div>
    </div>
    <div class="yearly reveal" id="yearly">
      <p class="yearly-title">${esc(pr.yearly.title)}</p>
      <p class="yearly-big">${esc(pr.yearly.big)}</p>
      <div class="bar-row"><span class="bar-name">Hlas Cloud</span><div class="bar"><i class="me" style="--w:26.9%"></i></div><b>35 €</b><em></em></div>
      <div class="bar-row"><span class="bar-name">Superwhisper</span><div class="bar"><i style="--w:59%"></i></div><b>${n('76.90')} €</b><em>-54 %</em></div>
      <div class="bar-row"><span class="bar-name">Wispr Flow</span><div class="bar"><i style="--w:100%"></i></div><b>${n('130.29')} €</b><em>-73 %</em></div>
      <div class="bar-row"><span class="bar-name">Willow</span><div class="bar"><i style="--w:100%"></i></div><b>${n('130.29')} €</b><em>-73 %</em></div>
      <p class="foot">${esc(pr.yearly.foot)} <a href="${L.compare}">${esc(pr.compareLink)}</a></p>
    </div>
  </div>
</section>

<section class="sec" id="faq">
  <div class="wrap faq-wrap">
    <div><p class="eyebrow reveal">${esc(t.faq.eyebrow)}</p><h2 class="reveal">${esc(t.faq.h2)}</h2></div>
    <div class="faq">${t.faq.items.map((i) => `<details class="reveal"><summary>${esc(i.q)}</summary><p>${esc(i.a)}</p></details>`).join('\n      ')}</div>
  </div>
</section>

<section class="final">
  <div class="final-bg"></div>
  <div class="wrap final-inner">
    <h2 class="reveal">${esc(t.final.h2)}</h2>
    <p class="reveal">${esc(t.final.p)}</p>
    <div class="cta-row reveal"><a class="btn btn-light" href="${DMG}" data-ev="download-mac">${esc(t.final.dlMac)}</a><a class="btn btn-glass" href="${EXE}" data-ev="download-win">${esc(t.hero.dlWin)}</a></div>
  </div>
</section>
</main>

${footer(t, code)}
<div class="toast" id="toast" role="status"></div>
<script>window.HLAS=${json(client)}</script>
<script src="/app.js?v=${JSV}" defer></script>
<script type="module" src="/orb.js?v=${ORBV}"></script>
</body>
</html>
`;
}

function write(path, html) {
  const file = join(OUT, path.endsWith('/') ? path + 'index.html' : path);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, html);
  return file;
}

function main() {
  const locales = loadLocales();
  const built = [];
  for (const [code, hreflang, dir] of LANGS) {
    const t = locales[code];
    if (!t) continue;
    write(homePath(code), home(t, code, hreflang, dir, locales));
    built.push(homePath(code));
  }
  const pages = contentPages({ locales, head, footer, langMenu, siteLinks, homePath, LANGS, SITE, UPDATED, VERSION, DMG, EXE, GITHUB, esc, logo });
  for (const pg of pages) { write(pg.path, pg.html); built.push(pg.path); }

  // sitemap with hreflang clusters for the homepages and the cs/en page pairs
  const homeAlts = LANGS.filter(([c]) => locales[c]).map(([c, h]) => `<xhtml:link rel="alternate" hreflang="${h}" href="${SITE}${homePath(c)}"/>`).join('');
  const urls = built.map((p) => {
    const isHome = LANGS.some(([c]) => locales[c] && homePath(c) === p);
    const pg = pages.find((x) => x.path === p);
    const alts = isHome ? homeAlts : (pg?.alternates || []).map(([h, ap]) => `<xhtml:link rel="alternate" hreflang="${h}" href="${SITE}${ap}"/>`).join('');
    return `<url><loc>${SITE}${p}</loc><lastmod>${UPDATED}</lastmod>${alts}</url>`;
  }).join('\n');
  write('/sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls}\n</urlset>\n`);

  write('/robots.txt', `# Search engines and AI assistants are welcome to read and cite hlas.dev.
User-agent: *
Allow: /
Disallow: /_src/
Disallow: /variants/

User-agent: GPTBot
Allow: /
User-agent: OAI-SearchBot
Allow: /
User-agent: ChatGPT-User
Allow: /
User-agent: ClaudeBot
Allow: /
User-agent: Claude-User
Allow: /
User-agent: PerplexityBot
Allow: /
User-agent: Google-Extended
Allow: /
User-agent: Applebot-Extended
Allow: /

Sitemap: ${SITE}/sitemap.xml
`);

  const langList = LANGS.filter(([c]) => locales[c]).map(([c]) => `- [${locales[c].langName} (${locales[c].langNameEn})](${SITE}${homePath(c)})`).join('\n');
  write('/llms.txt', `# Hlas

> Hlas is a small native dictation app for Mac and Windows, made in Prague by Gedeon Drapák and Eden Makers s.r.o. Hold Fn, speak, release, and the text is typed where the cursor is, in any app. Czech, Slovak and English have extra tuning; 60+ other languages work through Whisper large-v3.

Key facts (as of ${UPDATED}):
- Version ${VERSION}, released 15 November 2026. Mac: Apple Silicon, macOS 15 or later, signed with Apple Developer ID and notarized. Windows 10 and 11 (x64): beta, installer not code-signed yet.
- App size 4 MB. RAM about 60 MB when idle, about 1 GB while the local model is loaded; the model unloads after 3 minutes of silence.
- Local transcription with whisper.cpp (Whisper large-v3 turbo, 547 MB download) works offline; audio does not leave the computer.
- Free forever for local use or with your own API key (Groq, OpenAI, Soniox, Fish Audio).
- Hlas Cloud: EUR 35 a year without VAT (EUR 42.35 for EU consumers incl. 21 % Czech VAT), unlimited dictation with fair use up to 3 hours a day, Mac and Windows, 7-day free trial without a card in the app. Audio goes through the Hlas server to Groq for transcription and is not stored by Hlas.
- Source code: ${GITHUB}

## Pages
- [Homepage, Czech](${SITE}/)
- [Homepage, English](${SITE}/en/)
- [Comparison with Superwhisper, Wispr Flow, MacWhisper and others](${SITE}/en/compare/)
- [FAQ](${SITE}/en/faq/)
- [Privacy](${SITE}/en/privacy/)
- [About](${SITE}/en/about/)
- [Press kit](${SITE}/en/press/)
- [Changelog](${SITE}/changelog/)
- [Dictation for smaller languages](${SITE}/en/small-languages-dictation/)

## Languages
${langList}
`);
  console.log(`built ${built.length} pages:`, built.join(' '));
}

main();
