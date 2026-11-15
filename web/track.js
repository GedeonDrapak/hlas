// Analytics and ad pixels for hlas.dev, configured by window.HLAS_TRACK from the page head.
// - Cloudflare Web Analytics: no cookies, no personal data, always on.
// - Google Analytics 4, Google Ads, Meta pixel: load only after the visitor allows them
//   (Google Consent Mode v2 stays "denied" until then). Nothing loads for an ID left empty.
// Clicks on [data-ev] become conversion events once allowed.
(() => {
  const C = window.HLAS_TRACK || {};
  const KEY = 'hlas-consent';
  const load = (src, attrs = {}) => {
    const s = document.createElement('script');
    s.src = src; s.async = true;
    for (const [k, v] of Object.entries(attrs)) s.setAttribute(k, v);
    document.head.appendChild(s);
  };

  // Only on the real site: the beacon rejects other origins (localhost previews).
  if (C.cf && location.hostname.endsWith('hlas.dev')) load('https://static.cloudflareinsights.com/beacon.min.js', { 'data-cf-beacon': JSON.stringify({ token: C.cf }) });

  const tags = [C.ga4, C.gads, C.meta].filter(Boolean);
  if (!tags.length) return;

  const read = () => { try { return localStorage.getItem(KEY); } catch (e) { return null; } };
  const save = (v) => { try { localStorage.setItem(KEY, v); } catch (e) {} };

  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function () { window.dataLayer.push(arguments); };
  gtag('consent', 'default', { ad_storage: 'denied', analytics_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied' });

  let granted = false;
  function grant() {
    if (granted) return;
    granted = true;
    gtag('consent', 'update', { ad_storage: 'granted', analytics_storage: 'granted', ad_user_data: 'granted', ad_personalization: 'granted' });
    const gid = C.ga4 || C.gads;
    if (gid) {
      load('https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(gid));
      gtag('js', new Date());
      if (C.ga4) gtag('config', C.ga4);
      if (C.gads) gtag('config', C.gads);
    }
    if (C.meta) {
      /* Meta pixel base code */
      !function (f, b, e, v, n, t, s) { if (f.fbq) return; n = f.fbq = function () { n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments); }; if (!f._fbq) f._fbq = n; n.push = n; n.loaded = !0; n.version = '2.0'; n.queue = []; t = b.createElement(e); t.async = !0; t.src = v; s = b.getElementsByTagName(e)[0]; s.parentNode.insertBefore(t, s); }(window, document, 'script', 'https://connect.facebook.net/en_US/fbevents.js');
      fbq('init', C.meta);
      fbq('track', 'PageView');
    }
  }

  // Conversions: downloads are leads, the subscribe button starts checkout.
  const META = { 'download-mac': ['Lead', { content_name: 'mac' }], 'download-win': ['Lead', { content_name: 'windows' }], checkout: ['InitiateCheckout', { value: 35, currency: 'EUR' }] };
  document.addEventListener('click', (e) => {
    const a = e.target.closest && e.target.closest('[data-ev]');
    if (!a || !granted) return;
    const ev = a.dataset.ev;
    gtag('event', ev.replace(/-/g, '_'), { page_language: C.lang });
    if (C.gads && C.gadsLabels && C.gadsLabels[ev]) gtag('event', 'conversion', { send_to: C.gads + '/' + C.gadsLabels[ev] });
    if (C.meta && window.fbq && META[ev]) fbq('track', META[ev][0], META[ev][1]);
  });

  function banner() {
    const t = C.text || {};
    const box = document.createElement('div');
    box.className = 'consent';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-label', t.more || 'Privacy');
    box.innerHTML = `<p>${t.msg} <a href="${C.privacy}">${t.more}</a></p><div><button type="button" data-c="no">${t.no}</button><button type="button" data-c="yes" class="yes">${t.yes}</button></div>`;
    box.addEventListener('click', (e) => {
      const c = e.target.dataset && e.target.dataset.c;
      if (!c) return;
      save(c);
      if (c === 'yes') grant();
      box.remove();
    });
    document.body.appendChild(box);
  }

  // Footer "Cookies" link reopens the choice.
  window.hlasConsent = () => { document.querySelector('.consent')?.remove(); banner(); };

  const state = read();
  if (state === 'yes') grant();
  else if (state !== 'no') {
    if (document.body) banner(); else document.addEventListener('DOMContentLoaded', banner);
  }
})();
