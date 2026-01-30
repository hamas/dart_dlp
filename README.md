# dart_dlp 🚀

> **The World's First Pure-Dart, Zero-FFmpeg Media Engine for 8K Performance & 1,000+ Site Scalability.**

[![Pure Dart](https://img.shields.io/badge/Pure-Dart-blue?logo=dart)](https://dart.dev)
[![Kotlin](https://img.shields.io/badge/Kotlin-Native-purple?logo=kotlin)](https://kotlinlang.org)
[![Swift](https://img.shields.io/badge/Swift-Native-orange?logo=swift)](https://developer.apple.com/swift)
[![Zero FFmpeg](https://img.shields.io/badge/Zero-FFmpeg-green)](https://github.com/hamas/dart_dlp)
[![License](https://img.shields.io/badge/License-MIT-purple)](LICENSE)

---

## 📖 Introduction

**dart_dlp** is a revolutionary media extraction engine designed to liberate Dart and Flutter developers from the constraints of heavy external binaries. Unlike traditional solutions that wrap `yt-dlp` (Python) or require massive `ffmpeg` bundles, `dart_dlp` is built from the ground up to be **Lightweight and Invincible**.

It combines a **Pure Dart** extraction core with a **Native (Kotlin/Swift)** muxing bridge, delivering 8K video streams without a single byte of compiled FFmpeg or Python code.

It is engineered for **Hyper-Scale** and **Stealth**, capable of navigating complex anti-bot protections and executing rolling cipher decryption.

---

### Why dart_dlp?

1.  **Zero External Binaries**: No Python, no node.js.
2.  **Native Muxing**: Uses Android's `MediaMuxer` and iOS's `AVAssetExportSession` to merge 4K video+audio instantly (Zero-Encoding).
3.  **HamasDownloader™**: A proprietary, multi-threaded chunked downloader that saturates your bandwidth by opening parallel connections.
4.  **Stealth Mode**: Rotates between 50+ real-world User-Agents and injects human-like HTTP headers (`Sec-Fetch-*`) to evade IP blocking.
5.  **Architecture**: Decoupled design allows for pure Dart usage (extraction only) or full Flutter Plugin power (muxing enabled).

---

## ⚙️ Advanced Features

### ⚡ HD Download & Native Muxing (The "Super" Pattern)
YouTube (and others) often serve 1080p+ video as separate Video and Audio tracks.
`dart_dlp` handles this automatically using its Native Bridge.

**Zero-FFmpeg Requirement:**
We utilize the device's native APIs (`MediaMuxer` on Android, `AVAssetExportSession` on iOS) to merge streams instantly without re-encoding. This keeps the app size tiny only adding ~20KB to your bundle, compared to FFmpeg's ~50MB.

**How it works:**
1.  **Detects** if a video is split (e.g., 4K stream).
2.  **Downloads** video and audio tracks concurrently.
3.  **Invokes** the Native Bridge to merge them in seconds.
4.  **Cleans up** temporary files.

```dart
final controller = DlpController();

// 1. Get Video Data
final videoData = await engine.extract('https://tiktok.com/...');

// 2. Start Download (Auto-Muxing handled internally)
controller.state.listen((state) {
  if (state.status == DlpStatus.downloading) {
    print('Downloading... ${state.progress?.percentage.toStringAsFixed(1)}%');
  } else if (state.status == DlpStatus.completed) {
    print('Done! File at: ${state.message}');
  }
});

await controller.startDownload(videoData, '/downloads/');
final path = await controller.startDownload(videoData, '/storage/emulated/0/Download');
print('Saved to: $path');
```

---

## 🛡️ Stealth Technology

To ensure longevity, `dart_dlp` mimics human behavior.

1.  **User-Agent Rotation**: Every request pulls from a library of 50+ modern User-Agents (Chrome, Firefox, Safari on Windows, Mac, Linux).
2.  **Request Factory**: We inject trusted headers (`Sec-Fetch-Mode: navigate`, `Sec-Fetch-Site: none`) to bypass "naive" bot filters.
3.  **Proxy Injection**: Support for residential proxies via the `proxy` parameter allows for massive scraping operations (100k+ requests/day).

---

## 🔮 Extending dart_dlp

We built a factory tool so you can add support for new sites in seconds.

### The Hamas Factory
Use the CLI tool to generate a new extractor template. This ensures your code complies with our strict architectural standards.

```bash
dart run tool/hamas_factory.dart my_new_site
```

**Output:** `lib/src/extractors/my_new_site_extractor.dart`

This file comes pre-loaded with:
- `/// Developed by Hamas` header.
- `JsonScraper` mixin.
- Correct `canHandle` and `extract` signatures.

---

## ⚠️ Disclaimer
**dart_dlp** is an educational tool designed for interoperability and data portability. Use this engine responsibly and respect the Terms of Service of the platforms you interact with.

---

## 🔒 Strict Ownership & Security
**dart_dlp** is protected by a strict security policy. 

-   **Owner-Only Access**: Only the repository creator (@Hamas) is authorized to approve changes, merge Pull Requests, or modify the repository configuration.
-   **Documentation Locked**: The `README.md` and `CONTRIBUTING.md` files define the laws of this repository. **No one else is permitted to edit, alter, or dilute these rules.** Any Pull Request attempting to modify these files without explicit prior authorization will be closed and the user blocked.

---

/// Developed by Hamas | dart_dlp Engine
