(() => {
  'use strict';

  const $ = (id) => document.getElementById(id);
  const widget = $('widget');
  const themeStyles = $('themeStyles');
  const cover = $('cover');
  const artistAvatar = $('miniCover');
  const artistAvatarText = $('artistAvatarText');
  const title = $('title');
  const titleViewport = $('titleViewport');
  const artist = $('artist');
  const album = $('album');
  const serviceBadge = $('serviceBadge');
  const serviceName = $('serviceName');
  const progressFill = $('progressFill');
  const progressKnob = $('progressKnob');
  const elapsed = $('elapsed');
  const duration = $('duration');
  const controls = $('controls');
  const nowLabel = $('nowLabel');
  const idleTitle = $('idleTitle');
  const idleSubtitle = $('idleSubtitle');
  const previous = $('previous');
  const toggle = $('toggle');
  const next = $('next');
  const coverWrap = document.querySelector('.cover-wrap');
  const avatarWrap = document.querySelector('.mini-disc');
  const coverColorCache = new Map();

  function rgbToHsl(r, g, b) {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    let h = 0;
    let s = 0;
    const l = (max + min) / 2;
    if (max !== min) {
      const delta = max - min;
      s = l > .5 ? delta / (2 - max - min) : delta / (max + min);
      if (max === r) h = (g - b) / delta + (g < b ? 6 : 0);
      else if (max === g) h = (b - r) / delta + 2;
      else h = (r - g) / delta + 4;
      h /= 6;
    }
    return { h, s, l };
  }

  function hslToRgb(h, s, l) {
    if (!s) {
      const gray = Math.round(l * 255);
      return { r: gray, g: gray, b: gray };
    }
    const q = l < .5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    const hue = (value) => {
      if (value < 0) value += 1;
      if (value > 1) value -= 1;
      if (value < 1 / 6) return p + (q - p) * 6 * value;
      if (value < 1 / 2) return q;
      if (value < 2 / 3) return p + (q - p) * (2 / 3 - value) * 6;
      return p;
    };
    return { r: Math.round(hue(h + 1 / 3) * 255), g: Math.round(hue(h) * 255), b: Math.round(hue(h - 1 / 3) * 255) };
  }

  function normalizeAccentColor(color) {
    const hsl = rgbToHsl(color.r, color.g, color.b);
    const saturation = Math.min(.95, Math.max(.7, hsl.s));
    const lightness = Math.min(.62, Math.max(.48, hsl.l));
    return {
      base: hslToRgb(hsl.h, saturation, lightness),
      light: hslToRgb(hsl.h, Math.min(.96, saturation + .04), Math.min(.76, lightness + .17)),
      dark: hslToRgb(hsl.h, saturation, Math.max(.25, lightness - .22))
    };
  }

  function extractDominantColor(image) {
    const canvas = document.createElement('canvas');
    canvas.width = 36;
    canvas.height = 36;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    if (!context) throw new Error('Canvas kullanilamiyor');
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
    const buckets = new Map();
    for (let i = 0; i < pixels.length; i += 16) {
      const r = pixels[i];
      const g = pixels[i + 1];
      const b = pixels[i + 2];
      const alpha = pixels[i + 3];
      if (alpha < 180) continue;
      const hsl = rgbToHsl(r, g, b);
      if (hsl.l < .09 || hsl.l > .91 || hsl.s < .18) continue;
      const qr = Math.round(r / 32) * 32;
      const qg = Math.round(g / 32) * 32;
      const qb = Math.round(b / 32) * 32;
      const key = `${qr},${qg},${qb}`;
      const value = buckets.get(key) || { r: 0, g: 0, b: 0, count: 0, score: 0 };
      value.r += r; value.g += g; value.b += b; value.count += 1;
      value.score += .45 + hsl.s * 1.4 + (1 - Math.abs(hsl.l - .52)) * .7;
      buckets.set(key, value);
    }
    let best = null;
    buckets.forEach((bucket) => { if (!best || bucket.score > best.score) best = bucket; });
    if (!best || !best.count) throw new Error('Uygun renk bulunamadi');
    return normalizeAccentColor({ r: best.r / best.count, g: best.g / best.count, b: best.b / best.count });
  }

  function applyAccentColor(color) {
    const rgb = `${color.base.r}, ${color.base.g}, ${color.base.b}`;
    const light = `rgb(${color.light.r}, ${color.light.g}, ${color.light.b})`;
    const dark = `rgb(${color.dark.r}, ${color.dark.g}, ${color.dark.b})`;
    widget.style.setProperty('--accent-rgb', rgb);
    widget.style.setProperty('--accent', `rgb(${rgb})`);
    widget.style.setProperty('--accent-light', light);
    widget.style.setProperty('--accent-dark', dark);
    widget.style.setProperty('--accent-soft', `rgba(${rgb}, .22)`);
    widget.style.setProperty('--accent-transparent', `rgba(${rgb}, .1)`);
    widget.style.setProperty('--accent-glow', `rgba(${rgb}, .46)`);
    widget.style.setProperty('--panel-tint', `rgba(${rgb}, .08)`);
  }

  function analyzeCurrentCover() {
    if (!coverResolved || !cover.complete || !cover.naturalWidth) return;
    const cacheKey = `${lastTrackKey}|${state ? Number(state.coverVersion) || 0 : 0}|${cover.currentSrc || cover.src}`;
    if (coverColorCache.has(cacheKey)) {
      applyAccentColor(coverColorCache.get(cacheKey));
      return;
    }
    try {
      const color = extractDominantColor(cover);
      coverColorCache.set(cacheKey, color);
      while (coverColorCache.size > 24) coverColorCache.delete(coverColorCache.keys().next().value);
      applyAccentColor(color);
    } catch { /* Kapak yine gorunur; mevcut vurgu rengi korunur. */ }
  }

  function updateTitleMarquee() {
    titleViewport.classList.remove('is-overflowing');
    titleViewport.style.removeProperty('--marquee-distance');
    titleViewport.style.removeProperty('--marquee-duration');
    requestAnimationFrame(() => {
      const overflow = Math.ceil(title.scrollWidth - titleViewport.clientWidth);
      if (overflow <= 1) return;
      titleViewport.style.setProperty('--marquee-distance', `${-(overflow + 4)}px`);
      titleViewport.style.setProperty('--marquee-duration', `${Math.max(6, overflow / 24 + 4).toFixed(1)}s`);
      titleViewport.classList.add('is-overflowing');
    });
  }

  const params = new URLSearchParams(location.search);
  const demo = params.get('demo') === '1';
  const requestedTheme = params.get('theme');
  cover.addEventListener('load', analyzeCurrentCover);

  let config = {
    hideWhenIdle: false,
    idleHideDelaySeconds: 8,
    showAlbum: true,
    showControls: true,
    showServiceBadge: true,
    language: 'tr',
    theme: 'neon'
  };

  const themes = {
    neon: { file: 'styles.css', className: 'theme-neon', title: 'Dynamic Neon' },
    'minimal-clean-dark': { file: 'themes/minimal-clean-dark.css', className: 'theme-minimal', title: 'Minimal Clean Dark' },
    'retro-synthwave': { file: 'themes/retro-synthwave.css', className: 'theme-retro', title: 'Retro Synthwave' },
    'cyberpunk-neon-glass': { file: 'themes/cyberpunk-neon-glass.css', className: 'theme-cyberpunk', title: 'Cyberpunk Neon Glass' }
  };

  function applyTheme() {
    const configuredTheme = requestedTheme || config.theme;
    const key = Object.prototype.hasOwnProperty.call(themes, configuredTheme) ? configuredTheme : 'neon';
    const selected = themes[key];
    widget.classList.remove('theme-neon', 'theme-minimal', 'theme-retro', 'theme-cyberpunk');
    widget.classList.add(selected.className);
    if (themeStyles.getAttribute('href') !== selected.file) themeStyles.setAttribute('href', selected.file);
    document.title = `OBS Now Playing — ${selected.title}`;
    requestAnimationFrame(updateTitleMarquee);
  }

  function isTurkish() {
    return String(config.language || 'tr').toLowerCase() === 'tr';
  }

  function applyLanguage() {
    const tr = isTurkish();
    document.documentElement.lang = tr ? 'tr' : 'en';
    nowLabel.textContent = tr ? 'ŞİMDİ ÇALIYOR' : 'NOW PLAYING';
    idleTitle.textContent = tr ? 'Müzik bekleniyor' : 'Waiting for music';
    idleSubtitle.textContent = tr ? 'Spotify veya başka bir oynatıcıdan şarkı başlat' : 'Start a song in Spotify or another player';
  }

  let state = null;
  let receivedAt = performance.now();
  let lastTrackKey = '';
  let idleSince = 0;
  let observedCoverVersion = -1;

  let currentArtistName = '';
  let artistImageResolved = false;
  let artistRequestToken = 0;
  let artistRetryTimer = 0;
  let artistAttempt = 0;

  let coverResolved = false;
  let coverRequestToken = 0;
  let coverRetryTimer = 0;
  let coverAttempt = 0;

  const demoState = {
    connected: true,
    hasMedia: true,
    title: 'MIDNIGHT DREAMS',
    artist: 'THE SYNTH WAVES',
    album: 'NEON LIGHTS',
    source: 'Spotify',
    sourceId: 'Spotify.exe',
    status: 'Playing',
    isPlaying: true,
    positionMs: 105000,
    durationMs: 232000,
    playbackRate: 1,
    coverVersion: 1,
    updatedAt: Date.now(),
    controls: { previous: true, toggle: true, next: true }
  };

  function formatTime(ms, live = false) {
    if (live) return 'CANLI';
    const total = Math.max(0, Math.floor(ms / 1000));
    const minutes = Math.floor(total / 60);
    const seconds = String(total % 60).padStart(2, '0');
    return `${minutes}:${seconds}`;
  }

  function getCurrentPosition() {
    if (!state) return 0;
    let value = Number(state.positionMs) || 0;
    if (state.isPlaying && state.durationMs > 0) {
      value += (performance.now() - receivedAt) * (Number(state.playbackRate) || 1);
    }
    return Math.max(0, state.durationMs > 0 ? Math.min(value, state.durationMs) : value);
  }

  function escapeCssUrl(url) {
    return String(url || '').replaceAll('"', '%22');
  }

  function getInitials(text) {
    const source = String(text || '').trim();
    if (!source) return '♪';
    return source
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part[0])
      .join('')
      .toUpperCase();
  }

  function setArtistFallback(label) {
    avatarWrap.classList.add('no-artist-image');
    artistAvatar.removeAttribute('src');
    artistAvatar.alt = label ? `${label} görseli hazırlanıyor` : 'Sanatçı görseli';
    artistAvatarText.textContent = getInitials(label);
  }

  function setArtistAvatar(url, label) {
    avatarWrap.classList.remove('no-artist-image');
    artistAvatar.src = url;
    artistAvatar.alt = label ? `${label} görseli` : 'Sanatçı görseli';
    artistAvatarText.textContent = '';
    artistImageResolved = true;
  }

  function setCover(url, hasCover = true) {
    coverWrap.classList.toggle('no-cover', !hasCover);
    cover.src = url;
    widget.style.setProperty('--cover-image', `url("${escapeCssUrl(url)}")`);
    coverResolved = hasCover;
    if (hasCover) requestAnimationFrame(analyzeCurrentCover);
  }

  function clearCover() {
    setCover('demo-cover.svg', false);
  }

  function animateTrackChange() {
    widget.classList.remove('track-change');
    void widget.offsetWidth;
    widget.classList.add('track-change');
    setTimeout(() => widget.classList.remove('track-change'), 750);
  }

  function stopArtistRetry() {
    if (artistRetryTimer) {
      clearTimeout(artistRetryTimer);
      artistRetryTimer = 0;
    }
  }

  function scheduleArtistRetry(name, token) {
    if (token !== artistRequestToken || artistImageResolved) return;
    artistAttempt += 1;
    const delay = artistAttempt <= 45 ? 120 : artistAttempt <= 80 ? 300 : 800;
    artistRetryTimer = window.setTimeout(() => tryArtistImage(name, token), delay);
  }

  function tryArtistImage(name, token) {
    if (token !== artistRequestToken || artistImageResolved || !name) return;

    const url = `/artist-image?name=${encodeURIComponent(name)}&v=${token}&t=${Date.now()}`;
    const probe = new Image();
    probe.onload = () => {
      if (token !== artistRequestToken) return;
      stopArtistRetry();
      setArtistAvatar(url, name);
    };
    probe.onerror = () => {
      if (token !== artistRequestToken) return;
      scheduleArtistRetry(name, token);
    };
    probe.src = url;
  }

  function beginArtistLoad(name) {
    stopArtistRetry();
    artistRequestToken += 1;
    artistAttempt = 0;
    artistImageResolved = false;
    currentArtistName = String(name || '').trim();

    if (!currentArtistName) {
      setArtistFallback('');
      return;
    }
    if (demo) {
      setArtistAvatar('demo-cover.svg', currentArtistName);
      return;
    }

    setArtistFallback(currentArtistName);
    tryArtistImage(currentArtistName, artistRequestToken);
  }

  function stopCoverRetry() {
    if (coverRetryTimer) {
      clearTimeout(coverRetryTimer);
      coverRetryTimer = 0;
    }
  }

  function scheduleCoverRetry(token) {
    if (token !== coverRequestToken || coverResolved) return;
    coverAttempt += 1;
    // Ilk saniyelerde cok hizli, sonra daha sakin kontrol et.
    const delay = coverAttempt <= 16 ? 120 : coverAttempt <= 40 ? 250 : coverAttempt <= 80 ? 600 : 1500;
    coverRetryTimer = window.setTimeout(() => tryCover(token), delay);
  }

  function tryCover(token) {
    if (token !== coverRequestToken || coverResolved) return;

    const version = state ? Number(state.coverVersion) || 0 : 0;
    const url = `/cover?v=${encodeURIComponent(version)}&track=${token}&t=${Date.now()}`;
    const probe = new Image();
    probe.onload = () => {
      if (token !== coverRequestToken) return;
      stopCoverRetry();
      setCover(url, true);
    };
    probe.onerror = () => {
      if (token !== coverRequestToken) return;
      scheduleCoverRetry(token);
    };
    probe.src = url;
  }

  function beginCoverLoad() {
    stopCoverRetry();
    coverRequestToken += 1;
    coverAttempt = 0;
    coverResolved = false;
    clearCover();

    if (demo) {
      setCover('demo-cover.svg', true);
      return;
    }

    tryCover(coverRequestToken);
  }

  function applyState(nextState) {
    const wasIdle = widget.classList.contains('is-idle');
    state = nextState;
    receivedAt = performance.now();

    const hasMedia = Boolean(state && state.hasMedia && state.title);
    widget.classList.toggle('is-idle', !hasMedia);
    widget.classList.toggle('is-paused', hasMedia && !state.isPlaying);
    widget.classList.toggle('is-live', hasMedia && !(Number(state.durationMs) > 0));

    if (!hasMedia) {
      if (!idleSince) idleSince = Date.now();
      const shouldHide = config.hideWhenIdle && Date.now() - idleSince >= config.idleHideDelaySeconds * 1000;
      widget.classList.toggle('is-hidden', shouldHide);
      widget.setAttribute('aria-hidden', shouldHide ? 'true' : 'false');
      return;
    }

    idleSince = 0;
    widget.classList.remove('is-hidden');
    widget.setAttribute('aria-hidden', 'false');

    const key = `${state.sourceId}|${state.title}|${state.artist}|${state.album}`;
    const trackChanged = key !== lastTrackKey;
    if (trackChanged) {
      lastTrackKey = key;
      observedCoverVersion = Number(state.coverVersion) || 0;
      beginArtistLoad(state.artist || '');
      beginCoverLoad();
      animateTrackChange();
    }

    title.textContent = state.title || (isTurkish() ? 'BİLİNMEYEN ŞARKI' : 'UNKNOWN TRACK');
    if (trackChanged) updateTitleMarquee();
    artist.textContent = state.artist || (isTurkish() ? 'BİLİNMEYEN SANATÇI' : 'UNKNOWN ARTIST');
    album.textContent = state.album || '';
    album.style.display = config.showAlbum && state.album ? '' : 'none';

    const source = state.source || 'Müzik';
    serviceName.textContent = source;
    serviceBadge.classList.toggle('generic', source.toLowerCase() !== 'spotify');
    serviceBadge.style.display = config.showServiceBadge ? '' : 'none';
    controls.style.display = config.showControls ? '' : 'none';

    previous.disabled = !(state.controls && state.controls.previous);
    toggle.disabled = !(state.controls && state.controls.toggle);
    next.disabled = !(state.controls && state.controls.next);

    const newCoverVersion = Number(state.coverVersion) || 0;
    if (!trackChanged && !coverResolved && newCoverVersion !== observedCoverVersion) {
      observedCoverVersion = newCoverVersion;
      stopCoverRetry();
      tryCover(coverRequestToken);
    }

    if (wasIdle) animateTrackChange();
  }

  async function fetchJson(url) {
    const response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) throw new Error(`${response.status}`);
    return response.json();
  }

  async function refresh() {
    if (demo) {
      const elapsedDemo = (Date.now() - demoState.updatedAt) % demoState.durationMs;
      applyState({ ...demoState, positionMs: elapsedDemo });
      return;
    }

    try {
      applyState(await fetchJson('/api/state'));
    } catch {
      applyState({ hasMedia: false, connected: false, title: '', error: 'Sunucu bağlantısı yok' });
    }
  }

  async function refreshConfig() {
    try {
      config = { ...config, ...(await fetchJson('/api/config')) };
      applyLanguage();
      applyTheme();
      if (state) applyState(state);
    } catch { /* Son geçerli ayarlarla devam et. */ }
  }

  async function control(action) {
    if (demo) {
      if (action === 'toggle') demoState.isPlaying = !demoState.isPlaying;
      return;
    }

    try {
      await fetch(`/api/control/${action}`, { method: 'POST', cache: 'no-store' });
      setTimeout(refresh, 80);
    } catch { /* OBS görünümünü bozma */ }
  }

  previous.addEventListener('click', () => control('previous'));
  toggle.addEventListener('click', () => control('toggle'));
  next.addEventListener('click', () => control('next'));
  window.addEventListener('resize', updateTitleMarquee);

  function renderTimeline() {
    if (state && state.hasMedia) {
      const pos = getCurrentPosition();
      const dur = Number(state.durationMs) || 0;
      if (dur > 0) {
        const percent = Math.max(0, Math.min(100, (pos / dur) * 100));
        progressFill.style.width = `${percent}%`;
        progressKnob.style.left = `${percent}%`;
        elapsed.textContent = formatTime(pos);
        duration.textContent = formatTime(dur);
      } else {
        elapsed.textContent = 'CANLI';
        duration.textContent = '';
      }
    }
    requestAnimationFrame(renderTimeline);
  }

  async function start() {
    try { config = { ...config, ...(await fetchJson('/api/config')) }; } catch { /* defaults */ }
    applyLanguage();
    applyTheme();
    clearCover();
    setArtistFallback('');
    await refresh();
    widget.classList.remove('is-loading');
    setInterval(refresh, demo ? 1000 : 150);
    setInterval(refreshConfig, 2000);
    requestAnimationFrame(renderTimeline);
  }

  start();
})();
