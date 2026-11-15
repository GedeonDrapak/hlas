// Orb in the demo pill in place of the status dot: grey and still while idle,
// green while listening, grey and moving while transcribing.
// Engine: thinking-orbs 0.3.2 by Jakub Antalik (MIT), vendor/thinking-orbs/.
import { MODE_FRAMES, resolvePreset, paintFrame } from './vendor/thinking-orbs/engine.es.js';

const SIZE = 32; // presets exist for 20, 32 and 64
const GREEN = { r: 0, g: 230, b: 122 };
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const { mode, speed, opts } = resolvePreset('breathing', SIZE);
const frameFn = MODE_FRAMES[mode];

function mount(canvas) {
  const dpr = Math.min(2, devicePixelRatio || 1);
  canvas.width = Math.round(SIZE * dpr);
  canvas.height = Math.round(SIZE * dpr);
  const ctx = canvas.getContext('2d');
  let tint, raf = 0, running = false;
  const draw = (t) => {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, SIZE, SIZE);
    paintFrame(ctx, frameFn(SIZE, t, opts), true, tint);
  };
  const loop = () => { draw((performance.now() / 1000) * speed); if (running) raf = requestAnimationFrame(loop); };
  const stop = () => { running = false; cancelAnimationFrame(raf); };
  draw(0.6);
  return {
    /** 'idle' | 'rec' | 'busy' */
    set(state) {
      tint = state === 'rec' ? GREEN : undefined;
      if (state === 'idle' || reduced) { stop(); draw(0.6); return; }
      if (!running) { running = true; raf = requestAnimationFrame(loop); }
    },
  };
}

const canvas = document.getElementById('orb');
if (canvas) window.HlasOrb = mount(canvas);
