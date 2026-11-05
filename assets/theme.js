/* Edge-Ops theme switcher. Classic script, no build, works from file:// (load it in <head>, before paint).
   Each theme is one file in assets/themes/<id>.css that sets tokens on :root[data-theme=<id>].
   Switching theme = setting that one attribute; this script does it and remembers the choice.
   To add a theme: add its CSS file, link it in the pages, and add one entry to THEMES below.
   Fleet Night watch is the default (SCOPE's dark). "System" follows prefers-color-scheme and DEFAULTS:
   Night watch when the OS is dark, Phoenix light when it is light. The picker still lists every theme. */
(function () {
  'use strict';
  var THEMES = [
    { id: 'phoenix-dark', label: 'Phoenix dark', scheme: 'dark' },
    { id: 'phoenix-light', label: 'Phoenix light', scheme: 'light' },
    { id: 'fleet-night-watch', label: 'Fleet Night watch', scheme: 'dark' },
    { id: 'fleet-chart-room', label: 'Fleet Chart room', scheme: 'light' }
  ];
  var DEFAULTS = { dark: 'fleet-night-watch', light: 'phoenix-light' };
  var DEFAULT_PREF = 'fleet-night-watch';
  var KEY = 'edge-ops-theme', root = document.documentElement;
  var mq = window.matchMedia ? window.matchMedia('(prefers-color-scheme: light)') : null;

  function find(id) { for (var i = 0; i < THEMES.length; i++) { if (THEMES[i].id === id) return THEMES[i]; } return null; }
  // Only 'system' or a registered theme id counts; anything else (a removed or renamed theme) falls back to 'system'.
  function valid(p) { return p === 'system' || !!find(p); }
  function load() { try { var p = localStorage.getItem(KEY); return valid(p) ? p : DEFAULT_PREF; } catch (e) { return DEFAULT_PREF; } }
  function save(p) { try { if (p === DEFAULT_PREF) localStorage.removeItem(KEY); else localStorage.setItem(KEY, p); } catch (e) {} }
  function resolve(p) { return (p !== 'system' && find(p)) || find(DEFAULTS[mq && mq.matches ? 'light' : 'dark']) || THEMES[0]; }
  function apply(p) {
    var t = resolve(p);
    root.setAttribute('data-theme', t.id);
    root.classList.toggle('light', t.scheme === 'light'); // kit.css light-mode rules (badges, hover) key on .light
    return t;
  }

  var pref = load();
  apply(pref);
  if (mq) {
    var onChange = function () { if (pref === 'system') apply(pref); };
    if (mq.addEventListener) mq.addEventListener('change', onChange); else if (mq.addListener) mq.addListener(onChange);
  }

  window.EdgeTheme = {
    themes: THEMES.slice(),
    get preference() { return pref; },
    get current() { return root.getAttribute('data-theme'); },
    set: function (p) { pref = valid(p) ? p : 'system'; save(pref); return apply(pref); }
  };

  // Fill every <select data-theme-select> with System + the registered themes.
  function bind() {
    var sels = document.querySelectorAll('select[data-theme-select]');
    for (var i = 0; i < sels.length; i++) {
      var s = sels[i];
      if (s.options.length === 0) {
        var o = document.createElement('option'); o.value = 'system'; o.textContent = 'System default'; s.appendChild(o);
        THEMES.forEach(function (t) { var x = document.createElement('option'); x.value = t.id; x.textContent = t.label; s.appendChild(x); });
      }
      s.value = pref;
      if (!s.hasAttribute('data-theme-bound')) {
        s.setAttribute('data-theme-bound', '');
        s.addEventListener('change', function (e) { window.EdgeTheme.set(e.target.value); sync(); });
      }
    }
  }
  function sync() {
    var all = document.querySelectorAll('select[data-theme-select]');
    for (var j = 0; j < all.length; j++) all[j].value = pref;
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind); else bind();
  // Another tab changed the theme: follow it.
  window.addEventListener('storage', function (e) { if (e.key === KEY) { pref = load(); apply(pref); sync(); } });
})();
