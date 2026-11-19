/*
 * Reproductor de vídeos de formación ONEMS: un solo vídeo con voz en inglés y subtítulos por idioma.
 *
 * Uso en cualquier página:
 *   <div data-onems-video="panelist-registration"></div>
 *   <script src="/videos/player.js" defer></script>
 *
 * Idioma de los subtítulos: atributo data-lang del contenedor; si no, el <html lang> de la página;
 * si no, el idioma del navegador. En inglés los subtítulos salen apagados (la voz ya es inglés),
 * pero se pueden activar. El usuario siempre puede cambiarlos con los botones bajo el vídeo
 * o con el menú CC del propio reproductor.
 *
 * Para añadir un vídeo: súbelo al bucket training-videos, añádelo a VIDEOS y deja sus
 * subtítulos en /videos/subs/<id>.<idioma>.vtt (ver scripts/videos/README.md).
 */
(function () {
  'use strict';

  var STORAGE = 'https://sehbnpgzqljrsqimwyuz.supabase.co/storage/v1/object/public/training-videos/';

  // id -> fichero MP4 (voz en inglés) e idiomas con subtítulos disponibles.
  var VIDEOS = {
    'panelist-registration': { file: 'ONE_Panelist_Registration_EN.mp4', subs: ['en', 'es', 'fr', 'ar', 'pt'] },
    'roles-access': { file: 'ONEMS_Roles_and_access_EN.mp4', subs: ['en', 'es', 'fr', 'ar', 'pt'] }
  };

  var LANG_NAMES = { en: 'English', es: 'Español', fr: 'Français', ar: 'العربية', pt: 'Português' };
  var UI = {
    en: { subs: 'Subtitles', off: 'Off', missing: 'Video not found' },
    es: { subs: 'Subtítulos', off: 'No', missing: 'Vídeo no encontrado' },
    fr: { subs: 'Sous-titres', off: 'Non', missing: 'Vidéo introuvable' },
    ar: { subs: 'الترجمة', off: 'إيقاف', missing: 'الفيديو غير موجود' },
    pt: { subs: 'Legendas', off: 'Não', missing: 'Vídeo não encontrado' }
  };

  // Carpeta de subtítulos relativa a este script, para que funcione desde /help/ y desde /videos/.
  var self = document.currentScript && document.currentScript.src;
  var SUBS_BASE = self ? new URL('subs/', self).href : '/videos/subs/';

  function shortLang(l) {
    return String(l || '').toLowerCase().split(/[-_]/)[0];
  }

  function pickLang(el) {
    var cands = [el.getAttribute('data-lang'), document.documentElement.lang, navigator.language];
    for (var i = 0; i < cands.length; i++) {
      var l = shortLang(cands[i]);
      if (UI[l]) return l;
    }
    return 'en';
  }

  function injectStyles() {
    if (document.getElementById('onems-video-css')) return;
    var css = document.createElement('style');
    css.id = 'onems-video-css';
    css.textContent =
      '.onems-video{margin:16px 0;max-width:100%}' +
      '.onems-video video{display:block;width:100%;max-width:100%;border-radius:12px;background:#000;aspect-ratio:16/9}' +
      '.onems-video .ov-bar{display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin-top:8px;font-size:13px}' +
      '.onems-video .ov-bar span{color:#64748b;margin-inline-end:4px}' +
      '.onems-video button{font:inherit;font-size:13px;padding:4px 10px;border-radius:999px;border:1px solid #cbd5e1;' +
      'background:#fff;color:#334155;cursor:pointer}' +
      '.onems-video button[aria-pressed="true"]{background:#1d4ed8;border-color:#1d4ed8;color:#fff}' +
      '.onems-video video::cue{font-size:1.05em;background:rgba(0,0,0,.75)}';
    document.head.appendChild(css);
  }

  function mount(el) {
    var id = el.getAttribute('data-onems-video');
    var v = VIDEOS[id];
    var lang = pickLang(el);
    var ui = UI[lang];
    el.classList.add('onems-video');
    if (!v) {
      el.textContent = ui.missing + ': ' + id;
      return;
    }

    var video = document.createElement('video');
    video.controls = true;
    video.preload = 'metadata';
    video.playsInline = true;
    video.crossOrigin = 'anonymous';
    video.src = STORAGE + v.file;

    v.subs.forEach(function (l) {
      var tr = document.createElement('track');
      tr.kind = 'subtitles';
      tr.srclang = l;
      tr.label = LANG_NAMES[l] || l;
      tr.src = SUBS_BASE + id + '.' + l + '.vtt';
      if (l === lang && l !== 'en') tr.default = true;
      video.appendChild(tr);
    });

    var bar = document.createElement('div');
    bar.className = 'ov-bar';
    var label = document.createElement('span');
    label.textContent = ui.subs + ':';
    bar.appendChild(label);

    var buttons = [];
    // Solo mandan nuestras pistas .vtt. Si el MP4 trae subtítulos incrustados (Safari los muestra),
    // se apagan siempre para que no salgan duplicados.
    var ours = Array.prototype.map.call(video.querySelectorAll('track'), function (te) { return te.track; });
    var current = '';
    function select(l) {
      current = l;
      for (var i = 0; i < video.textTracks.length; i++) {
        var t = video.textTracks[i];
        t.mode = ours.indexOf(t) >= 0 && t.language === l ? 'showing' : 'disabled';
      }
      buttons.forEach(function (b) {
        b.setAttribute('aria-pressed', String(b.getAttribute('data-l') === l));
      });
    }
    function addButton(l, text) {
      var b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('data-l', l);
      b.textContent = text;
      b.addEventListener('click', function () { select(l); });
      buttons.push(b);
      bar.appendChild(b);
    }
    addButton('', ui.off);
    v.subs.forEach(function (l) { addButton(l, LANG_NAMES[l] || l); });

    el.textContent = '';
    el.appendChild(video);
    el.appendChild(bar);

    var initial = v.subs.indexOf(lang) >= 0 && lang !== 'en' ? lang : '';
    // Las pistas aparecen en textTracks al insertarse; se fija el estado inicial y se mantiene
    // sincronizado si el usuario cambia desde el menú CC del navegador.
    select(initial);
    video.textTracks.addEventListener('addtrack', function () { select(current); });
    video.textTracks.addEventListener('change', function () {
      var on = '';
      for (var i = 0; i < video.textTracks.length; i++) {
        if (video.textTracks[i].mode === 'showing') on = video.textTracks[i].language;
      }
      buttons.forEach(function (b) {
        b.setAttribute('aria-pressed', String(b.getAttribute('data-l') === on));
      });
    });
  }

  function init() {
    injectStyles();
    var els = document.querySelectorAll('[data-onems-video]');
    for (var i = 0; i < els.length; i++) mount(els[i]);
  }

  window.OnemsVideo = { mount: mount, videos: VIDEOS };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
