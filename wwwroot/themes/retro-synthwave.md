# Retro / Synthwave

80'ler ufkunu andıran bir panel: kapak sanatının arkasından yükselen degrade
bir "güneş" parıltısı, alt kısımda yavaşça kayan bir ufuk ızgarası ve italik,
geniş boşluklu bir "chrome" başlık efekti. Demo kapağındaki (`demo-cover.svg`)
synthwave estetiğiyle doğal biçimde eşleşir.

## Bu temayı özel kılan şey

- **Ufuk ızgarası** — panelin alt %46'sında, sürekli sağa doğru kayan ince
  çizgilerden oluşan bir perspektif ızgara (`::after`, `gridDrift`), metnin
  arkasında maskeyle soluklaştırılarak okunabilirliği bozmuyor.
- **Chrome başlık** — şarkı adı, üstten alta beyazdan vurgu rengine geçen bir
  gradyanla doldurulur (`background-clip: text`) ve altına hafif bir parlama
  eklenir; yüksek kontrast korunduğu için okunabilirlik etkilenmiyor.
- **İtalik/eğik tipografi** — başlık, sanatçı adı, servis rozeti ve boşta
  ekranı hafif italik açıyla yazılır, retro kaset/poster hissi verir.

## Renk sistemi

Güneş parıltısı, ızgara, ilerleme çubuğu, kalp ikonu ve chrome başlık
gradyanının üst durağı doğrudan `--accent` / `--accent-light` değişkenlerinden
beslenir; bu değişkenler kapak sanatından `app.js` tarafından canlı hesaplanır.
Sabit mor/magenta tonu (`--grid-violet`, `--grid-magenta`) yalnızca gradyanın
ikincil durağı ve arka plan gökyüzü rengi olarak kullanılır — kimliği domine
etmez, vurgu rengi her zaman baskındır.

## Test edilenler

- 400×100 (OBS hedefi), 800×200, 1200×300 — 4:1 oranı korunuyor.
- Uzun başlıklarda marquee kayması çalışıyor, `...` kullanılmıyor.
- Kapak/sanatçı görseli bulunamadığında fallback görünümleri doğru tetikleniyor.
- Duraklat/oynat, `is-live`, boşta (`is-idle`) ekranı ve `hideWhenIdle`
  davranışı orijinal `app.js` ile birebir çalışıyor.
- Spotify dışı kaynaklarda (`generic` servis rozeti) görünüm bozulmuyor.

## Notlar

- `app.js` orijinal dosyayla birebir aynıdır, hiçbir bağlantı değişmedi.
- Tüm element `id` değerleri korunmuştur.
- 400×100 altında (`@media (max-height: 120px)`) mini sanatçı avatarı, albüm
  adı, kalp ikonu ve kontroller gizlenir; başlık ve sanatçı adı her zaman en
  belirgin metin olarak kalır.
