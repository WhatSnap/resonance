# Tap spike: capturing a muted child process (HQ-429)

Plan step 1 of `./docs/plans/2026-11-16-optimization-plan.md`. Status: **done.** The capture run passed on
2026-11-16 on Luis's Mac (macOS 26.4), once, after he granted the System Audio Recording permission.

## What was built

- `./Library/Tap/ProcessTapCapture.swift`: a `CATapDescription(stereoMixdownOfProcesses:)` for the listed processes
  only (a global tap is refused by a precondition), wrapped in a private aggregate device clocked by a named device,
  read with an IOProc. The aggregate's input buffer list holds the clock device's input buffers first, then the tap
  buffers (`clockBufferRange`, `tapBufferRange`).
- `./Library/Tap/CoreAudioObjects.swift`: read-only lookups (default output, UID to device, PID to process object,
  sample rate, buffer layout).
- `./Library/Tap/SignalAnalysis.swift`: RMS, FFT peak frequency (Hann window plus Gaussian interpolation, within
  0.5 Hz on a 2 s sine), single-tone level, and `SilenceWatchdog`, which decides when an all-zero tap must be rebuilt.
- `./Tests/Tap/ProcessTapSpikeTests.swift`: the spike. Off unless `RESONANCE_TAP_SPIKE=1`.

## How the spike stays silent

1. The child process plays a 997 Hz sine **only to BlackHole 2ch** by UID. It never opens the default output.
2. The aggregate device is clocked by BlackHole, not by the speakers, and its output buffers are never written.
3. The test refuses to run while the Resonance app is open, because that app plays BlackHole's input on the speakers.
4. The tap lists only the child's process object. A global tap is never created.
5. The test reads the default output device before and after, and asserts they are the same. Nothing writes it.

So even if a mute behavior did not mute, the sine would land in BlackHole and nowhere else.

## How mute is observed

BlackHole loops its output back to its input, and the aggregate exposes BlackHole's input next to the tap. For each
`CATapMuteBehavior`, the test measures the 997 Hz level in two places at once:

- **tap buffers**: what the tap captures (must be the sine, RMS above 0, peak within 1 Hz);
- **BlackHole loopback**: what the child's device actually receives (the sine if the child is heard, near zero if
  the tap muted it).

A reference loopback level is taken before any tap exists. For `mutedWhenTapped`, the loopback is also read with the
tap created but IO not started.

## Run results (2026-11-16)

| Check | Result |
|---|---|
| Captured RMS (sine amplitude 0.25, ideal 0.177) | 0.1767 muted, 0.1765 unmuted, 0.1767 mutedWhenTapped |
| FFT peak (tone 997 Hz) | 997.011 Hz in all three runs |
| System default output before / after | `BuiltInSpeakerDevice` / `BuiltInSpeakerDevice` |
| Mute behavior reported by the live tap | equal to the one set, for all three |
| Capture after `rebuild()` (muted) | RMS 0.1767 |
| Rates | BlackHole 48 kHz, aggregate 48 kHz, tap format 48 kHz |
| Aggregate input layout | buffer 0 = BlackHole input (2 ch), buffer 1 = tap (2 ch, interleaved) |

A process playing to a **non-default** device (BlackHole) is captured: the stereo-mixdown tap follows the process,
not the default output.

## Mute behavior, as observed

Tone level the child's device receives (BlackHole loopback at 997 Hz). Reference with no tap: 0.250.

| Behavior | Tap captures | Child heard on its device |
|---|---|---|
| `unmuted` | yes | yes: 0.250 |
| `muted` | yes | **no: exactly 0** while the tap exists and is read |
| `mutedWhenTapped` | yes | **yes while the tap exists but is idle (0.250)**; almost silent while it is read (0.0045, about 2% of the level, -35 dB) |

Reading: `muted` silences the process as soon as the tap exists and leaves exact zeros. `mutedWhenTapped`
silences it only while some client reads the tap, and in our 2 s window a small residue remained. That residue is
most likely the time between `AudioDeviceStart` and the first IO cycle reaching the tap, but this was not isolated.

**For the engine (step 5):** use `mutedWhenTapped`. If the app stops reading (crash, rebind, teardown), the original
audio comes back by itself instead of leaving the user in silence. Accept a short overlap of original audio at each
start. If that overlap turns out audible on Luis's listen check, switch to `muted` and make sure every exit path
destroys the tap.

## Recovery from all-zero buffers

Second-hand report (Apple developer forums, in the dossier): a tap can keep returning all-zero buffers, and only
destroying both the tap and its aggregate recovers it. What the code does:

1. **Detect.** `SilenceWatchdog` counts consecutive buffers whose peak is exactly 0. With `armOnFirstSignal`, silence
   before the first non-zero buffer does not count (a source that has not started is not a broken tap). Real
   silence in music is rarely exact zeros, but the engine (step 5) should also pause the watchdog while nothing plays.
2. **Tear down, in this order:** `AudioDeviceStop` on the aggregate, `AudioDeviceDestroyIOProcID`,
   `AudioHardwareDestroyAggregateDevice`, `AudioHardwareDestroyProcessTap`.
3. **Rebuild:** a new `CATapDescription` with a fresh UUID, a new aggregate with a fresh UID, a new IOProc, start.
   `ProcessTapCapture.rebuild()` does steps 2 and 3. The spike asserts that capture works again after a rebuild.

Also seen while building: all-zero buffers are what a tap delivers when the System Audio Recording permission was
not granted, so the engine must tell "no permission" apart from "broken tap" before rebuilding in a loop.

## Not verified yet

- The `mutedWhenTapped` residue: whether it is only the start-up gap, or a steady leak. A test that measures the
  loopback in 100 ms windows after start would settle it.
- A real all-zero failure was not reproduced; the rebuild was exercised on a working tap only.
- A tap and its child device at different rates (here all ran at 48 kHz).
- Taps of a global mixdown (excluding Resonance), which step 5 needs. Never run without warning Luis: it mutes his audio.

## Step 0 of HQ-433: mute behavior settled (2026-11-16)

Harness: `./Tests/Tap/MuteBehaviorStepZeroTests.swift` (`RESONANCE_TAP_SPIKE=1`), BlackHole child only, 997 Hz at 0.25.
Default output `BuiltInSpeakerDevice` before and after. Tone level on the child's device, reference with no tap 0.250.

| Check | `muted` | `mutedWhenTapped` |
|---|---|---|
| Tap held by another process, while it reads | 0 | 0 |
| That process killed with SIGKILL: first 100 ms window | 0.170 | 0.170 |
| Windows 2 to 20 after the kill | 0.250 | 0.250 |
| In-process start: first 100 ms window | 0.107 | 0.160 |
| Windows 2 to 20 after start | exactly 0 | exactly 0 |
| After stop | 0.250 | 0.250 |

Reading: Core Audio drops a dead client's tap at once, so `muted` never leaves the user in silence after a crash. The
`mutedWhenTapped` residue in the spike was the start transient only (first window), not a steady leak.

**Decision (lead's default, both checks passed): `muted`, with the output started first and the tap created last.**

Also measured: an aggregate holding only the tap (no clock sub-device) runs and carries the tone (RMS 0.174 for an
ideal 0.177). The engine uses that shape, so the capture clock does not depend on the output device.
