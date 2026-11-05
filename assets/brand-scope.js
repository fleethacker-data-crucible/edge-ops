/* SCOPE shell for the Edge-Ops hub. Classic script, no build, works from file://. Load it in <head> after theme.js.
   The shell is the default for GitHub Pages and for the offline client (same index.html). ?brand=edgeops switches it
   off and remembers that; ?brand=scope turns it back on. With nothing in the URL and nothing remembered, SCOPE renders.
   The default dark theme is Fleet Night watch, set in assets/theme.js. This file does not overwrite a theme the
   visitor already chose, so the theme switcher sticks. Same catalog, same tools, same data.
   The skin loads assets/brand-scope.css (the Fleet UI v0.2 look the Fleet apps share) and arranges the page into the
   Fleet shell: a sidebar with the emblem, wordmark and group navigation, a header with the page title and filters,
   the catalog, and a status bar. */
(function () {
  'use strict';
  // The expansion wording is not settled. Change it here only: one word per letter; the page shows the initials in bold.
  var SCOPE_EXPANSION = 'Ship Continuity Operations Platform Environment';
  var SCOPE_NAME = 'SCOPE';
  var SCOPE_THEME = 'fleet-night-watch';
  var SCOPE_EMBLEM = 'assets/emblems/scope.svg';
  var PLAIN_ICON = 'ui-kit/assets/favicon-32.png';
  // The painted SCOPE emblem goes here when it lands (dark and light variants); until then the line mark above is used.
  var SCOPE_EMBLEM_PAINTED = 'assets/brand/scope/emblem-dark.png', SCOPE_EMBLEM_PAINTED_LIGHT = 'assets/brand/scope/emblem-light.png';
  var PAINTED_DIR = 'assets/emblems/painted/';
  var SCOPE_CSS = 'assets/brand-scope.css';
  var SCOPE_PAGE_TITLE = 'Periscope';
  var SCOPE_SUBTITLE = 'FleetHacker Edge-Ops utility suite';
  var KEY = 'edge-ops-brand', PREV_THEME_KEY = 'edge-ops-brand-prev-theme';

  function get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function set(k, v) { try { if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) {} }
  var m = /[?&]brand=([^&#]*)/.exec(location.search), q = m ? decodeURIComponent(m[1]) : '';
  var theme = window.EdgeTheme;

  function plainHub() {
    // The display name stays Periscope. This only removes the SCOPE shell.
    document.documentElement.removeAttribute('data-brand');
    document.title = SCOPE_PAGE_TITLE;
    var icon = document.querySelector('link[rel="icon"]');
    if (icon) icon.href = PLAIN_ICON;
  }

  // ?brand=edgeops is the plain hub. A remembered edgeops choice sticks until ?brand=scope.
  if (q === 'edgeops') {
    set(KEY, 'edgeops');
    var prev = get(PREV_THEME_KEY); set(PREV_THEME_KEY, null);
    if (theme && prev !== null && theme.preference === SCOPE_THEME) theme.set(prev);
    plainHub();
    return;
  }
  if (q === 'scope') set(KEY, 'scope');
  if (q !== 'scope' && get(KEY) === 'edgeops') { plainHub(); return; }

  document.documentElement.setAttribute('data-brand', 'scope');
  document.title = SCOPE_PAGE_TITLE;
  var iconOn = document.querySelector('link[rel="icon"]');
  if (iconOn) iconOn.href = SCOPE_EMBLEM;
  if (!document.querySelector('link[rel="stylesheet"][href="' + SCOPE_CSS + '"]')) {
    var css = document.createElement('link'); css.rel = 'stylesheet'; css.href = SCOPE_CSS; document.head.appendChild(css);
  }

  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }

  function light() { var t = document.documentElement.getAttribute('data-theme') || ''; return document.documentElement.classList.contains('light') || /light|chart/.test(t); }
  // Try each source in turn; the first that loads stays. Works from file://, where nothing can be probed ahead of time.
  function paintedOrFallback(img, sources, onFound) {
    var i = 0;
    function next() { if (i >= sources.length) return; img.src = sources[i++]; }
    img.onerror = next;
    img.onload = function () { img.onerror = null; if (onFound) onFound(img); };
    next();
  }

  var brandImg = null, brandBlock = null;
  function paintBrand() {
    if (!brandImg || !brandBlock) return;
    var sources = light() ? [SCOPE_EMBLEM_PAINTED_LIGHT, SCOPE_EMBLEM_PAINTED, SCOPE_EMBLEM] : [SCOPE_EMBLEM_PAINTED, SCOPE_EMBLEM];
    var key = sources.join('|');
    function mark(img) { if (img.src.indexOf(SCOPE_EMBLEM) === -1) brandBlock.classList.add('has-painted'); else brandBlock.classList.remove('has-painted'); }
    if (brandImg.getAttribute('data-sources') === key && brandImg.getAttribute('src')) { if (brandImg.complete) mark(brandImg); return; }
    brandBlock.classList.remove('has-painted');
    brandImg.setAttribute('data-sources', key);
    paintedOrFallback(brandImg, sources, mark);
  }

  // Cards: the painted emblem and the tagline. app.js redraws the grid on every filter change, so decorate() runs again
  // for new cards. restylePainted() swaps light and dark emblems when the theme picker changes.
  function paintCard(c, t) {
    if (t.tagline) { var p = c.querySelector('h3 + p'); if (p) p.textContent = t.tagline; }
    var im = c.querySelector('img.painted');
    if (!im) {
      im = el('img', 'painted'); im.alt = ''; im.setAttribute('aria-hidden', 'true'); im.width = 96; im.height = 96;
      c.insertBefore(im, c.firstChild);
    }
    var sources = light() ? [PAINTED_DIR + t.id + '-light.png', PAINTED_DIR + t.id + '.png'] : [PAINTED_DIR + t.id + '.png'];
    var key = sources.join('|');
    function mark() { c.classList.add('has-painted'); }
    if (im.getAttribute('data-sources') === key && im.getAttribute('src')) { if (im.complete && im.naturalWidth) mark(); return; }
    c.classList.remove('has-painted');
    im.setAttribute('data-sources', key);
    paintedOrFallback(im, sources, mark);
  }
  function toolsById(data) { var byId = {}; (data.tools || []).forEach(function (t) { byId[t.id] = t; }); return byId; }
  function decorate(data) {
    var byId = toolsById(data);
    var cards = document.querySelectorAll('#grid .card:not([data-scope])');
    for (var k = 0; k < cards.length; k++) {
      var c = cards[k];
      var a = c.querySelector('h3 a'); if (!a) continue;
      var mm = /tools\/([^/]+)\.html$/.exec(a.getAttribute('href') || ''); var t = mm ? byId[mm[1]] : null; if (!t) continue;
      c.setAttribute('data-scope', ''); c.setAttribute('data-tool', t.id);
      paintCard(c, t);
    }
  }
  function restylePainted() {
    paintBrand();
    var byId = toolsById(window.EDGE_OPS_CATALOG || { tools: [] });
    var cards = document.querySelectorAll('#grid .card[data-tool]');
    for (var k = 0; k < cards.length; k++) { var t = byId[cards[k].getAttribute('data-tool')]; if (t) paintCard(cards[k], t); }
  }

  function brand() {
    var b = el('div', 'scope-brand'); brandBlock = b;
    var im = el('img', 'emblem'); im.alt = ''; im.setAttribute('aria-hidden', 'true'); im.width = 112; im.height = 112;
    brandImg = im;
    // With the painted emblem (which carries its own wordmark) the brand block shows it alone, as PacketRat's sidebar does.
    b.appendChild(im);
    paintBrand();
    b.appendChild(el('p', 'scope-wordmark', SCOPE_NAME));
    // Fleet wordmark rule: brass rules either side of a compass star.
    var rule = el('div', 'scope-rule'); rule.setAttribute('aria-hidden', 'true');
    rule.appendChild(el('span'));
    rule.insertAdjacentHTML('beforeend', '<svg width="10" height="10" viewBox="0 0 10 10"><path d="M5 0 6.2 3.8 10 5 6.2 6.2 5 10 3.8 6.2 0 5 3.8 3.8Z"/></svg>');
    rule.appendChild(el('span'));
    b.appendChild(rule);
    var ex = el('p', 'scope-expansion');
    var words = SCOPE_EXPANSION.split(' ');
    for (var i = 0; i < words.length; i++) {
      ex.appendChild(el('b', null, words[i].charAt(0)));
      ex.appendChild(document.createTextNode(words[i].slice(1) + (i < words.length - 1 ? ' ' : '')));
    }
    b.appendChild(ex);
    return b;
  }

  // Group navigation drives the hub's own Group filter (the <select id="grp"> that app.js listens to).
  // Groups stay in catalog order: the four primary rows first, then voice, secrets and support.
  function nav(data, grp) {
    var n = el('nav', 'scope-nav'); n.setAttribute('aria-label', 'Groups');
    n.appendChild(el('div', 'scope-nav-title', 'Groups'));
    var tools = data.tools || [], groups = (data.groups || []).filter(function (g) { return tools.some(function (t) { return t.group === g.id; }); });
    var items = [{ id: '', name: 'All tools', n: tools.length }].concat(groups.map(function (g) {
      return { id: g.id, name: g.name, n: tools.filter(function (t) { return t.group === g.id; }).length };
    }));
    var buttons = [];
    function mark() { buttons.forEach(function (b) { if (b.getAttribute('data-group') === grp.value) b.setAttribute('aria-current', 'page'); else b.removeAttribute('aria-current'); }); }
    items.forEach(function (it) {
      var b = el('button', null); b.type = 'button'; b.setAttribute('data-group', it.id);
      b.appendChild(el('span', null, it.name)); b.appendChild(el('span', 'n', String(it.n)));
      b.addEventListener('click', function () {
        grp.value = it.id;
        var ev = document.createEvent('Event'); ev.initEvent('change', true, true); grp.dispatchEvent(ev);
        var c = document.querySelector('.scope-content'); if (c) c.scrollTop = 0;
      });
      n.appendChild(b); buttons.push(b);
    });
    grp.addEventListener('change', mark); mark();
    return n;
  }

  function status(data) {
    var s = el('footer', 'scope-status'); s.setAttribute('aria-label', 'Status');
    var state = el('span', null); state.setAttribute('role', 'status'); state.appendChild(el('span', 'dot')); state.appendChild(document.createTextNode('Catalog loaded'));
    s.appendChild(state);
    s.appendChild(el('span', 'addr', location.protocol === 'file:' ? 'local file' : location.host));
    var tools = data.tools || [], groups = (data.groups || []).filter(function (g) { return tools.some(function (t) { return t.group === g.id; }); });
    s.appendChild(el('span', null, tools.length + ' tools in ' + groups.length + ' groups'));
    if (data.updated) s.appendChild(el('span', null, 'catalog ' + data.updated));
    s.appendChild(el('span', 'spacer'));
    s.appendChild(el('span', null, 'Edge-Ops hub'));
    return s;
  }

  function shell() {
    var data = window.EDGE_OPS_CATALOG || { groups: [], tools: [] };
    var body = document.body, header = document.querySelector('body > header'), grid = document.getElementById('grid');
    var foot = document.querySelector('body > footer'), grp = document.getElementById('grp');
    if (!header || !grid || !grp) return;

    var side = el('aside', 'scope-side'); side.setAttribute('aria-label', SCOPE_NAME);
    side.appendChild(brand());
    side.appendChild(nav(data, grp));
    side.appendChild(el('div', 'scope-side-foot', SCOPE_SUBTITLE));

    // Header: page title on the left, the filters, the theme picker on the right. The old subtitle moves to the sidebar foot.
    var h1 = header.querySelector('h1'); if (h1) h1.textContent = SCOPE_PAGE_TITLE;
    var sub = header.querySelector('p'); if (sub) sub.parentNode.removeChild(sub);
    var prefs = header.querySelector('.prefs'); if (prefs) header.appendChild(prefs);

    var main = el('div', 'scope-main');
    var content = el('div', 'scope-content');
    main.appendChild(header);
    content.appendChild(grid);
    if (foot) { foot.className = 'scope-content-footer'; content.appendChild(foot); }
    main.appendChild(content);

    body.appendChild(side); body.appendChild(main); body.appendChild(status(data));
    body.classList.add('scope-ready');
    decorate(data);
    if (window.MutationObserver) {
      new MutationObserver(function () { decorate(window.EDGE_OPS_CATALOG || data); }).observe(grid, { childList: true, subtree: true });
      new MutationObserver(function () { restylePainted(); }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'class'] });
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', shell); else shell();
})();
