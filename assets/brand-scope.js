/* SCOPE skin for the Edge-Ops hub. Classic script, no build, works from file://. Load it in <head> after theme.js.
   Switch it on with index.html?brand=scope (remembered in localStorage); ?brand=edgeops switches it off and restores the
   theme that was chosen before. With nothing in the URL and nothing remembered, the plain Edge-Ops hub renders unchanged.
   Same catalog, same tools, same data: only the name, the mark, the subtitle, the favicon and the theme change. */
(function () {
  'use strict';
  // The expansion wording is not settled. Change it here only: one word per letter; the page shows the initials in bold.
  var SCOPE_EXPANSION = 'Ship Continuity Operations Platform Environment';
  var SCOPE_NAME = 'SCOPE';
  var SCOPE_THEME = 'fleet-night-watch';
  var SCOPE_EMBLEM = 'assets/emblems/scope.svg';
  var SCOPE_SUBTITLE = 'Standalone utilities for app-whitelisted Windows: PowerShell 5.1, a Chrome-engine browser, no admin, no installs. Built on FleetHacker Edge-Ops.';
  var KEY = 'edge-ops-brand', PREV_THEME_KEY = 'edge-ops-brand-prev-theme';

  function get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function set(k, v) { try { if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) {} }
  var m = /[?&]brand=([^&#]*)/.exec(location.search), q = m ? decodeURIComponent(m[1]) : '';
  var theme = window.EdgeTheme;

  if (q === 'edgeops') {
    set(KEY, null);
    var prev = get(PREV_THEME_KEY); set(PREV_THEME_KEY, null);
    if (theme && prev !== null && theme.preference === SCOPE_THEME) theme.set(prev);
    return;
  }
  var on = q === 'scope' || (!q && get(KEY) === 'scope');
  if (!on) return;
  if (q === 'scope') set(KEY, 'scope');

  // The skin is the Fleet Night watch theme. Remember the earlier choice once, so ?brand=edgeops can put it back.
  if (theme) {
    if (get(PREV_THEME_KEY) === null && theme.preference !== SCOPE_THEME) set(PREV_THEME_KEY, theme.preference);
    theme.set(SCOPE_THEME);
  }
  document.documentElement.setAttribute('data-brand', 'scope');
  document.title = SCOPE_NAME;
  var icon = document.querySelector('link[rel="icon"]');
  if (icon) icon.href = SCOPE_EMBLEM;

  function skin() {
    var h1 = document.querySelector('header h1');
    if (!h1) return;
    h1.textContent = '';
    var im = document.createElement('img');
    im.className = 'emblem'; im.src = SCOPE_EMBLEM; im.alt = ''; im.setAttribute('aria-hidden', 'true'); im.width = 52; im.height = 52;
    var w = document.createElement('span'); w.textContent = SCOPE_NAME;
    h1.appendChild(im); h1.appendChild(w);

    var ex = document.createElement('p'); ex.className = 'scope-expansion';
    var words = SCOPE_EXPANSION.split(' ');
    for (var i = 0; i < words.length; i++) {
      var b = document.createElement('b'); b.textContent = words[i].charAt(0);
      ex.appendChild(b); ex.appendChild(document.createTextNode(words[i].slice(1) + (i < words.length - 1 ? ' ' : '')));
    }
    var sub = document.createElement('p'); sub.className = 'scope-subtitle'; sub.textContent = SCOPE_SUBTITLE;
    var p = h1.nextElementSibling;
    if (p && p.tagName === 'P') p.parentNode.replaceChild(sub, p); else h1.parentNode.appendChild(sub);
    sub.parentNode.insertBefore(ex, sub);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', skin); else skin();
})();
