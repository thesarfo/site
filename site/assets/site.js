// Small behaviours the site needs a script for: theme, a random quote, copy link,
// the shelf filter, the lightbox, and the lens gallery. Everything else is plain HTML.
(function () {
  'use strict';

  /* ---------- theme ---------- */
  var root = document.documentElement;
  function stored() {
    try { var s = localStorage.getItem('theme'); return s === 'dark' || s === 'light' ? s : 'system'; }
    catch (e) { return 'system'; }
  }
  function apply(mode) {
    var dark = mode === 'dark' || (mode === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
    root.classList.toggle('dark', dark);
    root.classList.toggle('light', !dark);
    document.querySelectorAll('[data-theme]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.getAttribute('data-theme') === mode));
    });
  }
  apply(stored());
  document.querySelectorAll('[data-theme]').forEach(function (b) {
    b.addEventListener('click', function () {
      var mode = b.getAttribute('data-theme');
      try {
        if (mode === 'system') localStorage.removeItem('theme');
        else localStorage.setItem('theme', mode);
      } catch (e) {}
      apply(mode);
    });
  });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function () {
    if (stored() === 'system') apply('system');
  });

  /* ---------- random quote on the home page ---------- */
  var quote = document.getElementById('quote');
  if (quote) {
    try {
      var quotes = JSON.parse(quote.getAttribute('data-quotes'));
      var q = quotes[Math.floor(Math.random() * quotes.length)];
      quote.querySelector('.text').textContent = '"' + q.text + '"';
      quote.querySelector('.by').textContent = '- ' + q.author;
    } catch (e) {}
  }

  /* ---------- copy link ---------- */
  document.querySelectorAll('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () {
      navigator.clipboard.writeText(b.getAttribute('data-copy')).then(function () {
        var was = b.textContent;
        b.textContent = 'copied';
        setTimeout(function () { b.textContent = was; }, 2000);
      });
    });
  });

  /* ---------- 404: show the path that was asked for ---------- */
  var lost = document.getElementById('lost-path');
  if (lost) lost.textContent = location.pathname;

  /* ---------- shelf search and filter ---------- */
  var search = document.getElementById('shelf-search');
  if (search) {
    var kindBox = document.getElementById('shelf-kinds');
    var shelvesEl = document.getElementById('shelves');
    var countEl = document.getElementById('shelf-count');
    var emptyEl = document.getElementById('shelf-empty');
    var kind = 'all';
    var run = function () {
      var q = search.value.trim().toLowerCase();
      var filtering = q.length > 0 || kind !== 'all';
      var shown = 0;
      shelvesEl.classList.toggle('filtering', filtering);
      shelvesEl.querySelectorAll('.shelf').forEach(function (shelf) {
        var n = 0;
        shelf.querySelectorAll('.shelf-item').forEach(function (item) {
          var ok = (kind === 'all' || item.getAttribute('data-kind') === kind) &&
            (!q || item.getAttribute('data-text').indexOf(q) !== -1);
          item.hidden = !ok;
          if (ok) n++;
        });
        shelf.hidden = n === 0;
        shelf.querySelector('.count').textContent = n + ' items';
        shown += n;
      });
      countEl.hidden = !filtering;
      countEl.textContent = shown + (shown === 1 ? ' match' : ' matches');
      emptyEl.hidden = shown !== 0;
    };
    search.addEventListener('input', run);
    kindBox.addEventListener('click', function (e) {
      var b = e.target.closest('button[data-kind]');
      if (!b) return;
      kind = b.getAttribute('data-kind');
      kindBox.querySelectorAll('button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
      run();
    });
  }

  /* ---------- lightbox: any <a data-lightbox="group" href="full image"> ---------- */
  var lb = null, group = [], at = 0;
  function show() {
    var a = group[at];
    lb.querySelector('img').src = a.href;
    lb.querySelector('img').alt = a.getAttribute('data-caption') || '';
    lb.querySelector('.lb-cap').textContent = a.getAttribute('data-caption') || '';
    var many = group.length > 1;
    lb.querySelector('.lb-prev').hidden = !many;
    lb.querySelector('.lb-next').hidden = !many;
  }
  function step(d) { at = (at + d + group.length) % group.length; show(); }
  function close() {
    if (!lb) return;
    document.removeEventListener('keydown', onKey);
    lb.remove(); lb = null;
    document.body.style.overflow = '';
  }
  function onKey(e) {
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft' && group.length > 1) step(-1);
    else if (e.key === 'ArrowRight' && group.length > 1) step(1);
  }
  function open(anchor) {
    var name = anchor.getAttribute('data-lightbox');
    group = Array.prototype.slice.call(document.querySelectorAll('a[data-lightbox="' + name + '"]'));
    at = group.indexOf(anchor);
    lb = document.createElement('div');
    lb.className = 'lb';
    lb.setAttribute('role', 'dialog');
    lb.setAttribute('aria-modal', 'true');
    lb.innerHTML =
      '<button type="button" class="lb-close" aria-label="Close">&times;</button>' +
      '<button type="button" class="lb-prev" aria-label="Previous">&#8249;</button>' +
      '<img alt="">' +
      '<button type="button" class="lb-next" aria-label="Next">&#8250;</button>' +
      '<p class="lb-cap"></p>';
    lb.addEventListener('click', function (e) {
      if (e.target.closest('.lb-prev')) step(-1);
      else if (e.target.closest('.lb-next')) step(1);
      else if (e.target.tagName !== 'IMG') close();
    });
    document.body.appendChild(lb);
    document.body.style.overflow = 'hidden';
    document.addEventListener('keydown', onKey);
    show();
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest('a[data-lightbox]');
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey) return;
    e.preventDefault();
    open(a);
  });

  /* ---------- lens: photos come from the image host's manifest ---------- */
  var lens = document.getElementById('lens');
  if (lens) {
    var BASE = 'https://images.thesarfo.com';
    var url = function (p) { return BASE + '/' + encodeURI(p); };
    fetch(BASE + '/manifest.json')
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (m) {
        lens.innerHTML = '';
        var images = m.images || [];
        if (!images.length) throw new Error('empty');
        images.forEach(function (im, i) {
          var a = document.createElement('a');
          a.href = url(im.file);
          a.setAttribute('data-lightbox', 'lens');
          a.setAttribute('data-caption', im.date || '');
          a.setAttribute('aria-label', 'View photo');
          var img = document.createElement('img');
          img.src = url(im.thumb);
          img.srcset = url(im.thumb) + ' 640w, ' + url(im.file) + ' ' + im.width + 'w';
          img.sizes = '(max-width: 704px) 100vw, 672px';
          img.alt = '';
          img.width = im.width; img.height = im.height;
          img.loading = i < 2 ? 'eager' : 'lazy';
          a.appendChild(img);
          lens.appendChild(a);
        });
      })
      .catch(function () {
        lens.innerHTML = '<p class="coming">Coming soon 🙂</p>';
      });
  }
})();
