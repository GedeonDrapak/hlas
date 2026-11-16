// Comparison pages: year toggle on cost charts and the own-key calculator.
(() => {
  const fmt = (n, cs) => {
    const s = (Math.round(n * 100) / 100).toFixed(2).replace(/\.00$/, '');
    return cs ? s.replace('.', ',') : s;
  };

  document.querySelectorAll('.costchart').forEach((fig) => {
    const cs = fig.dataset.cs === '1';
    const box = fig.querySelector('.cc-rows');
    const rows = [...fig.querySelectorAll('.cc-row')];
    const cost = (r, n) => (r.dataset.o !== '' ? +r.dataset.o : +r.dataset.y * n);
    const show = (n) => {
      const max = Math.max(...rows.map((r) => cost(r, n)), 1);
      rows.sort((a, b) => cost(a, n) - cost(b, n)).forEach((r) => {
        const c = cost(r, n);
        r.querySelector('i').style.setProperty('--w', ((c / max) * 100).toFixed(1) + '%');
        r.querySelector('.cc-val').textContent = c === 0 ? (cs ? 'zdarma' : 'free') : fmt(c, cs) + ' €';
        box.appendChild(r);
      });
      fig.querySelectorAll('.cc-toggle button').forEach((b) => b.setAttribute('aria-pressed', String(+b.dataset.n === n)));
    };
    fig.querySelectorAll('.cc-toggle button').forEach((b) => b.addEventListener('click', () => show(+b.dataset.n)));
  });

  // Own Groq key: $0.04 per audio hour, $1 = €0.90481, 30 days a month.
  document.querySelectorAll('.calc').forEach((el) => {
    const cs = el.dataset.cs === '1';
    const input = el.querySelector('input');
    const update = () => {
      const min = +input.value;
      const month = (min / 60) * 30 * 0.04 * 0.90481;
      el.querySelector('.calc-min-out').textContent = min >= 60 ? `${fmt(min / 60, cs)} h` : `${min} min`;
      el.querySelector('.calc-key').textContent = fmt(month, cs) + ' €';
      el.classList.toggle('cloud-wins', month > 35 / 12);
    };
    input.addEventListener('input', update);
    update();
  });
})();
