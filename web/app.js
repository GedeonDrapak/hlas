(() => {
  'use strict';

  const H = window.HLAS || {};
  const CHECKOUT_URL = H.checkout || '';

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const t = () => H;

  function splitWords(el) {
    // CJK and Thai have no spaces: the headline then animates as one block.
    const words = el.textContent.trim().split(/\s+/);
    if (words.length < 2) { el.classList.add('in'); return; }
    el.innerHTML = words.map((w, i) => `<span class="w" style="--i:${i}">${w}</span>`).join(' ');
  }

  /* ---------- language suggestion (no auto redirect, crawlers see every page) ---------- */
  function suggestLanguage() {
    const box = $('#suggest'); if (!box || !H.langs) return;
    let dismissed = false; try { dismissed = localStorage.getItem('hlas-lang-ok') === '1'; } catch (e) {}
    if (dismissed) return;
    const prefs = (navigator.languages || [navigator.language || '']).map((l) => l.toLowerCase());
    let match = null;
    for (const p of prefs) {
      let base = p.split('-')[0];
      if (base === 'no' || base === 'nn') base = 'nb';
      if (base === H.code) return;
      if (H.langs[base]) { match = base; break; }
    }
    if (!match) return;
    const L = H.langs[match];
    box.innerHTML = `<a href="${L.path}" hreflang="${match}">${L.suggest} →</a><button type="button" aria-label="Close">×</button>`;
    box.hidden = false;
    const ok = () => { try { localStorage.setItem('hlas-lang-ok', '1'); } catch (e) {} };
    $('button', box).addEventListener('click', () => { box.hidden = true; ok(); });
    $$('.langmenu-list a').forEach((a) => a.addEventListener('click', ok));
  }

  /* ---------- reveal ---------- */
  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (!e.isIntersecting) return;
      e.target.classList.add('in');
      io.unobserve(e.target);
    });
  }, { threshold: 0.14, rootMargin: '0px 0px -6% 0px' });

  function initReveal() {
    $$('.reveal, .split').forEach((el) => {
      const sibs = [...el.parentElement.children].filter((c) => c.classList.contains('reveal'));
      const i = sibs.indexOf(el);
      if (i > 0) el.style.setProperty('--d', Math.min(i, 6) * 80 + 'ms');
      io.observe(el);
    });
  }

  /* fire fn once (or every time) when element enters view */
  function onView(el, fn, repeat = false) {
    if (!el) return;
    const o = new IntersectionObserver((es) => es.forEach((e) => {
      if (e.isIntersecting) { fn(); if (!repeat) o.disconnect(); }
    }), { threshold: 0.45 });
    o.observe(el);
  }

  /* ---------- nav + parallax ---------- */
  const nav = $('#nav'), heroBg = $('#heroBg');
  let ticking = false;
  addEventListener('scroll', () => {
    if (ticking) return; ticking = true;
    requestAnimationFrame(() => {
      const y = scrollY;
      nav.classList.toggle('scrolled', y > 40);
      if (!reduced && y < innerHeight * 1.4) heroBg.style.translate = `0 ${y * 0.16}px`;
      ticking = false;
    });
  }, { passive: true });

  /* ---------- waveform ---------- */
  const cv = $('#wave'), cx = cv.getContext('2d');
  const BARS = 30; const levels = new Array(BARS).fill(0.1); let waveOn = false, phase = 0;
  function drawWave() {
    const w = cv.width, h = cv.height;
    cx.clearRect(0, 0, w, h);
    phase += 0.09;
    const bw = 5, gap = (w - BARS * bw) / (BARS - 1);
    let sum = 0;
    for (let i = 0; i < BARS; i++) {
      const env = Math.sin((i / (BARS - 1)) * Math.PI) * 0.75 + 0.25;
      const target = waveOn
        ? (0.22 + 0.78 * Math.abs(Math.sin(phase * 1.7 + i * 0.63) * Math.sin(phase * 0.9 + i * 1.31))) * env
        : 0.08;
      levels[i] += (target - levels[i]) * 0.22;
      sum += levels[i];
      const bh = Math.max(5, levels[i] * h);
      cx.fillStyle = '#00E67A';
      cx.beginPath();
      cx.roundRect(i * (bw + gap), (h - bh) / 2, bw, bh, 2.5);
      cx.fill();
    }
    // voice glow in the demo window follows the same level
    if (glow) glow.style.setProperty('--lv', (sum / BARS).toFixed(3));
    requestAnimationFrame(drawWave);
  }

  /* ---------- hero demo ---------- */
  const glow = $('#vglow'), pill = $('#pill'), key = $('#fnKey'), typed = $('#typed'), ctx = $('#ctx'), tabs = $$('#tabs .tab');
  let demoToken = 0, scene = 0, manualHold = null;

  function showCtx(s) {
    ctx.innerHTML = s.ctx.map(([a, b]) => `<div class="row"><span class="av"></span><span><b>${a}</b><br>${b}</span></div>`).join('');
  }
  async function hold(ms, alive) {
    // resolves after ms, or sooner/later when the visitor holds the key themselves
    const end = performance.now() + ms;
    while (alive() && performance.now() < end) await sleep(60);
  }
  async function runDemo() {
    const my = demoToken; const alive = () => my === demoToken;
    while (alive()) {
      const s = t().scenes[scene];
      tabs.forEach((b, i) => b.classList.toggle('on', i === scene));
      typed.innerHTML = ''; showCtx(s);
      pill.classList.remove('rec-on', 'busy'); glow.classList.remove('on', 'think'); window.HlasOrb?.set('idle'); $('#pillLabel').textContent = t().idle;
      await hold(1300, alive); if (!alive()) return;

      key.classList.add('down'); pill.classList.add('rec-on'); glow.classList.add('on'); window.HlasOrb?.set('rec'); waveOn = true;
      await hold(2500, alive); if (!alive()) return;

      key.classList.remove('down'); waveOn = false;
      pill.classList.remove('rec-on'); pill.classList.add('busy'); $('#pillLabel').textContent = t().busy;
      glow.classList.add('think'); window.HlasOrb?.set('busy');
      await hold(1100, alive); if (!alive()) return;
      glow.classList.remove('on', 'think'); window.HlasOrb?.set('idle');
      pill.classList.remove('busy'); $('#pillLabel').textContent = t().idle;

      const words = s.text.split(' ');
      for (let i = 0; i < words.length; i++) {
        if (!alive()) return;
        const sp = document.createElement('span'); sp.className = 'tw'; sp.textContent = words[i] + ' ';
        typed.appendChild(sp);
        await sleep(reduced ? 0 : 55);
      }
      await hold(2600, alive); if (!alive()) return;
      scene = (scene + 1) % 3;
    }
  }
  tabs.forEach((b) => b.addEventListener('click', () => { scene = +b.dataset.i; demoToken++; runDemo(); }));
  key.addEventListener('click', () => { demoToken++; scene = (scene + 1) % 3; runDemo(); });

  /* ---------- count up ---------- */
  function countUp(el) {
    const to = parseFloat(el.dataset.to), dec = +(el.dataset.dec || 0), dur = 1400, t0 = performance.now();
    const fmt = (v) => v.toFixed(dec).replace('.', H.dec || '.');
    if (reduced) { el.textContent = fmt(to); return; }
    (function tick(now) {
      const p = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - p, 4);
      el.textContent = fmt(to * e);
      if (p < 1) requestAnimationFrame(tick);
    })(t0);
  }

  /* ---------- small loops ---------- */
  function loop(fn, ms) { fn(); return setInterval(fn, ms); }

  function initCards() {
    // offline toggle: Wi-Fi goes off, local chip stays
    const wifi = $('#wifi'); wifi.classList.add('on');
    onView(wifi, () => loop(() => wifi.classList.toggle('on'), 2600));

    // vocabulary: type a word, press Add, it drops into the list
    const vt = $('#vocabTyped'), vl = $('#vocabList'), add = $('.vocab-in em'); let vi = 0;
    onView(vl, async function cycle() {
      const [word, hint] = t().vocab[vi % t().vocab.length]; vi++;
      for (let i = 1; i <= word.length; i++) { vt.textContent = word.slice(0, i); await sleep(70); }
      await sleep(450); add.classList.add('hit'); await sleep(160); add.classList.remove('hit');
      vt.textContent = '';
      const li = document.createElement('li'); li.innerHTML = `<b>${word}</b><small>${hint}</small>`;
      vl.prepend(li); if (vl.children.length > 3) vl.lastElementChild.remove();
      await sleep(2200); cycle();
    });

    // smart text: raw <-> structured
    const smart = $('#smart');
    onView(smart, () => loop(() => smart.classList.toggle('done'), 3200));

    // language cloud: focus hops between phrases
    const lc = $$('#langcloud span'); let li = 0;
    onView($('#langcloud'), () => loop(() => {
      lc.forEach((s, i) => { s.classList.toggle('focus', i === li); s.classList.toggle('dim', i !== li); });
      li = (li + 3) % lc.length;
    }, 1900));

    // fillers strike out
    const filler = $('#filler');
    onView(filler, () => loop(() => filler.classList.toggle('cut'), 3000));

    // spoken symbols morph
    const morph = $('#morph'), say = $('.m-say', morph), get = $('.m-get', morph); let mi = 0;
    const setMorph = () => { const [a, b] = t().morph[mi % t().morph.length]; say.textContent = `„${a}“`; get.textContent = b; };
    setMorph();
    onView(morph, () => setInterval(async () => {
      morph.classList.add('swap'); await sleep(360); mi++; setMorph(); morph.classList.remove('swap');
    }, 2400));

    // speed race restarts each time it scrolls into view
    const speed = $('#speed');
    onView(speed, () => { speed.classList.remove('run'); void speed.offsetWidth; speed.classList.add('run'); }, true);

    $$('.count').forEach((el) => onView(el, () => countUp(el)));

    // cursor spotlight
    $$('.spot').forEach((el) => el.addEventListener('pointermove', (e) => {
      const r = el.getBoundingClientRect();
      el.style.setProperty('--mx', e.clientX - r.left + 'px');
      el.style.setProperty('--my', e.clientY - r.top + 'px');
    }));
  }

  /* ---------- checkout ---------- */
  const toast = $('#toast'); let toastTimer;
  const buy = $('#buy');
  if (CHECKOUT_URL) { buy.href = CHECKOUT_URL; buy.rel = 'noopener'; }
  buy.addEventListener('click', (e) => {
    if (CHECKOUT_URL) return;
    e.preventDefault();
    toast.textContent = t().soon; toast.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.remove('show'), 3600);
  });

  /* ---------- anonymous funnel counter: button name + page language, no cookie, no id ---------- */
  function initEvents() {
    if (!H.events || !navigator.sendBeacon) return;
    document.addEventListener('click', (e) => {
      const a = e.target.closest && e.target.closest('[data-ev]');
      if (a) navigator.sendBeacon(H.events, JSON.stringify({ e: a.dataset.ev, l: H.code }));
    });
  }

  /* ---------- boot ---------- */
  $$('.split').forEach(splitWords);
  initReveal(); initCards(); drawWave(); runDemo(); suggestLanguage(); initEvents();
  document.addEventListener('click', (e) => { const m = $('.langmenu[open]'); if (m && !m.contains(e.target)) m.open = false; });
})();
