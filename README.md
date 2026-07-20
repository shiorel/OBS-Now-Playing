# OBS Now Playing

[Türkçe dokümantasyon](README_TR.md)

A portable, installer-free Windows now-playing widget for OBS Studio. It reads Windows media sessions and displays the active track in a compact 400×100 Dynamic Neon browser source.

## Project story and open-source use

This project was created entirely with artificial intelligence tools, primarily OpenAI ChatGPT and Codex, under the direction of [shiorel](https://github.com/shiorel). It was built to solve the owner's personal need for a practical, readable, and portable now-playing widget for OBS Studio. The owner defined the requirements, guided the development, tested the application, and published the final result.

OBS Now Playing is open source under the MIT License. You may use, copy, modify, improve, redistribute, or include it in personal and commercial projects. You are welcome to fork the repository and develop it in any direction. When using or redistributing the project, please retain the license and copyright notice and credit **shiorel** as the original project creator.

## What makes it different from other now-playing widgets?

Many now-playing widgets are tied to a single streaming service, require OAuth setup, API credentials, a user account, or a hosted web service. OBS Now Playing instead reads Windows media sessions locally, allowing one widget to work with Spotify, Apple Music, YouTube Music, Deezer, and compatible browser players without requiring a music-service login or API key.

- **One widget for multiple players:** It prioritizes dedicated music applications and falls back to compatible browser media when necessary.
- **Portable and installer-free:** Extract the ZIP and run the application; no command prompt, web hosting, or installer is required.
- **Local and privacy-conscious:** The widget server listens only on `127.0.0.1`; track metadata is not sent to an analytics or account service.
- **Designed specifically for OBS readability:** The 400×100 layout keeps track and artist names prominent, while long titles scroll instead of being truncated with an ellipsis.
- **Artwork recovery:** Missing artwork can be found through Deezer, with iTunes Search API as a fallback, while downloaded images are cached locally.
- **Adaptive Dynamic Neon appearance:** Accent colors are derived from the current album artwork to create a matching neon outline without sacrificing readability.
- **Built-in desktop control panel:** OBS setup instructions, a copyable Browser Source URL, player priority, idle hiding, artwork options, and bilingual TR/ENG controls are available in one UX.
- **Live behavior:** Settings and language changes reach the open OBS Browser Source without requiring a complete application restart.

## Screenshots

### Dynamic Neon widget

![Dynamic Neon OBS widget showing Linkin Park Faint on Spotify](docs/images/widget-spotify-faint.png)

Live Spotify playback shown with **Linkin Park — Faint**.

### In OBS Studio

The widget can be positioned and scaled as a transparent Browser Source over any OBS scene.

![OBS Now Playing used in OBS Studio](docs/images/obs-studio-preview.png)

### Control panel

![OBS Now Playing control panel](docs/images/control-panel.png)

### Settings

![OBS Now Playing settings](docs/images/settings.png)

## Features

- Spotify, Apple Music, YouTube Music, Deezer, and browser-media support
- Prioritized Windows media-session selection
- Deezer artwork lookup with iTunes Search API fallback
- Dynamic neon accent colors derived from album artwork
- Four built-in themes selectable from the control panel
- Readable artist and track names with marquee animation for long titles
- Live progress, service badge, and optional playback controls
- Turkish and English control panel and widget UI
- Copyable OBS Browser Source URL
- Idle hiding, player priority, artwork, and appearance settings
- Portable Windows application with system-tray support

## Download

Download the latest ready-to-run Windows ZIP from the repository's **Releases** page. Extract the archive and run `OBSNowPlaying.exe`; no installer or account is required.

## OBS setup

1. Start `OBSNowPlaying.exe`.
2. In OBS Studio, add a **Browser** source.
3. Use `http://127.0.0.1:8974/` as its URL.
4. Set width to `400`, height to `100`, and FPS to `30` or `60`.
5. Keep **Shutdown source when not visible** disabled.

The control panel displays the current URL and lets you copy it. If you change the port, update the Browser Source URL in OBS.

## Themes

Choose a theme from **Settings → Widget theme**, then select **Save and Restart**. Open OBS Browser Sources receive the selected theme automatically.

- Dynamic Neon
- Minimal Clean Dark
- Retro Synthwave
- Cyberpunk Neon Glass

The imported alternative-theme CSS files are kept separately under `wwwroot/themes/`; the shared HTML, JavaScript, API, language, idle hiding, and long-title marquee behavior remain unchanged.

## Supported sources

The application prioritizes Spotify, Apple Music, YouTube Music desktop clients, and Deezer. If none is active, compatible browser media sessions from Edge, Chrome, or Firefox can be displayed.

## Privacy and security

- The HTTP server listens only on `127.0.0.1`.
- Track metadata stays on the local machine.
- Public Deezer and iTunes endpoints are used only to find missing artwork.
- No API key, analytics service, account, or telemetry is used.

The executable is currently unsigned. Windows SmartScreen or antivirus software may therefore show a warning. Review the source and build it locally if preferred.

## AI-assisted development

This project was developed with assistance from OpenAI ChatGPT and Codex. AI tools were used for code generation, debugging, UI development, documentation, testing, and architectural improvements. The repository owner reviewed, tested, packaged, and published the project.

This project is not affiliated with or endorsed by OpenAI, Spotify, Apple, YouTube, Deezer, Microsoft, or OBS Studio.

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) before contributing. For security concerns, see [SECURITY.md](SECURITY.md).

## License

Released under the [MIT License](LICENSE).
