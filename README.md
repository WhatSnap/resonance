# 🌀 Resonance

### For Those Who Seek the Original Tone
**[resonance.whatsnap.ai](https://resonance.whatsnap.ai)**

The modern world has distanced us from our natural frequency. Today, we remember. Resonance is a macOS application designed to real-time tune your entire system audio to **432Hz**—the pulse of the Earth, the vibration through which Sacred Geometry manifests in its purest form.

---

## 📽️ The Vision

432Hz is not merely a number. It is a return to original harmony. What Cymatics reveals through visible patterns in matter, Resonance delivers through every sound you hear.

When you tune to 432Hz, you do not simply create music—you create a sanctuary of peace. You become an emitter of resonant coherence, allowing the molecular structures of those who listen to recover their natural geometric organization.

---

## 🚀 Features

- **System-Wide Tuning**: Retunes everything your Mac plays, with Apple's `NewTimePitch` AudioUnit.
- **Follows Your Output**: Plays on whatever output macOS is using (speakers, AirPods, a USB DAC) and follows it when it changes. Volume keys keep working.
- **Nothing to Install Besides the App**: No virtual audio driver, no Audio MIDI Setup.
- **Menu Bar Utility**: Stay in the flow with a lightweight menu bar interface. Open at login is optional.

---

## 🛠️ Installation

Requires macOS 14.4 or later.

1. Download `Resonance-2.0.dmg` from the [latest release](https://github.com/WhatSnap/resonance/releases/latest).
2. Open the DMG and drag Resonance.app to Applications.
3. Open Resonance. The app is not notarized yet, so the first time macOS blocks it: go to
   **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Resonance, and confirm.
4. Allow audio recording when macOS asks (once).
5. Turn it on from the menu bar icon.

---

## 🧠 Technical Architecture

- **Capture**: A Core Audio process tap captures what other apps play and mutes the original, so you hear only the retuned audio.
- **Buffer**: A single-producer, single-consumer ring buffer between the tap and the output. Its read and write paths use atomics only: no locks and no allocation on the audio threads (`scripts/check-realtime.sh` checks the release build).
- **Output**: An AUHAL unit renders through `NewTimePitch` to the current default output, in **32-bit Float Non-Interleaved** at the device's native sample rate. Clock drift between the two devices is absorbed by the buffer.

---

## 🛠️ Development

### Prerequisites
- macOS 14.4+
- Swift 6.1 (Command Line Tools are enough)

### Build and test
```bash
./scripts/test.sh
./scripts/build-app.sh      # builds Resonance.app into .build/app
```

### Create DMG
```bash
./build-dmg.sh
```

---

## 📜 License

Resonance is released as Open Source. We invite musicians, therapists, and seekers of sound to contribute and explore.

*"Let us return to the original harmony. Let us become the echo of creation once again."*

**Resonance · 2026**
🌀

