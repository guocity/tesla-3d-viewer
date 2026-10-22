const chevron = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="m7 10 5 5 5-5"/></svg>';
const car = '<svg viewBox="0 0 80 36" fill="none"><path d="m9 24 3-8 14-2 9-9h21l11 10 7 3 2 7H9Z" fill="currentColor" opacity=".16"/><path d="m9 24 3-8 14-2 9-9h21l11 10 7 3 2 7H9ZM28 14h35M40 6l-3 8" stroke="currentColor" stroke-width="1.5"/><circle cx="24" cy="25" r="5" fill="currentColor"/><circle cx="64" cy="25" r="5" fill="currentColor"/></svg>';
const names = {
  bmw: ['BMW XM', 'Original scene'], cybertruck: ['Cybertruck', 'Stainless steel · Truck'],
  model3_high: ['Model 3', 'Highland'], modely_high: ['Model Y', 'Latest generation'],
  models_plaid: ['Model S', 'Palladium'], modelx_plaid: ['Model X', 'Palladium'],
  bayberry: ['Model Y', 'Juniper · Bayberry'], bayberry_e41: ['Model Y', 'Bayberry E41'], bayberry_e80: ['Model Y', 'Bayberry E80'],
  semi: ['Tesla Semi', 'Electric truck'], poppyseed: ['Model 3', 'Poppyseed'],
  models_legacy: ['Model S', 'Legacy'], modelx_legacy: ['Model X', 'Legacy'],
};
export function createModelPicker(select) {
  select.hidden = true;
  const host = document.createElement('div');
  host.className = 'model-picker';
  host.innerHTML = `<button class="model-trigger" type="button" aria-haspopup="dialog" aria-expanded="false" aria-controls="model-menu"><span class="model-icon">${car}</span><span class="model-current"><span class="model-eyebrow">YOUR GARAGE</span><span class="model-name">Choose a vehicle</span></span><span class="model-chevron">${chevron}</span></button><section id="model-menu" class="model-menu" role="dialog" aria-label="Choose your vehicle" hidden><div class="model-menu-heading"><div><span class="model-eyebrow">THE COLLECTION</span><h2>Find your next view.</h2></div><button class="model-close" type="button" aria-label="Close vehicle picker">×</button></div><label class="model-search"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/></svg><input type="search" placeholder="Search models or generations" aria-label="Search vehicles" autocomplete="off"></label><div class="model-filters" role="group" aria-label="Vehicle brand"><button type="button" data-filter="all" aria-pressed="true">All models</button><button type="button" data-filter="tesla" aria-pressed="false">Tesla</button><button type="button" data-filter="bmw" aria-pressed="false">BMW</button><span class="model-count"></span></div><div class="model-options" role="group" aria-label="Available vehicles"></div><div class="model-footer"><span><i></i> Same scene. A different perspective.</span><kbd>ESC</kbd></div></section>`;
  select.before(host);
  const trigger = host.querySelector('.model-trigger'), menu = host.querySelector('.model-menu'), search = host.querySelector('input'), options = host.querySelector('.model-options');
  let filter = 'all';
  function close(focus = false) { menu.hidden = true; trigger.setAttribute('aria-expanded', 'false'); if (focus) trigger.focus(); }
  function render() {
    const selected = names[select.value] || [select.selectedOptions[0]?.textContent || 'Choose a vehicle', ''];
    host.querySelector('.model-name').textContent = selected[0];
    trigger.setAttribute('aria-label', `Change vehicle, currently ${selected.join(' · ')}`);
    options.replaceChildren();
    let count = 0;
    for (const option of select.options) {
      const [name, subtitle] = names[option.value] || [option.textContent, ''];
      const brand = option.value === 'bmw' ? 'bmw' : 'tesla';
      if (filter !== 'all' && filter !== brand) continue;
      if (!`${name} ${subtitle} ${brand}`.toLowerCase().includes(search.value.toLowerCase().trim())) continue;
      count++;
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'model-option'; button.dataset.value = option.value;
      button.setAttribute('aria-pressed', String(option.value === select.value));
      button.innerHTML = `<span class="model-thumbnail">${car}</span><span class="model-option-copy"><strong></strong><span></span></span><span class="model-check" aria-hidden="true">${option.value === select.value ? '✓' : '↗'}</span>`;
      button.querySelector('strong').textContent = name; button.querySelector('.model-option-copy > span').textContent = subtitle;
      button.onclick = () => { if (select.value !== option.value) { select.value = option.value; select.dispatchEvent(new Event('change', { bubbles: true })); } render(); close(true); };
      options.append(button);
    }
    host.querySelector('.model-count').textContent = `${count} ${count === 1 ? 'vehicle' : 'vehicles'}`;
    if (!count) { const empty = document.createElement('p'); empty.className = 'model-empty'; empty.textContent = 'No matches. Try another model or generation.'; options.append(empty); }
  }
  trigger.onclick = () => { if (!menu.hidden) return close(); search.value = ''; render(); menu.hidden = false; trigger.setAttribute('aria-expanded', 'true'); search.focus(); };
  host.querySelector('.model-close').onclick = () => close(true);
  search.oninput = render;
  host.querySelectorAll('[data-filter]').forEach(button => button.onclick = () => { filter = button.dataset.filter; host.querySelectorAll('[data-filter]').forEach(b => b.setAttribute('aria-pressed', String(b === button))); render(); });
  host.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !menu.hidden) { event.preventDefault(); event.stopPropagation(); close(true); }
    if (menu.hidden) return;
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      const choices = [...options.querySelectorAll('button')];
      const current = choices.indexOf(document.activeElement);
      const next = event.key === 'ArrowDown' ? (current + 1) % choices.length : (current <= 0 ? choices.length - 1 : current - 1);
      if (choices[next]) { event.preventDefault(); choices[next].focus(); }
    }
    if (event.key === 'Tab') {
      const focusable = [...menu.querySelectorAll('button,input')]; const first = focusable[0], last = focusable.at(-1);
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });
  document.addEventListener('pointerdown', event => { if (!host.contains(event.target)) close(); });
  select.addEventListener('change', render);
  new MutationObserver(render).observe(select, { childList: true });
  render();
  return { refresh: render };
}
