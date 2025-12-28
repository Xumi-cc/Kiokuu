# Music Cloud 🎵

A beautiful, cross-platform music player built with Flutter featuring a sleek black & white design.

## ✨ Features

- **Cross-Platform**: Runs on Android, iOS, Linux, macOS, Windows, and Web
- **Beautiful UI**: Modern black & white theme with glassmorphic effects and smooth animations
- **Audio Playback**: Powered by `just_audio` for high-quality audio playback
- **Playlist Management**: Add, remove, and organize your music
- **Playback Controls**: Play, pause, skip, shuffle, and repeat
- **Progress Tracking**: Visual progress bar with seek functionality
- **Swipe to Delete**: Swipe songs to remove them from the playlist
- **Responsive Design**: Adapts to different screen sizes

## 🎨 Design

The app features a premium black & white aesthetic with:

- Gradient backgrounds and buttons
- Glassmorphic containers with subtle transparency
- Smooth micro-animations
- Animated album art with pulse effects
- Clean, modern typography using Inter font

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (3.10.1 or higher)
- Dart SDK

### Installation

1. Clone the repository
2. Install dependencies:

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
flutter pub get
```

3. Run the app:

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
flutter run -d <device>
```

Available devices:

- `linux` - Linux desktop
- `android` - Android device/emulator
- `ios` - iOS device/simulator
- `macos` - macOS desktop
- `windows` - Windows desktop
- `chrome` - Web browser

## 📱 Usage

1. **Add Music**: Tap the "Add Music" button to select audio files from your device
2. **Play Songs**: Tap any song in the playlist to start playing
3. **Control Playback**: Use the player controls to play/pause, skip, shuffle, or repeat
4. **Seek**: Drag the progress slider to jump to any position in the song
5. **Remove Songs**: Swipe left on any song to remove it from the playlist

## 🛠️ Tech Stack

- **Framework**: Flutter
- **State Management**: Provider
- **Audio Playback**: just_audio
- **Background Audio**: audio_service
- **File Picking**: file_picker
- **Typography**: Google Fonts (Inter)

## 📦 Dependencies

```yaml
dependencies:
  just_audio: ^0.9.36
  audio_service: ^0.18.12
  file_picker: ^8.0.0+1
  path_provider: ^2.1.2
  permission_handler: ^11.3.0
  provider: ^6.1.1
  google_fonts: ^6.2.1
```

## 🎯 Features in Detail

### Player Controls

- **Play/Pause**: Large gradient button with shadow effects
- **Skip**: Navigate to previous/next songs
- **Shuffle**: Randomize playback order
- **Repeat One**: Loop the current song

### Playlist View

- **Visual Indicators**: Current song highlighted with white border
- **Animated Icons**: Equalizer animation for playing songs
- **Song Options**: Long-press or tap menu for additional options
- **Empty State**: Helpful message when playlist is empty

### Now Playing Card

- **Album Art**: Large, rounded artwork display with gradient fallback
- **Pulse Animation**: Animated effect when music is playing
- **Song Info**: Title, artist, and album information
- **Responsive**: Adapts to different screen sizes

## 🔧 Development

### Hot Reload

While the app is running, press `r` in the terminal for hot reload or `R` for hot restart.

### Building for Production

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Linux
flutter build linux --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Web
flutter build web --release
```

## 📝 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

---

Made with ❤️ using Flutter
