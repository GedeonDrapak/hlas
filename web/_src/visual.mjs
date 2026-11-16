// Visual building blocks for the comparison pages: cost chart, feature grid,
// how-it-works strip, verdict cards, FAQ accordion, calculator. Plain HTML + CSS,
// web/compare.js adds the interactions (year toggle, slider). Everything reads
// without JavaScript: the chart renders for one year, the calculator shows a default.

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const eur = (n, cs) => (Math.round(n * 100) / 100).toFixed(2).replace('.', cs ? ',' : '.').replace(/[,.]00$/, '');
const T = (cs, a, b) => (cs ? a : b);

/** rows: [{ name, me?, y? (per year), o? (one-time) }]. Sorted by cost at the chosen horizon in the browser. */
export function costChart(rows, cs, { title, years = [1, 3, 5], start = 1 } = {}) {
  const cost = (r, n) => (r.o != null ? r.o : (r.y || 0) * n);
  const max = Math.max(...rows.map((r) => cost(r, start)), 1);
  const sorted = [...rows].sort((a, b) => cost(a, start) - cost(b, start));
  const bar = (r) => {
    const c = cost(r, start);
    const kind = r.o != null ? T(cs, 'jednorázově', 'one-time') : r.y ? T(cs, 'předplatné', 'subscription') : T(cs, 'zdarma', 'free');
    return `<div class="cc-row${r.me ? ' me' : ''}" data-y="${r.y || 0}" data-o="${r.o ?? ''}">
  <span class="cc-name">${esc(r.name)}<small>${kind}</small></span>
  <span class="cc-track"><i style="--w:${((c / max) * 100).toFixed(1)}%"></i></span>
  <b class="cc-val">${c === 0 ? T(cs, 'zdarma', 'free') : eur(c, cs) + ' €'}</b>
</div>`;
  };
  return `<figure class="costchart" data-cs="${cs ? 1 : 0}" aria-label="${esc(title)}">
  <figcaption><span>${esc(title)}</span><span class="cc-toggle" role="group" aria-label="${T(cs, 'Období', 'Period')}">${years.map((n) => `<button type="button" data-n="${n}"${n === start ? ' aria-pressed="true"' : ''}>${n} ${cs ? (n === 1 ? 'rok' : n < 5 ? 'roky' : 'let') : n === 1 ? 'year' : 'years'}</button>`).join('')}</span></figcaption>
  <div class="cc-rows">${sorted.map(bar).join('')}</div>
  <p class="cc-foot">${T(cs, 'Ceny bez DPH. Předplatné násobíme počtem let, jednorázová licence se platí jednou.', 'Prices without VAT. Subscriptions are multiplied by the years, a one-time licence is paid once.')}</p>
</figure>`;
}

const ICON = {
  yes: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  no: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7l10 10M17 7L7 17" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
  dash: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 12h10" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
};

/** cells: [state 'yes'|'no'|'dash', text] for Hlas and the other app. */
export function featureGrid(other, rows, cs) {
  const cell = ([st, txt]) => `<div class="fg-cell ${st}">${ICON[st]}<span>${esc(txt)}</span></div>`;
  return `<div class="fgrid" role="table" aria-label="${T(cs, 'Srovnání funkcí', 'Feature comparison')}">
  <div class="fg-head" role="row"><span role="columnheader"></span><span role="columnheader" class="fg-me">Hlas</span><span role="columnheader">${esc(other)}</span></div>
  ${rows.map(([label, a, b]) => `<div class="fg-row" role="row"><span class="fg-label" role="rowheader">${esc(label)}</span>${cell(a)}${cell(b)}</div>`).join('\n  ')}
</div>`;
}

export function howItWorks(cs) {
  return `<div class="how">
  <div class="how-step"><div class="how-vis"><span class="kc">fn</span></div><h3>${T(cs, '1. Podrž Fn', '1. Hold Fn')}</h3><p>${T(cs, 'V jakékoli aplikaci: Slack, Mail, Word, prohlížeč.', 'In any app: Slack, Mail, Word, the browser.')}</p></div>
  <div class="how-step"><div class="how-vis"><span class="wavebars" aria-hidden="true">${Array.from({ length: 13 }, (_, i) => `<i style="--d:${(i * 0.07).toFixed(2)}s"></i>`).join('')}</span></div><h3>${T(cs, '2. Mluv', '2. Speak')}</h3><p>${T(cs, 'Normálně, česky, slovensky nebo v 60+ dalších jazycích.', 'Naturally, in Czech, English or 60+ other languages.')}</p></div>
  <div class="how-step"><div class="how-vis"><span class="typed">${T(cs, 'Ahoj Petře, posílám finální verzi.', 'Hi Peter, sending the final version.')}<i></i></span></div><h3>${T(cs, '3. Pusť a je to', '3. Let go, done')}</h3><p>${T(cs, 'Text se napíše tam, kde máš kurzor. S tečkami a čárkami.', 'The text lands where your cursor is, with full punctuation.')}</p></div>
</div>`;
}

export function verdict(other, betterText, hlasText, cs) {
  return `<div class="verdict">
  <div class="vd"><p class="vd-k">${T(cs, `Vyber ${esc(other)}, když`, `Pick ${esc(other)} if`)}</p><p>${esc(betterText)}</p></div>
  <div class="vd me"><p class="vd-k">${T(cs, 'Vyber Hlas, když', 'Pick Hlas if')}</p><p>${esc(hlasText)}</p></div>
</div>`;
}

export const faqAccordion = (items) => `<div class="faqx">${items.map(([q, a], i) => `<details${i === 0 ? ' open' : ''}><summary>${esc(q)}</summary><p>${a}</p></details>`).join('')}</div>`;

/** Own Groq key vs Hlas Cloud per month, by minutes of dictation a day. */
export function keyCalculator(cs) {
  return `<div class="calc" data-cs="${cs ? 1 : 0}">
  <label for="calc-min">${T(cs, 'Kolik diktuješ denně?', 'How much do you dictate a day?')} <b class="calc-min-out">30 min</b></label>
  <input id="calc-min" type="range" min="5" max="240" step="5" value="30">
  <div class="calc-out">
    <div><small>${T(cs, 'Vlastní klíč Groq', 'Your own Groq key')}</small><b class="calc-key">0,54 €</b><span>${T(cs, 'měsíčně, platíš Groqu', 'a month, paid to Groq')}</span></div>
    <div class="me"><small>Hlas Cloud</small><b>2,92 €</b><span>${T(cs, 'měsíčně, bez klíčů a limitu slov', 'a month, no keys, no word limit')}</span></div>
    <div><small>${T(cs, 'Lokálně v Hlasu', 'Locally in Hlas')}</small><b>0 €</b><span>${T(cs, 'zdarma, offline, potřebuje model 547 MB', 'free, offline, needs a 547 MB model')}</span></div>
  </div>
  <p class="cc-foot">${T(cs, 'Groq účtuje whisper-large-v3-turbo 0,04 $ za hodinu zvuku (1 $ = 0,90481 €), 30 dní v měsíci. Hlas Cloud je 35 € ročně bez DPH.', 'Groq charges $0.04 per hour of audio for whisper-large-v3-turbo ($1 = €0.90481), 30 days a month. Hlas Cloud is €35 a year without VAT.')}</p>
</div>`;
}

const APPLE = '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.8-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7 2-1.1 2.8-2.3c.9-1.3 1.2-2.5 1.3-2.6-.1 0-2.5-1-2.5-3.8zM14.1 5.8c.6-.8 1.1-1.9 1-3-1 0-2.1.6-2.8 1.4-.6.7-1.2 1.8-1 2.9 1.1.1 2.2-.5 2.8-1.3z"/></svg>';
const WIN = '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 5.5l7.5-1v7.2H3zM11.5 4.3L21 3v8.7h-9.5zM3 12.7h7.5v7.2L3 18.8zM11.5 12.7H21V21l-9.5-1.3z"/></svg>';
const dlButtons = (cs, DMG, EXE) => `<a class="btn btn-light" href="${DMG}" data-ev="download-mac">${APPLE}<span>${T(cs, 'Stáhnout pro Mac', 'Download for Mac')}</span></a><a class="btn btn-glass" href="${EXE}" data-ev="download-win">${WIN}<span>${T(cs, 'Windows (beta)', 'Windows (beta)')}</span></a>`;

/** Compact download strip for the middle of a page. */
export const dlStrip = (cs, DMG, EXE) => `<div class="dlstrip">
  <p><b>${T(cs, 'Vyzkoušej to hned.', 'Try it now.')}</b> ${T(cs, 'Zdarma, 4 MB, bez účtu.', 'Free, 4 MB, no account.')}</p>
  <div class="dlstrip-b">${dlButtons(cs, DMG, EXE)}</div>
</div>`;

export const ctaBand = (cs, DMG, EXE) => `<div class="ctaband">
  <div><h2>${T(cs, 'Vyzkoušej Hlas zdarma', 'Try Hlas for free')}</h2><p>${T(cs, '4 MB, Mac i Windows. Hlas Cloud 7 dní zdarma bez karty.', '4 MB, Mac and Windows. Hlas Cloud 7 days free, no card.')}</p></div>
  <div class="ctaband-b">${dlButtons(cs, DMG, EXE)}</div>
</div>`;
