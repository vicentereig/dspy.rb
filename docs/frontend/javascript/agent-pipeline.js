// "The shape of an agent" horizontal pipeline.
// Native CSS scroll-snap already works (swipe / trackpad / scrollbar).
// This progressively enhances it with arrows, step dots, a counter, and
// keyboard support. If it doesn't run, the filmstrip still scrolls.

function initAgentPipeline() {
  const root = document.querySelector('[data-agent-pipeline]');
  if (!root) return;

  const track = root.querySelector('[data-agent-track]');
  const controls = root.querySelector('[data-agent-controls]');
  const prev = root.querySelector('[data-agent-prev]');
  const next = root.querySelector('[data-agent-next]');
  const dotsWrap = root.querySelector('[data-agent-dots]');
  const status = root.querySelector('[data-agent-status]');
  const panels = Array.from(track.querySelectorAll('.agent-panel'));
  if (!controls || panels.length < 2) return;

  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const horizontal = window.matchMedia('(min-width: 1024px)');
  const pad = (n) => String(n + 1).padStart(2, '0');
  const clamp = (i) => Math.max(0, Math.min(panels.length - 1, i));
  // Reference panel 0 so the padded/bleed track still computes correct offsets.
  const panelLeft = (i) => panels[i].offsetLeft - panels[0].offsetLeft;

  // Controls only make sense in the horizontal (desktop) layout; on mobile the
  // panels stack vertically and scroll with the page. Use inline display (not the
  // `hidden` attribute) since the layout class would otherwise override it.
  function syncControls() {
    controls.hidden = false;
    controls.style.display = horizontal.matches ? 'flex' : 'none';
  }

  const dots = panels.map((_, i) => {
    const li = document.createElement('li');
    const b = document.createElement('button');
    b.type = 'button';
    b.setAttribute('aria-label', `Go to step ${i + 1}`);
    b.style.cssText =
      'width:0.5rem;height:0.5rem;border:0;padding:0;border-radius:9999px;cursor:pointer;' +
      'background:var(--color-rule);transition:background-color .2s ease';
    b.addEventListener('click', () => goTo(i));
    li.appendChild(b);
    dotsWrap.appendChild(li);
    return b;
  });

  let active = -1;

  function render(i) {
    if (i === active) return;
    active = i;
    dots.forEach((d, di) => {
      d.style.background = di === i ? 'var(--color-accent)' : 'var(--color-rule)';
      if (di === i) d.setAttribute('aria-current', 'true');
      else d.removeAttribute('aria-current');
    });
    if (status) status.textContent = `${pad(i)} / ${pad(panels.length - 1)}`;
    prev.disabled = i === 0;
    next.disabled = i === panels.length - 1;
  }

  function goTo(i) {
    const t = clamp(i);
    track.scrollTo({ left: panelLeft(t), behavior: reduce ? 'instant' : 'smooth' });
    render(t); // optimistic; scroll listener keeps it honest for swipes
  }

  function nearest() {
    const x = track.scrollLeft;
    let best = 0;
    let bestDist = Infinity;
    panels.forEach((_, i) => {
      const d = Math.abs(panelLeft(i) - x);
      if (d < bestDist) { bestDist = d; best = i; }
    });
    return best;
  }

  prev.addEventListener('click', () => goTo(active - 1));
  next.addEventListener('click', () => goTo(active + 1));

  track.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowRight') { e.preventDefault(); goTo(active + 1); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); goTo(active - 1); }
  });

  // Align the code blocks: give every panel's header (numeral + title + intro)
  // the same height, so the code panels start at the same vertical offset no
  // matter how many lines each intro wraps to.
  const heads = panels.map((p) => p.querySelector('[data-agent-head]'));
  function equalizeHeads() {
    if (heads.some((h) => !h)) return;
    heads.forEach((h) => { h.style.minHeight = ''; });
    if (!horizontal.matches) return; // vertical stack: natural heights
    const max = Math.max(...heads.map((h) => h.getBoundingClientRect().height));
    heads.forEach((h) => { h.style.minHeight = `${Math.ceil(max)}px`; });
  }

  let raf = 0;
  track.addEventListener(
    'scroll',
    () => {
      if (raf) return;
      raf = requestAnimationFrame(() => { raf = 0; render(nearest()); });
    },
    { passive: true }
  );

  window.addEventListener('resize', () => { equalizeHeads(); render(nearest()); }, { passive: true });
  horizontal.addEventListener('change', () => { syncControls(); equalizeHeads(); render(nearest()); });

  syncControls();
  equalizeHeads();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(equalizeHeads);

  render(0);
}

if (document.readyState !== 'loading') initAgentPipeline();
else document.addEventListener('DOMContentLoaded', initAgentPipeline);
