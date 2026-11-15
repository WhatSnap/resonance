# Resonance: how it routes audio, why it breaks, and how others solve it

HQ-423 · research by resonance-research-423 · 2026-11-16 · read-only (no code changed, no audio played, no device touched)

## Answer first

1. **Both of Luis's problems come from the same design choice: the system output is a Multi-Output device, not the real device.**
   - A Multi-Output device has no master volume, so the volume keys have nothing to control. Resonance never touches volume anywhere in the code.
   - The app only ever renders to the device picked in its own menu. It never looks at the system default output, so AirPods never "just work".
2. **Today's setup also plays the signal twice.** The Multi-Output sends the *un-shifted* audio to the real device, and Resonance sends the *shifted* audio to the same device. They mix (440 and 432 together).
3. **The fix is to stop using BlackHole and the Multi-Output.** Since macOS 14.2 an app can capture system audio with a Core Audio process tap, with no driver. The real device stays the default, so the volume keys and AirPods keep working natively. An open-source Apache-2.0 app that does exactly this already exists: `pc418/pitchshifter`.
4. **Recommendation: Option A (process tap).** Conviction **Alta (85%)** that it is the right direction. Conviction **Media (60%)** that volume keys work perfectly the first time. That one is unverified and needs a 2-minute listen by Luis (section 5).
5. Luis's Mac runs macOS 26.4 (`sw_vers`), so every option below is available to him. Right now his default output is MacBook Pro Speakers and no Multi-Output device exists: Resonance is not configured on this Mac at the moment.

## 1. How it works today

The package builds `./Sources` only (`./Package.swift:17`), a SwiftUI menu-bar app, macOS 13+.

| Stage | What happens | Where |
|---|---|---|
| Capture | An AUHAL input unit bound to **BlackHole 2ch** (found by name match) pulls audio into a ring buffer. | `./Sources/Audio/CoreAudioPitchGraph.swift:59-165`, `./Sources/Audio/AudioDeviceManager.swift:53-55` |
| Buffer | Two float arrays, 16384 frames each, guarded by one `NSLock`. | `CoreAudioPitchGraph.swift:17-23` |
| Processing | An AUGraph: `NewTimePitch` (pitch in cents, rate 1) feeding an AUHAL output. A render callback drains the ring buffer. | `CoreAudioPitchGraph.swift:167-267` |
| Output | The output AUHAL is bound to `selectedDeviceID`, the device chosen in the menu. | `CoreAudioPitchGraph.swift:202-203`, `./Sources/UI/MenuBarView.swift:38` |
| Format | Float32 non-interleaved stereo at the **output device's** nominal rate, read once at start. | `./Sources/Audio/AudioEngine.swift:164`, `CoreAudioPitchGraph.swift:57` |
| State | `isEnabled`, `selectedDeviceID`, `pitchMode` live in memory only. The one persisted value is `setupComplete`. | `AudioEngine.swift:63-68`, `MenuBarView.swift:7` |

**What Luis must install and configure** (`./README.md` "Installation", `./Sources/UI/SetupView.swift:145-152`):
- Install BlackHole 2ch. It is a HAL driver in `/Library/Audio/Plug-Ins/HAL`, installed with admin rights. It is already on this Mac.
- Build a Multi-Output device in Audio MIDI Setup with BlackHole **and** the real device ticked.
- Set that Multi-Output as the system output.
- In the app, pick the real device and click Enable.
- Grant microphone access. The app needs it only because BlackHole is an input device (`./Resources/Info.plist:21`, `./Resources/Resonance.entitlements`).

**What the app writes to the system:** nothing. `grep` finds no `AudioObjectSetPropertyData` call. `getDefaultOutputDeviceID()` is defined (`AudioDeviceManager.swift:70`) and never called. The app does **not** set the default output; all system changes are manual and live outside the app.

**Double audio (inferred from the code and README, not heard):** the Multi-Output sends the original stream to BlackHole *and* to the real device. Resonance then plays the shifted stream to that same real device. Result: original (440) plus shifted (432), delayed by the ring buffer and the pitch unit. That sounds like chorus or phasing. It can only be avoided by leaving the real device *unticked* in the Multi-Output, which the README and wizard tell the user not to do.

**Live vs dead code:**
- `./Core/*` is outside the package path (`Package.swift:17`) and is not built. Its copies of `FFTProcessor.swift` and `PitchShifter.swift` differ from the ones in `./Sources/Audio/`.
- `./Sources/Audio/FFTProcessor.swift` and `PitchShifter.swift` compile but nothing references them. `AudioEngine.onProcess` (line 75) is never set.
- The only live DSP is Apple's `NewTimePitch`. The README's claim of a "lock-free ring buffer" is wrong: it uses `NSLock`.

## 2. Root causes

### 2.1 Volume keys and volume do not work
- **R1. The system output is a Multi-Output device, which has no volume control.** This is a macOS behaviour, not an app bug. I could not test it here because no Multi-Output exists on this Mac. Background Music's issue tracker shows the same symptom with a Multi-Output as default: [BackgroundMusic #708](https://www.Github.com/kyleneideck/BackgroundMusic/issues/708), second-hand.
- **R2. The app has no volume code at all.** `grep` for volume properties finds nothing. Even if the keys moved something, the shifted stream is rendered to the real device at unity gain (`CoreAudioPitchGraph.swift:203-210`), and the original stream goes straight to that device through the Multi-Output.
- **R3. The only app-side control is on/off and the pitch.** Nothing in `MenuBarView.swift` or `PreferencesView.swift` adjusts level.

### 2.2 AirPods and other output changes
What the app listens to: **one** property, `kAudioHardwarePropertyDevices` on the system object (`AudioEngine.swift:101-135`).

What it does not listen to:
- `kAudioHardwarePropertyDefaultOutputDevice`
- `kAudioDevicePropertyDeviceIsAlive`
- `kAudioDevicePropertyNominalSampleRate`
- sleep/wake (`NSWorkspace.didWakeNotification`)
- the AirPods switch to the headset (HFP) profile when a mic opens, which changes the sample rate

Resulting failures:
- **R4. AirPods connect and the app keeps rendering to the old device.** The refresh keeps `selectedDeviceID` if it is still in the list (`AudioEngine.swift:96-98`), so the new AirPods are never selected. Luis has to open the menu and pick them. This is the "press buttons" problem.
- **R5. AirPods disconnect and the app jumps to an arbitrary device.** When the selected device vanishes, the fallback is `availableDevices.first` (`AudioEngine.swift:97`), whatever the HAL lists first. It may be the speakers while the system output moved elsewhere.
- **R6. Every device-list change restarts the whole graph,** even unrelated ones (Zoom, Camo, Hue Sync, the Multi-Output itself being created). The restart is `stop()` then rebuild (`AudioEngine.swift:117-126`), so audio drops each time. A failed restart is only `print`ed (line 123): the user sees the status flip to inactive with no message.
- **R7. The sample rate is read once.** `AudioEngine.swift:164` reads the output rate at start. If the rate changes later (AirPods A2DP to HFP, or an Audio MIDI change), the graph keeps the stale rate and the output is wrong or silent until a manual restart. Nothing listens for the change.
- **R8. Nothing persists.** After a relaunch or reboot the app is Disabled, the pitch is back to 432 and the output is the first device in the list (`AudioEngine.swift:63-68`, `96-98`). There is no launch-at-login.
- **R9. Sleep/wake is untested and unhandled.** No code path. Whether it recovers depends on the device-list notification firing; I could not verify it.

### 2.3 Other fragility
- **R10. Locks on real-time threads.** Both audio callbacks take the same `NSLock`; the input one holds it across `AudioUnitRender` (`CoreAudioPitchGraph.swift:93-94`, `116`, `221-222`). A priority inversion here gives clicks.
- **R11. No clock-drift handling.** BlackHole and the real device have different clocks (Bluetooth most of all). On overflow the input callback drops the whole chunk (`:96-98`). On underrun the output writes silence and consumes nothing (`:227-232`). Either way: periodic crackle. There is no target fill level, so latency can drift anywhere between 0 and the full buffer (16384 frames = about 341 ms at 48 kHz). I did not measure any of this.
- **R12. Race on stop/start.** `stop()` sets `inputUnit = nil` from the main thread while the callback reads it (`:91`, `:281-286`). Low risk but real.
- **R13. Signing.** The DMG is ad-hoc signed (`./build-dmg.sh:80-88`). Unverified: whether a microphone/audio permission grant survives an update of an ad-hoc-signed app. The DMG already needed a Gatekeeper workaround (`git log`, commit 0468212).

## 3. Prior art

| Tool | Capture | Installs | Follows default output | Volume keys |
|---|---|---|---|---|
| **BackgroundMusic** ([repo fork with dev notes](https://github.com/gchilds/LoomBackgroundMusic/blob/loom/DEVELOPING.md)) | Own virtual device, set as the default output. Playthrough reads its input and plays it on the real device. | HAL driver `Background Music Device.driver` in `/Library/Audio/Plug-Ins/HAL`, plus a helper | The app *sets* the virtual device as default at launch and restores the old one on quit. | The virtual device has its own volume. The app listens to it and copies the value to the real device. A [PR](https://github.com/kyleneideck/BackgroundMusic/pull/850) describes a stale-volume bug when the restore order is wrong. |
| **eqMac** ([driver explainer](https://eqmac.app/help/driver/what-is-the-eqmac-audio-capture-driver), [repo](https://github.com/bitgapp/eqMac)) | Custom driver based on Apple's Null Audio Server sample, like BlackHole. Processes and forwards to the chosen output. | A custom audio driver | Open issues mention mute on Bluetooth connect and no auto-select after wake (second-hand). | Issue trackers show volume-key complaints. I found no mechanism description. Unverified. |
| **Proxy Audio Device** ([repo](https://github.com/flori/proxy-audio-device)) | A HAL driver that wraps a real device. | HAL driver | n/a | Its stated purpose: system volume keys controlling devices that have no volume. This is the "custom driver forwards volume" pattern. |
| **Core Audio process taps** ([AudioCap sample](https://github.com/insidegui/AudioCap)) | `AudioHardwareCreateProcessTap` plus a private aggregate device that lists the tap; read it with an IOProc. | **Nothing.** Needs an `NSAudioCaptureUsageDescription` and a user permission prompt. | n/a: the real device stays the default. | n/a: the real device stays the default, so its volume works. |
| **pc418/pitchshifter** ([repo](https://github.com/pc418/pitchshifter)) | Global tap excluding its own process, aggregate device with the tap and the physical output, ring buffer, `AVAudioUnitTimePitch`. Apache-2.0. | Nothing; macOS 14.2+; ad-hoc signed binary | README: "automatically follows your default output device". Mechanics not described. | Not covered in its README. |
| **Rogue Amoeba SoundSource/Audio Hijack** ([blog](https://weblog.rogueamoeba.com/2024/12/13/the-developers-who-came-in-from-the-cold/)) | Moved off its ACE driver to a driver-free capture ("ARK"). Details not public. | Says no extensions or restarts needed | Not found | Not found |
| **Other 432 Hz apps** | `Retuner Pro` (SYQEL, closed source) uses BlackHole. `reTuner` (Kushview, GPL-3) is a file/plugin tool, not system-wide. [432 Hz Converter](https://apps.apple.com/us/app/432-hz-converter/id6751567434) was not examined. | | | |

Sources for the tap behaviour: [AudioCap README](https://github.com/insidegui/AudioCap) (macOS 14.4+ for the permission API; the tap API itself is 14.2+ per [pc418/pitchshifter](https://github.com/pc418/pitchshifter)); a [developer write-up and forum report](https://developer.apple.com/forums/thread/825780) says a tap can return all-zero buffers and that tap and aggregate must both be destroyed and rebuilt to recover.

**Not verified:** Apple's page for `CATapMuteBehavior` did not load. The cases `unmuted`, `muted`, `mutedWhenTapped` and their meaning come from model memory plus one second-hand search. Whether muting the original *and* playing the processed copy to the same device keeps the volume keys working was not confirmed by any source I found.

## 4. Options for Resonance

All steps are build steps, not hours.

### A. Process tap, no driver (recommended)
- **Change:** drop BlackHole and the Multi-Output. Create a global tap excluding Resonance, muted when tapped, wrapped in a private aggregate device. Run the pitch unit and render to the **current default output**. Re-bind on `kAudioHardwarePropertyDefaultOutputDevice`, `DeviceIsAlive`, sample-rate changes and wake.
- **System changes:** none. No driver, no sudo, no Audio MIDI Setup. One permission prompt (System Audio Recording).
- **macOS minimum:** 14.2 for the API, 14.4 for the documented permission flow. Product minimum goes from 13 to 14.4.
- **AirPods:** the default device follows AirPods; the app follows the default. No menu pick.
- **Volume keys:** the real device stays the default, so the keys move the real device's volume. Unverified whether the tap point is before or after device volume. If it is after, there is no double attenuation; if before, the app is unaffected. Needs Luis's ear once.
- **Steps:** (1) tap + aggregate capture with an IOProc and a drift-tolerant ring buffer; (2) render to the default device; (3) default-output / alive / rate / wake listeners behind a testable device-provider protocol; (4) persist settings and add launch-at-login; (5) remove BlackHole, Multi-Output, the wizard and the dead DSP files; (6) signing so the permission survives updates.
- **Risks:** the all-zero-buffer bug needs full teardown/rebuild logic; the mute-while-tapped semantics are unconfirmed; HFP call mode runs at a low rate; apps that opt out of capture; a user who needs macOS 13 loses support.

### B. Keep BlackHole, but make the app own the routing
- **Change:** the app sets BlackHole as the default output itself (like BackgroundMusic), plays through to the real device, mirrors volume if BlackHole exposes it, and restores the default on quit.
- **System changes:** BlackHole driver (admin install). The app changes the default output.
- **macOS minimum:** 13.
- **AirPods:** the app must watch the real default and keep its own pick in step; doable.
- **Volume keys:** only if BlackHole exposes a volume control. I could not verify that; unverified.
- **Steps:** about 6, plus crash-safe restore of the old default.
- **Risks:** a crash leaves the system on BlackHole with no sound (BackgroundMusic's known failure mode); the double-audio issue goes away only if the Multi-Output is gone; still needs the microphone permission.

### C. Own HAL driver (eqMac / BackgroundMusic style)
- **Change:** ship a virtual device with real volume and mute controls and forward them.
- **System changes:** HAL driver in `/Library/Audio/Plug-Ins/HAL`, admin install, coreaudiod restart, notarisation.
- **Steps:** 10 or more, in C++/C and a different toolchain from today's package.
- **Risks:** highest effort and ongoing maintenance. Not worth it when taps exist.

### D. Minimum fix of today's design
- **Change:** auto-pick the default device, persist settings, listen to rate and wake, add drift compensation. Keep BlackHole and the Multi-Output.
- **System changes:** same as today.
- **Volume keys:** **still broken** (R1).
- **Steps:** about 4. Good only as a stopgap; its pieces (listeners, ring buffer) are reused by A.

**Recommendation: A.** Alta (85%) over B/C/D on Luis's stated goals (no system changes, AirPods just work, volume keys work). Use `pc418/pitchshifter` (Apache-2.0) as a reference for the tap and aggregate setup and for its ring buffer, not as a dependency.

## 5. Testing on Luis's Mac without disturbing him

**Fully silent and automatic**
- **DSP offline.** Run `NewTimePitch` in manual rendering mode (`AVAudioEngine.enableManualRenderingMode`) on a 440 Hz sine. Assert the FFT peak lands at 432 Hz ± 0.5 Hz for each `PitchMode`. No device, no sound.
- **Device logic with a fake provider.** Put device list, default output, rate and alive state behind a protocol. Unit-test: AirPods connect, disconnect, default switch, rate change to HFP, wake, restart debouncing, and "never restart on unrelated devices".
- **Ring buffer.** Offline test with two simulated clocks (for example 48000 vs 48001 Hz) and a fill-level assertion over a few minutes of simulated audio.
- `swift build` and `swift test` are fine; they install nothing.

**Needs one human check**
- Creating a tap and starting IO triggers the macOS permission prompt once. It is a dialog, so Luis grants it once when convenient. A test that only measures RMS from an *unmuted* tap makes no sound.
- Never run a muted tap on his Mac unannounced: it silences his audio.

**Only Luis can verify by listening (about 2 minutes, once per build)**
1. Play music with the speakers, volume keys up and down: it should change.
2. Connect AirPods: audio should move and stay shifted, with no click on the menu.
3. Disconnect, then sleep and wake once.
The 432 Hz itself is verified offline, so he does not have to judge the tuning by ear.

## 6. Open questions for Luis

Relay through resonance-lead.

1. **Is dropping BlackHole, and with it macOS 13, acceptable?** The app is public (`resonance.whatsnap.ai`). Default: yes, require 14.4. Conviction **Alta (85%)**.
2. **On AirPods calls, should the shift stay on or pause?** When a call opens the mic, AirPods drop to a low-rate profile and shifting voice may be unwanted. Default: pause shifting automatically while the output runs at 24 kHz or lower. Conviction **Media (60%)**.
3. **Is this a personal tool or a distributed product?** It changes whether to pay for a Developer ID and notarisation so the audio-capture permission survives updates (R13). Default: distributed, so sign properly. Conviction **Media (65%)**.

## Not verified
- Apple's `CATapMuteBehavior` semantics and whether volume keys behave with a muted tap (section 3).
- That BlackHole 2ch exposes a volume control (Option B).
- Actual latency and drop rate of the current graph (R11).
- Sleep/wake behaviour (R9) and permission persistence with ad-hoc signing (R13).
- eqMac's volume and default-follow mechanism (only second-hand issue titles).
- Double audio (section 1) is derived from the README and code; it was not heard.
