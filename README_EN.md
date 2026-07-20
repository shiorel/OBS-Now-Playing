# OBS Now Playing Widget

A portable, installation-free Windows application that displays the currently playing track in OBS. Its Dynamic Neon design extracts a suitable accent color locally from the album artwork.

## Project story and open-source use

This project was created entirely with artificial intelligence tools, primarily OpenAI ChatGPT and Codex, under the direction of [shiorel](https://github.com/shiorel). It was built to solve the owner's personal need for a practical, readable, and portable now-playing widget for OBS Studio. The owner defined the requirements, guided the development, tested the application, and published the final result.

OBS Now Playing is open source under the MIT License. You may use, copy, modify, improve, redistribute, or include it in personal and commercial projects. You are welcome to fork the repository and develop it in any direction. When using or redistributing the project, please retain the license and copyright notice and credit **shiorel** as the original project creator.

## Screenshots

### Dynamic Neon widget

![Dynamic Neon OBS widget](docs/images/widget-neon.png)

### In OBS Studio

The widget can be positioned and scaled as a transparent Browser Source over any OBS scene.

![OBS Now Playing used in OBS Studio](docs/images/obs-studio-preview.png)

### Control panel

![OBS Now Playing control panel](docs/images/control-panel.png)

### Settings

![OBS Now Playing settings](docs/images/settings.png)

## Starting the application

The control panel starts in Turkish when the Windows display language is Turkish, and in English for every other language. Use the `TR` and `ENG` buttons in the upper-right corner to switch languages without restarting the application.

The selected control-panel language is also applied to the widget live. `ŞİMDİ ÇALIYOR / NOW PLAYING`, idle, and unknown-track labels follow the UX language.

Appearance and player settings are available in the modern control panel. When `Hide widget when idle` is enabled, the widget becomes completely hidden after the configured delay. Setting changes are picked up live even while the OBS Browser Source remains open.

1. Extract the ZIP package into a folder.
2. Double-click `OBSNowPlaying.exe`.
3. The application starts in the Windows system tray.
4. Start music in Spotify or another player that supports Windows media controls.

No command prompt, BAT file, installer, or user account is required.

## OBS setup

In OBS Studio:

1. Click `+` in the Sources panel.
2. Select `Browser`.
3. Enter `http://127.0.0.1:8974/` as the URL.
4. Set width to `400` and height to `100`.
5. Select `30` or `60` FPS.
6. Keep `Shutdown source when not visible` disabled.
7. Keep `Refresh browser when scene becomes active` disabled.

The widget opens directly with the Neon theme. No theme parameter is required.

## System tray controls

Double-click the application icon to open the widget in a browser. The right-click menu provides:

- `Widget'i Ac` — open the widget
- `Demo Onizleme` — open the demo preview
- `OBS Adresini Kopyala` — copy the OBS URL
- `Yeniden Baslat` — restart the local server
- `Kapat` — close the application

## Features

- Dynamic Neon appearance
- Event-driven media updates for lower CPU usage
- Automatic album-art accent color
- Highly readable track and artist names
- Automatic scrolling for long track titles
- Live progress bar and time display
- Previous, play/pause, and next controls
- Album cover and artist image caching
- Spotify and generic Windows media source support
- Player priority: Spotify → Apple Music → YouTube Music/Desktop App → Deezer → browsers
- Transparent OBS background
- Compact `400 × 100` broadcast layout

## Preview

Open the demo from the system tray menu or use:

`http://127.0.0.1:8974/?demo=1`

## Configuration

Main options in `config.json`:

- `port`: Local server port. Default: `8974`.
- `pollIntervalMs`: Base interval for lightweight timeline updates; track and playback changes arrive through Windows events. The effective value is limited to `500–1000 ms` for performance.
- `preferredPlayers`: Player priority when several players are active.
- `onlyPreferredPlayers`: Restrict detection to listed players.
- `openPreviewOnStart`: Open a browser preview at startup.
- `autoFetchArtistImages`: Automatically complete missing artist images.
- `autoFetchCoverImages`: Automatically complete missing cover artwork.

## Troubleshooting

- Check `log.txt` if the widget does not start.
- If the port is occupied, update both `config.json` and the OBS Browser Source URL.
- If track information is missing, restart the player and verify that it appears in the Windows media panel.
- If OBS shows an older design, use `Refresh cache of current page` in the Browser Source properties.
- Use `Kapat` from the system tray menu to close the application.

## Requirements

- Windows 10 version 1809 or newer, or Windows 11
- OBS Studio
- A music player supporting Windows media sessions
- Internet access for automatic artwork completion

## License

MIT License.
