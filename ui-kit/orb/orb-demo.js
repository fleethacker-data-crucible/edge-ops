/* Controls for orb-demo.html. Nothing here is needed to use the orb. */
(function () {
  'use strict';
  var voice = FleetOrb.voice;
  var CAPTIONS = {
    listening: 'Go ahead.',
    thinking: 'Checking 212 files against the index.',
    speaking: 'Turnover is ready. Two items are open for the next watch.',
    approval: 'Move 14 screenshots to Archive? Approve or deny.'
  };
  var main = FleetOrb.mount({ id: 'assistant', name: 'Assistant' });
  var $ = function (id) { return document.getElementById(id); };
  var simulated = true, reduced = false;

  function setToggle(btn, label, on) {
    btn.setAttribute('aria-pressed', String(on));
    btn.textContent = label + ': ' + (on ? 'on' : 'off');
  }
  function showState(id) {
    Array.prototype.forEach.call($('states').children, function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-state') === id)); });
  }

  FleetOrb.states.forEach(function (s) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'ghost'; b.textContent = s.label; b.setAttribute('data-state', s.id);
    b.addEventListener('click', function () { voice.set(s.id, undefined, CAPTIONS[s.id] || ''); });
    $('states').appendChild(b);
  });
  voice.subscribe(function (v) { showState(v.state); });
  showState(voice.state);

  voice.simulate(true);
  $('simulate').addEventListener('click', function () {
    simulated = !simulated;
    voice.simulate(simulated);
    setToggle(this, 'Simulated voice', simulated);
    $('level').value = 0;
  });
  $('level').addEventListener('input', function () {
    if (simulated) { simulated = false; voice.simulate(false); setToggle($('simulate'), 'Simulated voice', false); }
    voice.setLevel(this.value / 100 * 0.5);
  });

  /* Real audio through the same path TalkForge playback will use: a synthetic, speech-shaped WAV in an <audio>
     element, read by voice.fromAudio. */
  function testWav() {
    var rate = 22050, n = rate * 4, view = new DataView(new ArrayBuffer(44 + n * 2));
    function text(at, s) { for (var i = 0; i < s.length; i++) view.setUint8(at + i, s.charCodeAt(i)); }
    text(0, 'RIFF'); view.setUint32(4, 36 + n * 2, true); text(8, 'WAVEfmt ');
    view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
    view.setUint32(24, rate, true); view.setUint32(28, rate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
    text(36, 'data'); view.setUint32(40, n * 2, true);
    for (var i = 0; i < n; i++) {
      var t = i / rate, syllable = Math.max(0, Math.sin(t * 2 * Math.PI * 3.1)) * (Math.sin(t * 2 * Math.PI * 0.45) > -0.6 ? 1 : 0);
      var wave = Math.sin(t * 2 * Math.PI * 140) * 0.6 + Math.sin(t * 2 * Math.PI * 420) * 0.25;
      view.setInt16(44 + i * 2, wave * syllable * 0.5 * 32767, true);
    }
    return new Blob([view.buffer], { type: 'audio/wav' });
  }
  var audio = null;
  $('tone').addEventListener('click', function () {
    if (!audio) {
      audio = new Audio(URL.createObjectURL(testWav()));
      voice.fromAudio(audio);
      audio.addEventListener('ended', function () { if (simulated) voice.simulate(true); });
    }
    voice.simulate(false);
    audio.currentTime = 0;
    audio.play();
  });

  var tiles = [];
  /* Every look in every theme, live. Clicking a tile applies it to the orb. */
  FleetOrb.looks.forEach(function (look) {
    var head = document.createElement('h3'); head.textContent = look.label;
    var row = document.createElement('div'); row.className = 'demo-tiles';
    $('gallery').appendChild(head); $('gallery').appendChild(row);
    FleetOrb.themes.forEach(function (theme) {
      var tile = document.createElement('div'); tile.className = 'demo-tile';
      row.appendChild(tile);
      tiles.push(FleetOrb.mount({
        id: 'tile-' + look.id + '-' + theme.id, name: 'Use this:', look: look.id, theme: theme.id, size: 150, inline: true, parent: tile,
        persist: false, picker: false, caption: false, quality: 'medium',
        onActivate: function () { main.setLook(look.id); main.setTheme(theme.id); }
      }));
      var name = document.createElement('span'); name.className = 'muted'; name.textContent = theme.label;
      tile.appendChild(name);
    });
  });

  $('reduce').addEventListener('click', function () {
    reduced = !reduced;
    document.documentElement.setAttribute('data-reduced-motion', String(reduced));
    setToggle(this, 'Reduced motion', reduced);
  });
  $('home').addEventListener('click', function () { main.resetPosition(); });

  var clicks = 0;
  $('clicker').addEventListener('click', function () { clicks++; this.textContent = 'Clicked ' + clicks + (clicks === 1 ? ' time' : ' times'); });

  setInterval(function () {
    var s = main.stats();
    $('readout').textContent = voice.state + ' | level ' + voice.level.toFixed(2) + ' | ' + s.look + ' | ' + main.theme + ' | ' + s.fps + ' fps | draw ' + s.avgDrawMs + ' ms | quality step ' + s.tier;
  }, 500);
  window.orbDemo = { main: main, tiles: tiles };
}());
