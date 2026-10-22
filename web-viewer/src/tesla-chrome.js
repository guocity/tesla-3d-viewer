import { teslaIcon } from './tesla-icons.js';
export function createTeslaChrome({ panel, controls, appearance, quality, setTemperature, setFan, setDefrost }) {
  const brand = document.createElement('span'); brand.className = 'tesla-brand'; brand.innerHTML = teslaIcon('wordmark',104);brand.setAttribute('aria-label','Tesla');
  panel.prepend(brand); panel.setAttribute('aria-label', 'Tesla vehicle status');
  const status = document.createElement('div'); status.className = 'tesla-top-status';
  status.innerHTML = '<span class="tesla-park">P <small>Parked</small></span><time></time><span class="tesla-battery" aria-label="Battery 80 percent">▰ <span>80%</span></span>';
  panel.append(status);
  const clock = status.querySelector('time');
  function updateClock() { clock.textContent = new Date().toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}); }
  updateClock(); setInterval(updateClock, 60000);
  const bar = document.createElement('nav'); bar.className = 'tesla-bottom'; bar.setAttribute('aria-label', 'Tesla controls');
  bar.innerHTML = '<div class="tesla-controls-slot"></div><div class="tesla-climate"><button data-cool aria-label="Decrease cabin temperature">‹</button><span data-temperature aria-live="polite">21.5°</span><button data-warm aria-label="Increase cabin temperature">›</button></div><button data-fan aria-label="Cabin fan" aria-pressed="false"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="2"/><path d="M12 10C3 8 8 1 12 4c2 1 2 4 0 6Zm2 3c7-6 11 2 6 4-2 1-5-1-6-4Zm-3 1c2 9-7 9-7 4 0-3 4-4 7-4Z"/></svg></button><button data-defrost aria-label="Rear defrost" aria-pressed="false"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 11v9h18v-9M7 16V4m5 12V4m5 12V4M5 6l2-2 2 2m1 0 2-2 2 2m1 0 2-2 2 2"/></svg></button><div class="tesla-bar-spacer"></div><button data-settings aria-label="Rendering quality" aria-pressed="false">Low</button>';
  bar.querySelector('.tesla-controls-slot').append(controls);
  controls.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4 15 1-5 3-4h8l3 4 1 5v4h-3v-2H7v2H4v-4Zm2-5h12M4 14h3m10 0h3"/></svg><span>Controls</span>';
  bar.append(appearance); document.body.append(bar);
  bar.querySelector('[data-fan]').innerHTML = teslaIcon('fan');
  bar.querySelector('[data-defrost]').innerHTML = teslaIcon('defrost');
  controls.innerHTML = `${teslaIcon('controls',36)}<span>Controls</span>`;
  controls.setAttribute('aria-label','Vehicle controls');
  let temperature = 21.5, fan = false, defrost = false;
  const changeTemperature = delta => { temperature = Math.min(28, Math.max(16, temperature + delta)); bar.querySelector('[data-temperature]').textContent = `${temperature.toFixed(1)}°`; setTemperature(temperature); };
  bar.querySelector('[data-cool]').onclick = () => changeTemperature(-.5);
  bar.querySelector('[data-warm]').onclick = () => changeTemperature(.5);
  bar.querySelector('[data-fan]').onclick = e => { fan = !fan; e.currentTarget.setAttribute('aria-pressed', String(fan)); setFan(fan); };
  bar.querySelector('[data-defrost]').onclick = e => { defrost = !defrost; e.currentTarget.setAttribute('aria-pressed', String(defrost)); setDefrost(defrost); };
  quality.hidden = true;
  const settingsButton = bar.querySelector('[data-settings]');
  function updateQuality() {
    const high = quality.value === 'high';
    settingsButton.textContent = high ? 'High' : 'Low';
    settingsButton.setAttribute('aria-pressed', String(high));
    settingsButton.setAttribute('aria-label', `Rendering quality: ${high ? 'High' : 'Low'}. Tap to switch to ${high ? 'Low' : 'High'}`);
  }
  settingsButton.onclick = () => {
    quality.value = quality.value === 'high' ? 'smooth' : 'high';
    quality.dispatchEvent(new Event('change', { bubbles: true }));
  };
  quality.addEventListener('change', updateQuality);
  updateQuality();
  return { closePanels() {} };
}
