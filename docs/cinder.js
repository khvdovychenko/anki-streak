// Cinder: a grumpy lump of coal that lives on your streak.
// cinderSVG({ stage, mood, size }) returns an SVG string.
//   stage: 0..5, see STAGES (grows with the streak)
//   mood:  'lit' | 'partial' | 'fading' | 'dying' | 'dead' | 'new'

const STAGES = [
  { name: 'Ash', from: 0 },
  { name: 'Spark', from: 1 },
  { name: 'Smoulder', from: 7 },
  { name: 'Blaze', from: 30 },
  { name: 'Inferno', from: 100 },
  { name: 'Volcano', from: 365 },
];

function stageFor(streak) {
  let s = 0;
  STAGES.forEach((st, i) => { if (streak >= st.from) s = i; });
  return s;
}

const CRACKS = [
  'M-34 -6 L-27 1', 'M27 -15 L33 -8', 'M-20 29 L-11 32', 'M13 29 L22 25',
  'M-31 13 L-25 19', 'M29 9 L34 3', 'M-9 -28 L-1 -24 L5 -27', 'M-2 35 L5 32',
];

function flamePath(h) {
  // flame tongue rising from (0,0) upward, height h
  const w = h * 0.42;
  return `M0 ${-h} C${w * 0.5} ${-h * 0.7} ${w} ${-h * 0.5} ${w * 0.95} ${-h * 0.22}
    C${w * 0.9} ${-h * 0.02} ${w * 0.45} 0 0 0 C${-w * 0.45} 0 ${-w * 0.9} ${-h * 0.02} ${-w * 0.95} ${-h * 0.22}
    C${-w} ${-h * 0.42} ${-w * 0.45} ${-h * 0.5} ${-w * 0.3} ${-h * 0.72}
    C${-w * 0.15} ${-h * 0.6} ${-w * 0.05} ${-h * 0.55} ${w * 0.1} ${-h * 0.5}
    C${-w * 0.05} ${-h * 0.65} ${-w * 0.05} ${-h * 0.85} 0 ${-h}Z`;
}

function cinderSVG({ stage = 1, mood = 'lit', size = 160, uid = Math.random().toString(36).slice(2, 7) } = {}) {
  const dead = mood === 'dead' || stage === 0;
  const scale = [0.86, 0.86, 0.95, 1.03, 1.1, 1.16][stage];
  const flameH = dead ? 0 : [0, 26, 36, 48, 58, 66][stage] * ({ lit: 1, partial: 0.8, new: 0.7, fading: 0.5, dying: 0.3 }[mood] ?? 1);
  const flameOp = { lit: 1, partial: 0.9, new: 0.85, fading: 0.6, dying: 0.45 }[mood] ?? 1;
  const body = dead ? '#8C8580' : stage === 5 ? '#4A2620' : '#3B3632';
  const glow = dead ? '#6E6862' : mood === 'dying' ? '#A8521A' : mood === 'fading' ? '#D9661A' : '#FF5A00';
  const nCracks = dead ? 3 : [3, 2, 3, 5, 6, 8][stage];
  const eyeC = dead ? '#3B3632' : '#F6EEE6';

  let g = '';

  // back flames for big stages
  if (!dead && stage >= 4) {
    g += `<g class="cn-flame" opacity="${flameOp * 0.8}"><path d="${flamePath(flameH * 0.7)}" transform="translate(-24 -18) rotate(-18)" fill="#FF5A00"/>
      <path d="${flamePath(flameH * 0.7)}" transform="translate(24 -18) rotate(18)" fill="#FF5A00"/></g>`;
  }
  // main flame
  if (!dead && flameH > 0) {
    g += `<g transform="translate(0 -26)"><g class="cn-flame" opacity="${flameOp}">
      <path d="${flamePath(flameH)}" fill="#FF7A1A"/>
      <path d="${flamePath(flameH * 0.58)}" fill="#FFD25A"/></g></g>`;
  }
  // smoke when dead
  if (dead) {
    g += `<g class="cn-smoke" fill="none" stroke="#A8A29C" stroke-width="3" stroke-linecap="round" opacity=".7">
      <path d="M-4 -34 C-12 -44 4 -50 -4 -62"/><path d="M8 -36 C2 -46 16 -52 8 -64" opacity=".6"/></g>`;
  }
  // body
  g += `<path d="M-38 0 C-40 -22 -20 -34 -4 -32 C16 -34 38 -24 38 0 C40 22 24 38 0 38 C-24 40 -38 24 -38 0Z" fill="${body}"/>`;
  // lava drips for volcano
  if (stage === 5 && !dead) {
    g += `<path d="M-30 6 C-31 14 -27 16 -27 22 C-27 26 -32 26 -32 22" fill="#FF5A00"/><path d="M30 2 C32 10 28 12 29 18 C29 21 33 21 33 17" fill="#FF5A00"/>`;
  }
  // cracks
  g += `<g stroke="${glow}" stroke-width="2.2" stroke-linecap="round" fill="none" class="${dead ? '' : 'cn-glow'}">${CRACKS.slice(0, nCracks).map((d) => `<path d="${d}"/>`).join('')}</g>`;

  // face
  if (dead) {
    g += `<g stroke="${eyeC}" stroke-width="2.6" stroke-linecap="round">
      <path d="M-19 -6 L-9 4 M-9 -6 L-19 4"/><path d="M9 -6 L19 4 M19 -6 L9 4"/><path d="M-6 16 L6 16"/></g>`;
  } else {
    // eyes: half-lidded grumpy by default
    const pupil = (x) => `<circle class="cn-eye" cx="${x}" cy="0" r="3.4" fill="${eyeC}"/>`;
    let brows = '', mouth = '', extra = '';
    if (mood === 'lit') {
      brows = `<path d="M-22 -5 L-6 -4 M6 -4 L22 -5" stroke="${eyeC}" stroke-width="2.6" stroke-linecap="round"/>`;
      mouth = `<path d="M-6 16 Q3 19 10 13" stroke="${eyeC}" stroke-width="2.4" fill="none" stroke-linecap="round"/>`;
    } else if (mood === 'partial' || mood === 'new') {
      brows = `<path d="M-22 -6 L-6 -5 M6 -9 L22 -6" stroke="${eyeC}" stroke-width="2.6" stroke-linecap="round"/>`;
      mouth = `<path d="M-7 16 L8 15" stroke="${eyeC}" stroke-width="2.4" stroke-linecap="round"/>`;
    } else {
      // fading / dying: worried brows, wobbly mouth, sweat
      brows = `<path d="M-21 -10 L-8 -6 M8 -6 L21 -10" stroke="${eyeC}" stroke-width="2.6" stroke-linecap="round"/>`;
      mouth = `<path d="M-8 17 Q-4 13 0 17 Q4 21 8 17" stroke="${eyeC}" stroke-width="2.2" fill="none" stroke-linecap="round"/>`;
      extra = `<path d="M27 -14 C25 -8 25 -5 28 -4 C31 -5 30 -9 27 -14Z" fill="#7CC4FF"/>`;
      if (mood === 'dying') extra += `<path d="M-30 -12 C-32 -6 -32 -3 -29 -2 C-26 -3 -27 -7 -30 -12Z" fill="#7CC4FF"/>`;
    }
    g += `${brows}${pupil(-14)}${pupil(14)}${mouth}${extra}`;
  }

  // embers for blaze+
  if (!dead && stage >= 3 && (mood === 'lit' || mood === 'partial')) {
    const ember = (x, d) => `<circle class="cn-ember" cx="${x}" cy="-20" r="1.8" fill="#FFB02E" style="animation-delay:${d}s"/>`;
    g += ember(-26, 0) + ember(22, 0.7) + ember(-8, 1.4) + (stage >= 4 ? ember(30, 1.0) + ember(-34, 1.8) : '');
  }

  const vb = `-80 -110 160 160`;
  return `<svg class="cinder mood-${mood}" width="${size}" height="${size}" viewBox="${vb}" role="img" aria-label="${STAGES[dead ? 0 : stage].name}, ${mood}">
    <g transform="translate(0 6) scale(${scale})"><g class="cn-body">${g}</g></g></svg>`;
}

const CINDER_CSS = `
.cinder { overflow: visible; display: block; margin: 0 auto; }
.cinder .cn-flame { transform-box: fill-box; transform-origin: 50% 100%; animation: cn-flicker 2.2s ease-in-out infinite; }
.cinder.mood-fading .cn-flame { animation-duration: 3.6s; }
.cinder.mood-dying .cn-flame { animation: cn-gutter 1.1s ease-in-out infinite; }
.cinder .cn-glow { animation: cn-pulse 2.8s ease-in-out infinite; }
.cinder.mood-dying .cn-glow, .cinder.mood-fading .cn-glow { animation-duration: 5s; }
.cinder .cn-ember { animation: cn-rise 2.6s ease-out infinite; }
.cinder .cn-eye { transform-box: fill-box; transform-origin: 50% 50%; animation: cn-blink 4.6s infinite; }
.cinder.mood-lit .cn-body { transform-box: fill-box; transform-origin: 50% 100%; animation: cn-hop .7s ease-out 1; }
.cinder .cn-smoke { animation: cn-smoke 4s ease-in-out infinite; }
@keyframes cn-flicker { 0%,100% { transform: scale(1,1) rotate(0); } 35% { transform: scale(1.05,.96) rotate(-2deg); } 70% { transform: scale(.97,1.04) rotate(2deg); } }
@keyframes cn-gutter { 0%,100% { transform: scale(1); opacity: 1; } 50% { transform: scale(.7,.8); opacity: .55; } }
@keyframes cn-pulse { 0%,100% { opacity: 1; } 50% { opacity: .55; } }
@keyframes cn-rise { 0% { transform: translateY(0); opacity: 0; } 15% { opacity: 1; } 100% { transform: translateY(-60px); opacity: 0; } }
@keyframes cn-blink { 0%,94%,100% { transform: scaleY(1); } 97% { transform: scaleY(.1); } }
@keyframes cn-hop { 0% { transform: translateY(0); } 35% { transform: translateY(-10px) scale(1.04,.97); } 70% { transform: translateY(0) scale(.97,1.03); } 100% { transform: none; } }
@keyframes cn-smoke { 0%,100% { transform: translateY(0); opacity: .7; } 50% { transform: translateY(-6px); opacity: .35; } }
@media (prefers-reduced-motion: reduce) { .cinder * { animation: none !important; } }
`;
