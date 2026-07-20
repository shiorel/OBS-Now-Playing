# Minimal / Clean Dark

Yayında en az dikkat dağıtan, en hızlı okunan tema. Düz koyu bir yüzey, ince
saç çizgisi (hairline) kenarlık, blur veya glow yok. Vurgu rengi yalnızca tek
bir yerde — panelin sol kenarındaki ince şeritte, ilerleme çizgisinde ve
"şimdi çalıyor" noktasında — kullanılır; geri kalan her şey nötr gri/beyaz
tonlarda kalır.

## Bu temayı özel kılan şey

- **Nefes alan kenar şeridi** — widget'ın sol kenarında dikey ince bir vurgu
  çizgisi, 3.2 saniyelik yumuşak bir opasite döngüsüyle "canlı" hissi verir.
  Bu, orijinal `live-dot` yanıp sönmesinin yerini alan tek dekoratif hareket.
- **Düz yüzey** — gölge, iç parlama veya bulanık kapak arka planı yok; bunun
  yerine kapak renginden çok hafif bir radial vinyet (`--panel-tint`)
  kullanılır. Amaç: panel her zaman sakin ve okunur kalsın.
- **Tipografi ağırlıklı hiyerarşi** — başlık/sanatçı/albüm ayrımı renk veya
  büyük harfle değil, yalnızca font ağırlığı ve boyutuyla yapılır (700 / 500 /
  400).

## Renk sistemi

`--accent` yalnızca kenar şeridinde, ilerleme çubuğunda, canlı noktasında ve
kalp ikonunun rengi hariç her yerde son derece kısıtlı biçimde kullanılır.
Kapaktan gelen renk `app.js` tarafından hesaplanıp `#widget` üzerine satır içi
stil olarak uygulanır; sabit renk hiçbir yerde kullanılmaz.

## Test edilenler

- 400×100 (OBS hedefi), 800×200, 1200×300 — 4:1 oranı korunuyor.
- Uzun başlıklarda marquee kayması çalışıyor, `...` kullanılmıyor.
- Kapak/sanatçı görseli bulunamadığında fallback görünümleri (gri ikon /
  baş harfi) doğru tetikleniyor.
- Duraklat/oynat, `is-live`, boşta (`is-idle`) ekranı ve `hideWhenIdle`
  davranışı orijinal `app.js` ile birebir çalışıyor.
- Spotify dışı kaynaklarda (`generic` servis rozeti) görünüm bozulmuyor.

## Notlar

- `app.js` orijinal dosyayla birebir aynıdır, hiçbir bağlantı değişmedi.
- Tüm element `id` değerleri korunmuştur.
- 400×100 altında (`@media (max-height: 120px)`) mini sanatçı avatarı, albüm
  adı, kalp ikonu ve kontroller gizlenir; başlık ve sanatçı adı her zaman en
  belirgin metin olarak kalır.
