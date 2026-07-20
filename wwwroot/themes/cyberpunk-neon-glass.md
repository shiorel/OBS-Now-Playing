# Cyberpunk / Neon Glass

Kesik köşeli (notched) bir "HUD cam paneli": dört köşede ince ışıklı parantezler,
panel üzerinde çok düşük opasiteli bir ölçüm ızgarası ve yüzeyi yavaşça tarayan
tek bir çizgi. Etiketler ve süre bilgisi monospace bir yazı tipiyle, başlık ve
sanatçı ise kalın geniş bir sans-serif ile yazılır — okunabilirlik her zaman
dekorasyonun önünde tutulur.

## Bu temayı özel kılan şey

- **Köşe parantezleri** — widget'ın dört köşesinde `::after` katmanıyla çizilen,
  vurgu rengine göre parlayan ince HUD çizgileri.
- **Kesik köşeli panel** — `clip-path` ile klasik border-radius yerine tek bir
  köşesi kesik cam panel; kapak ve mini avatar da aynı dilde kesik köşelerle
  eşleşir.
- **Tarayıcı çizgisi** — panel yüzeyinde 7 saniyede bir geçen, çok düşük
  opasiteli bir ışık taraması (`.shine`), `screen` blend modu ile arka planı
  yakmadan derinlik katar.
- **Track değişiminde glitch** — yeni şarkı geldiğinde başlık kısa bir RGB
  kayması ve köşe parantezlerinde bir flaş ile karşılanır (`glitchIn`,
  `bracketFlash`), 0.5 saniyeden kısa ve `prefers-reduced-motion` ile kapanır.

## Renk sistemi

Tüm neon çizgiler, köşe parantezleri, servis rozeti çerçevesi ve ilerleme
çubuğu `--accent` / `--accent-light` / `--accent-glow` değişkenlerinden
beslenir; bu değişkenler `app.js` tarafından kapak sanatından canlı olarak
hesaplanıp `#widget` üzerine satır içi stil olarak yazılır. Sabit renk yalnızca
metin gölgesindeki hafif siyah kontrast katmanında kullanılır, kimliği
etkilemez.

## Test edilenler

- 400×100 (OBS hedefi), 800×200, 1200×300 — 4:1 oranı korunuyor.
- Uzun başlıklarda marquee kayması çalışıyor, `...` kullanılmıyor.
- Kapak/sanatçı görseli bulunamadığında fallback görünümleri doğru tetikleniyor.
- Duraklat/oynat, `is-live` (canlı yayın) durumu, boşta (`is-idle`) ekranı ve
  `hideWhenIdle` davranışı orijinal `app.js` ile birebir çalışıyor.
- Spotify dışı kaynaklarda (`generic` servis rozeti) görünüm bozulmuyor.

## Notlar

- `app.js` orijinal dosyayla birebir aynıdır, hiçbir bağlantı değişmedi.
- Tüm element `id` değerleri korunmuştur.
- 400×100 altında (`@media (max-height: 120px)`) servis rozeti, kalp ikonu ve
  kontroller gizlenir; bu, orijinal Dynamic Neon temasındaki alan önceliği
  mantığıyla aynıdır.
