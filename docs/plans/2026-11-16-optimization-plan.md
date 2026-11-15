# Resonance optimization plan

HQ-423 · resonance-lead · 2026-11-16 · status: **approved by Luis 2026-11-16** · issues HQ-429…HQ-435
Source: `./docs/research/2026-11-16/resonance-audio-routing.md` (root causes R1–R13 referenced below).

## Goal (Luis, 2026-11-16)
Resonance works with few system changes, follows AirPods and any other output without pressing buttons, and the
volume keys keep working.

## Decision
Replace the BlackHole + Multi-Output capture with a **Core Audio process tap** (macOS 14.2+, no driver). The real device
stays the system default, so the volume keys and AirPods switching stay native (fixes R1, R4, R5). The app renders
the shifted audio to whatever the current default output is and rebinds when it changes. This also removes the double
audio (original plus shifted on the same device).
Reference implementation: `pc418/pitchshifter` (Apache-2.0), read for the tap and aggregate setup. It is not a dependency.

## Assumptions (decided by the lead, reversible)
- **Minimum macOS goes from 13 to 14.4.** Luis runs 26.4. Users on 13 keep v1.0.0.
- **During calls on AirPods the shift pauses.** It pauses when the output drops to the headset profile (≤ 24 kHz) and
  resumes when the rate is back.
- **Launch at login is an opt-in toggle in the app, off by default** (`SMAppService.mainApp`). Nothing registers
  unless Luis turns it on.
- **BlackHole stays installed on Luis's Mac.** The app stops needing it. Uninstalling it is his choice. The tests use
  it as a silent sink while it is installed.
- **Signing is decided later (step 8).** It does not block steps 1–7.
- Work goes on the local branch `hq-423-optimization`. Nothing is pushed without Luis's OK.

## Steps, in order
One Linear issue per step (team HQ, children of HQ-423), one worker per issue. Each worker writes the tests first.

| # | Change | Fixes | Depends on | Tests (all silent) |
|---|---|---|---|---|
| 1 | **Tap spike.** Minimal tap + private aggregate + IOProc in a test target. Capture a child process that plays a sine, with that process muted. Confirm the `CATapMuteBehavior` semantics and the teardown/rebuild needed when a tap returns all-zero buffers. | Proves A | — | The captured RMS is above 0 and the FFT peak sits at the sine's frequency. Only the child process is muted. The system default output is unchanged before and after the test. |
| 2 | **DSP baseline.** Add a test target. Run an offline `NewTimePitch` render for each `PitchMode`. | Guards later steps | — | A 440 Hz input gives a 432 Hz output peak ± 0.5 Hz, rendered offline with no device. |
| 3 | **Device layer.** A `DeviceProvider` protocol with a Core Audio implementation. It listens to the default output, `DeviceIsAlive`, the nominal sample rate and wake, and debounces changes. | R4–R7, R9 | — | Fake provider scenarios: AirPods connect and disconnect, default switch, rate drop to HFP, wake. An unrelated device appearing causes no restart. |
| 4 | **Ring buffer.** A lock-free SPSC buffer with a target fill level and drift correction. It replaces the `NSLock` buffer. | R10–R12 | — | Two simulated clocks (48000 vs 48001 Hz) run for 10 simulated minutes. The fill level stays in its band, with no dropped chunk and no underrun. |
| 5 | **New engine.** Tap capture (from 1) → ring buffer (4) → `NewTimePitch` → current default output (3). The shift pauses on HFP. Errors appear in the menu, not only in `print`. | R1, R4–R7 | 1, 3, 4 | Integration test: tap a child process, render to BlackHole 2ch (silent sink), read BlackHole back and check the 432 Hz peak. Nothing reaches Luis's speakers. |
| 6 | **Settings.** Persist enabled, pitch mode and the last state. Add the opt-in launch-at-login toggle. | R8 | 5 | Unit tests on the settings store. Relaunch keeps the state. |
| 7 | **Cleanup.** Remove the BlackHole wizard, the Multi-Output instructions, the microphone permission, `./Core/` and the unused DSP files. Add `NSAudioCaptureUsageDescription`. Raise the minimum to 14.4. Rewrite the README setup to one step. | Simpler setup | 5 | `swift build` is clean, the tests pass, and `grep` finds no BlackHole reference in `./Sources`. |
| 8 | **Signing.** A stable signature, so the System Audio Recording permission survives rebuilds and updates (R13). Asked to Luis when we reach it (it may cost a Developer ID). | R13 | 7 | Rebuild twice and check the permission persists. |

**Critical path:** 1 → 5 → Luis's listen check. Steps 2, 3 and 4 run in parallel with 1.

## Testing without disturbing Luis
- Every automated test is silent. Nothing plays to his speakers or AirPods, nothing changes his default output, and
  no window opens (background-testing rule).
- The engine is never run with a **global** tap during his work, because it would mute his audio. Tests only tap a
  child process that the test spawns itself.
- **Two moments need him:**
  1. **Once, step 1:** macOS asks for the System Audio Recording permission the first time a tap starts. He clicks
     Allow. The lead tells him beforehand, when he is at the Mac.
  2. **Once, after step 5 (about 2 minutes):** music on the speakers, volume keys up and down, connect AirPods, then
     disconnect them, then sleep and wake. He reports whether the volume worked and whether the audio followed the
     device. The 432 Hz itself is already verified by the tests.

## Landing
Each step lands on `hq-423-optimization` only after a PASS review on the same commit. The DMG and the GitHub release
are a push, which Luis approves separately.

## Not in this plan
- An own HAL driver (option C): not needed, because taps exist.
- Keeping macOS 13 support.
- Any change to the website (`resonance.whatsnap.ai`).
