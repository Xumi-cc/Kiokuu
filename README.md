<p align="center">
  <img src="assets/images/logo_black_bg_white.png" width="120" alt="Kiokuu Logo"/>
</p>

<h1 align="center">Kiokuu</h1>

<p align="center">
  <strong>Your Personal Cloud Music Streaming Platform</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#installation">Installation</a> •
  <a href="#tech-stack">Tech Stack</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.38+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.10+-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android"/>
  <img src="https://img.shields.io/badge/iOS-000000?style=flat-square&logo=ios&logoColor=white" alt="iOS"/>
  <img src="https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black" alt="Linux"/>
  <img src="https://img.shields.io/badge/Windows-0078D6?style=flat-square&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS"/>
  <img src="https://img.shields.io/badge/Web-4285F4?style=flat-square&logo=googlechrome&logoColor=white" alt="Web"/>
</p>

---

## Features

### Music Streaming
- **Cloud Library** — Upload your music collection and stream from anywhere
- **High-Quality Playback** — Powered by MediaKit/MPV for lossless audio support
- **Offline Mode** — Download songs for offline listening with automatic HD upgrades
- **Background Playback** — Full audio service integration with notification controls

### AI-Powered
- **Smart Matching** — AI identifies your uploaded songs and fetches metadata automatically
- **Lyrics Sync** — Synchronized lyrics display with beautiful full-screen visualizations

### Cross-Platform
- **Native Experience** — Runs on Android, iOS, Linux, Windows, macOS, and Web
- **Seamless Sync** — Playback state syncs across all your devices in real-time
- **Responsive Design** — Adapts beautifully from mobile to desktop

### Social
- **Friend Activity** — See what your friends are listening to
- **Shared Playlists** — Collaborate on playlists with friends
- **Listen Together** — Sync playback with friends in real-time

### Premium Features
- **Unlimited Uploads** — No storage limits for premium users
- **Priority Streaming** — Dedicated CDN for faster streams
- **Early Access** — Get new features before everyone else

---

## Design Philosophy

Kiokuu features a stunning **monochromatic design** with:

- Elegant dark theme with glassmorphic elements
- Smooth micro-animations and transitions
- Dynamic backgrounds that adapt to album artwork
- Fluid, gesture-driven navigation

---

## Installation

### Prerequisites

- **Flutter SDK** 3.38.5 or higher
- **Dart SDK** 3.10.1 or higher

### Setup

```bash
# Clone the repository
git clone https://github.com/Xumi-cc/Kiokuu.git
cd Kiokuu

# Install dependencies
flutter pub get

# Run the app
flutter run -d <device>
```

**Available devices:**

| Device | Command |
|--------|---------|
| Android | `flutter run -d android` |
| iOS | `flutter run -d ios` |
| Linux | `flutter run -d linux` |
| Windows | `flutter run -d windows` |
| macOS | `flutter run -d macos` |
| Web | `flutter run -d chrome` |

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3.38+ |
| Language | Dart 3.10+ |
| State Management | Provider |
| Audio Engine | MediaKit (MPV) |
| Background Audio | audio_service + MPRIS |
| Networking | HTTP + WebSocket |
| Local Storage | flutter_secure_storage |
| Authentication | Google Sign-In, Discord OAuth |

---

## Project Structure

```
kiokuu/
├── lib/
│   ├── screens/           # UI screens
│   ├── providers/         # State management
│   ├── services/          # API & audio services
│   ├── models/            # Data models
│   └── widgets/           # Reusable components
│
├── assets/                # Static assets
├── android/               # Android-specific code
├── ios/                   # iOS-specific code
├── linux/                 # Linux-specific code
├── windows/               # Windows-specific code
├── macos/                 # macOS-specific code
└── web/                   # Web-specific code
```

---

## Building for Release

### Android
```bash
flutter build apk --release --split-per-abi
# or for Play Store
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

### Linux
```bash
flutter build linux --release
```

### Windows
```bash
flutter build windows --release
```

### macOS
```bash
flutter build macos --release
```

### Web
```bash
flutter build web --release
```

---

## Authentication

Kiokuu supports multiple authentication methods:

- **Email/Password** — Traditional authentication
- **Google Sign-In** — OAuth 2.0 integration
- **Discord** — OAuth 2.0 with deep linking support

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## Contact

- **Website**: [kiokuu.com](https://kiokuu.app)
- **Email**: support@kiokuu.com
- **Discord**: [Join our community](https://discord.gg/geHykXBUcz)

---

<p align="center">
  Made with care by <a href="https://github.com/Xumi-cc">Xumi Labs</a>
</p>
