# Tap spike: capturing a muted child process (HQ-429)

Plan step 1 of `./docs/plans/2026-11-16-optimization-plan.md`. Status: **code and silent tests done; the capture run
is waiting for the System Audio Recording permission.** The observed values below are filled in after that run.

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

## Mute behavior, as observed

Pending the run. Expected from the dossier, unconfirmed:

| Behavior | Tap captures | Child heard on its device |
|---|---|---|
| `unmuted` | yes | yes |
| `muted` | yes | no, while the tap exists |
| `mutedWhenTapped` | yes | no while the tap is read; yes while it exists but is idle |

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

- Every row of the mute table and the rebuild assertion: they need the permission run.
- Whether the tap's own format rate differs from the aggregate rate when the child's device runs at another rate.
- Whether a tap of a process playing to a non-default device is captured at all on 26.4 (the spike answers it).
