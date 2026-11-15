// Server-rendered pages: the post-checkout welcome page and small notices.
// Same look as the landing page: #121212, Satoshi fallback stack, no borders.

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function shell(title: string, body: string): Response {
  const html = `<!doctype html><html lang="cs"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex">
<title>${esc(title)}</title>
<style>
:root{--bg:#121212;--s1:#1b1b1b;--s2:#242424;--fg:#EDEDED;--fg2:#A3A3A3;--fg3:#737373;--brand:#00E67A}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--fg);font-family:'Satoshi',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;-webkit-font-smoothing:antialiased;line-height:1.5;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:32px 16px;
background-image:radial-gradient(80% 60% at 50% 110%,rgba(150,110,220,.22),transparent 60%)}
main{width:100%;max-width:560px}
.brand{display:flex;align-items:center;gap:9px;font-weight:700;letter-spacing:.22em;font-size:14px;margin-bottom:34px}
h1{font-size:clamp(30px,6vw,40px);line-height:1.08;letter-spacing:-.025em;font-weight:700}
p{color:var(--fg2);margin-top:12px;font-size:16px}
.card{margin-top:28px;background:var(--s1);border-radius:20px;padding:22px}
.label{font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--fg3)}
.key{margin-top:10px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
code{font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:15px;background:var(--s2);border-radius:12px;padding:12px 14px;flex:1 1 280px;word-break:break-all;color:var(--fg)}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:13px 22px;border-radius:999px;font:inherit;font-weight:600;font-size:15px;cursor:pointer;border:0;text-decoration:none}
.primary{background:var(--brand);color:#06130C}
.ghost{background:var(--s2);color:var(--fg)}
.row{display:flex;gap:10px;flex-wrap:wrap;margin-top:22px}
ol{margin:12px 0 0 18px;color:var(--fg2);font-size:15px}
li{margin-top:6px}
small{display:block;margin-top:22px;color:var(--fg3);font-size:13px}
a{color:var(--fg)}
</style></head><body><main>
<div class="brand"><svg width="20" height="20" viewBox="0 0 34 34" aria-hidden="true"><rect x="4" y="9" width="7" height="16" rx="3.5" fill="#00E67A"/><rect x="15" y="3" width="7" height="28" rx="3.5" fill="#EDEDED"/><circle cx="29" cy="17" r="3.5" fill="#00E67A"/></svg>HLAS</div>
${body}
</main></body></html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
  });
}

export function welcomePage(key: string, email: string | null, portalPath: string): Response {
  const deepLink = `hlas://activate?key=${encodeURIComponent(key)}`;
  return shell("Hlas Cloud je aktivní", `
<h1>Hlas Cloud je aktivní.</h1>
<p>Díky za předplatné${email ? `, ${esc(email)}` : ""}. Faktura ti přijde e-mailem. Teď stačí propojit aplikaci.</p>
<div class="row"><a class="btn primary" href="${esc(deepLink)}">Otevřít Hlas a aktivovat</a></div>
<div class="card">
  <div class="label">Licenční klíč / License key</div>
  <div class="key"><code id="k">${esc(key)}</code><button class="btn ghost" id="c" type="button">Kopírovat</button></div>
  <ol>
    <li>Otevři Hlas, v Nastavení vyber engine <b>Hlas Cloud</b>.</li>
    <li>Vlož klíč. Platí na všech tvých počítačích s Macem i Windows.</li>
    <li>Klíč si ulož, nikomu ho nedávej.</li>
  </ol>
</div>
<small>Hlas Cloud is active. Open Hlas, choose the Hlas Cloud engine in Settings and paste the key above.
Faktury a zrušení: <a href="${esc(portalPath)}">zákaznický portál</a>.</small>
<script>
document.getElementById('c').onclick=async()=>{try{await navigator.clipboard.writeText(document.getElementById('k').textContent);document.getElementById('c').textContent='Zkopírováno'}catch(e){}};
</script>`);
}

export function noticePage(title: string, message: string, status = 200): Response {
  const res = shell(title, `<h1>${esc(title)}</h1><p>${esc(message)}</p>`);
  return new Response(res.body, { status, headers: res.headers });
}

/** Lost-key page: e-mail, then the 6-digit code, then the key. */
export function recoverPage(available: boolean): Response {
  if (!available) {
    return shell("Ztracený klíč", `
<h1>Ztratil jsi licenční klíč?</h1>
<p>Obnovení e-mailem spouštíme za pár dní. Do té doby najdeš klíč v aplikaci Hlas na počítači, kde už ho máš (Nastavení, Hlas Cloud), nebo nám napiš z adresy, kterou jsi platil.</p>
<small>Lost your license key? E-mail recovery is coming in a few days. Until then the key is in Hlas Settings on a computer where you already use it.</small>`);
  }
  return shell("Ztracený klíč", `
<h1>Ztracený licenční klíč</h1>
<p>Zadej e-mail, kterým jsi platil. Pošleme ti kód a hned potom ukážeme klíč.</p>
<div class="card">
  <form id="f1"><div class="label">E-mail</div><div class="key"><input id="em" type="email" required autocomplete="email"><button class="btn primary" type="submit">Poslat kód</button></div></form>
  <form id="f2" hidden><div class="label">Kód z e-mailu / Code</div><div class="key"><input id="cd" inputmode="numeric" maxlength="6" required autocomplete="one-time-code"><button class="btn primary" type="submit">Ověřit</button></div></form>
  <div id="out" hidden><div class="label">Licenční klíč / License key</div><div class="key"><code id="k"></code></div><div class="row"><a class="btn primary" id="open" href="#">Otevřít Hlas a aktivovat</a></div></div>
  <p id="msg"></p>
</div>
<small>Lost your license key? Enter the e-mail you paid with, then the code we send you.</small>
<style>input{font:inherit;font-size:15px;background:var(--s2);color:var(--fg);border:0;border-radius:12px;padding:12px 14px;flex:1 1 240px}</style>
<script>
const $=(i)=>document.getElementById(i),msg=(t)=>{$('msg').textContent=t};
const post=(p,b)=>fetch(p,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)});
$('f1').onsubmit=async(e)=>{e.preventDefault();const r=await post('/v1/auth/email/start',{email:$('em').value});
 if(r.ok){$('f1').hidden=true;$('f2').hidden=false;msg('Pokud k e-mailu patří předplatné, kód je na cestě. Platí 10 minut.')}else msg('To nevypadá jako e-mail.')};
$('f2').onsubmit=async(e)=>{e.preventDefault();const r=await post('/v1/auth/email/verify',{email:$('em').value,code:$('cd').value});
 const j=await r.json().catch(()=>({}));if(j.key){$('f2').hidden=true;$('out').hidden=false;$('k').textContent=j.key;$('open').href='hlas://activate?key='+encodeURIComponent(j.key);msg('')}else msg('Kód nesedí nebo vypršel.')};
</script>`);
}
