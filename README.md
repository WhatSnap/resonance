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

- **System-Wide Tuning**: Processes all macOS audio through a high-precision 432Hz pitch shifter.
- **Low Latency**: Built on a custom CoreAudio `AUGraph` architecture with a lock-free ring buffer for real-time performance.
- **Guided Onboarding**: A beautiful setup wizard to help you configure the required virtual audio driver.
- **Menu Bar Utility**: Stay in the flow with a lightweight menu bar interface.
- **Native Performance**: Pure Swift implementation leveraging Apple's `NewTimePitch` AudioUnit for superior quality.

---

## 🛠️ Installation

### 1. Install Audio Driver (Required)
Resonance captures system audio using the **BlackHole** virtual audio driver. 
- You can find the installer bundled in the [latest release DMG](https://github.com/Eddy-G/Resonance/releases).
- Alternatively, install via Homebrew: `brew install blackhole-2ch`.

### 2. Configure Multi-Output Device
To hear your tuned audio, you must create a Multi-Output device in **Audio MIDI Setup**:
1. Open **Audio MIDI Setup**.
2. Click **+** → **Create Multi-Output Device**.
3. Check both **BlackHole 2ch** and your **Output Device** (e.g., AirPods Max, Speakers).
4. Set your System Output to this new Multi-Output Device.

### 3. Run Resonance
1. Launch Resonance.
2. Select your actual output device (e.g., AirPods Max) from the menu bar picker.
3. Click **Enable**.

---

## 🧠 Technical Architecture

Resonance uses a sophisticated "Pull Pattern" to bypass the limitations of high-level frameworks like `AVAudioEngine`:

- **Push Stage**: A standalone `AUHAL` unit captures audio from BlackHole and pushes it into a deinterleaved ring buffer.
- **Pull Stage**: A CoreAudio `AUGraph` pulls from the ring buffer, applies the pitch shift, and renders to the hardware output.
- **Format**: All processing is done in **32-bit Float Non-Interleaved** at the device's native sample rate to ensure maximum fidelity.

---

## 🛠️ Development

### Prerequisites
- macOS 13.0+
- Xcode 15+ / Swift 6.0

### Build
```bash
swift build -c release
```

### Create DMG
The project includes a custom distribution script:
```bash
./build-dmg.sh
```

---

## 📜 License

Resonance is released as Open Source. We invite musicians, therapists, and seekers of sound to contribute and explore.

*"Let us return to the original harmony. Let us become the echo of creation once again."*

**Resonance · 2026**
🌀

