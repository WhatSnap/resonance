# TASK_LOG — resonance

Newest first. The lead's notebook (resonance-lead).

## 2026-11-16 13:20Z — Engine landed; Luis's listen check open (HQ-433)

- **True now:** HQ-433 (tap engine, PASS on 846887a) and the HQ-434 Library part (PASS on a12204b) have landed on
  `hq-423-optimization` (7aa6b3a, local, not pushed). The app is built at
  `~/.hq/work/resonance-build-433/app/Resonance.app` (2.0, ad-hoc signed). The signing research is
  `./docs/research/2026-11-16/signing.md`. The session was idle overnight after 00:05Z: no morning note was written.
- **Waiting on Luis:** L5S3, the listen check (`./docs/gates/2026-11-16-listen-check.md`); S8G4, the signing choice, money
  (`./docs/gates/2026-11-16-signing.md`).
- **In flight:** `resonance-build-448` (HQ-448, the watchdog rebuilds on pauses: HQ-433 review finding 1) and
  `resonance-build-434-2` (HQ-434 wiring: settings + Open at login in the menu; review findings 1–4).
- **Queued:** HQ-435 cleanup (after the wiring lands, to avoid Sources/ conflicts). HQ-446 build after S8G4.
- **Push:** none. When the whole plan is green, ask Luis for one push of `hq-423-optimization` and a PR.

## 2026-11-16 ~23:52Z — Night run (hq brief: ~/.hq/work/hq/night-2026-11-16.md)

- **True now:** HQ-429, 430, 431 and 432 have landed on `hq-423-optimization` (2f64a67, local, not pushed: the repo is
  shared, so push is red). HQ-446 is filed (signing, step 8).
- **In flight (3 workers, the cap):** `resonance-build-433` (engine, critical path; step 0 mute check first, and it
  builds a runnable .app), `resonance-build-434` (settings + login item, Library only, no Sources/ edits),
  `resonance-research-446` (signing options doc).
- **Queued:** the HQ-433 review → land → the listen-check card for Luis in the morning. HQ-434 wiring in Sources/ after
  433. HQ-435 cleanup after 433. HQ-446: the ask page (money) once the research doc lands.
- **Morning note:** `~/.hq/work/resonance-lead/for-luis-1100.md` by 08:30Z.

## 2026-11-16 — HQ-429, 430, 431 landed; 432 in review (HQ-423)

- **True now:** on local branch `hq-423-optimization` (not pushed): HQ-430 offline pitch tests, HQ-431 device router,
  HQ-429 tap spike (capture ran once on Luis's Mac with his OK, C7T2: Warp now holds the System Audio Recording
  permission). P4N1 (plan) and C7T2 are recorded. Each landed after a PASS review on its commit.
- **In flight:** `resonance-review-432` reviews HQ-432 (4be925c). It adds swift-atomics, and write/render take hostTime.
- **Next:** land 432 on PASS → open the HQ-433 worker. Its first step is the mute-behavior check (kill -9 and 100 ms
  windows), with `muted` as the default. Inputs are in the HQ-433 comments.
- **Test command:** `./scripts/test.sh` (Command Line Tools only, no Xcode).

## 2026-11-16 — Plan approved, build started (HQ-423)

- **True now:** Luis approved the plan in this window ("go si rearmalo de la mejor manera"). The record of P4N1 was refused
  by the gate (NO_GO, turn check), so it is re-asked in one line. Plan and dossier are committed on the local branch
  `hq-423-optimization`.
- **Issues (children of HQ-423):** HQ-429 tap spike · HQ-430 DSP baseline test · HQ-431 device router · HQ-432
  lock-free buffer · HQ-433 tap engine (blocked by 429, 431, 432) · HQ-434 settings + opt-in login · HQ-435 cleanup.
  Signing (step 8) is not filed yet: it gets filed and asked (money) when 435 lands.
- **In flight:** workers `resonance-build-429`, `-430`, `-431`, `-432`, each on its own branch off
  `hq-423-optimization`. Shared rules: `~/.hq/work/resonance-lead/briefs/build-common.md` (fixed package layout:
  `Library/` = ResonanceCore, `Tests/`).
- **Critical path:** HQ-429 → HQ-433 → Luis's listen check.
- **Waiting on Luis:** the one-line re-ask of P4N1 (record only). Later: the macOS audio-capture prompt (HQ-429), and the
  2-minute listen (after HQ-433).
- **Gate:** each branch lands on `hq-423-optimization` only after a PASS review on the same commit. Luis has admin on
  the GitHub repo, and the push is still asked.

## 2026-11-16 — Dossier done, plan proposed, waiting on Luis (HQ-423)

- **True now:** the dossier `./docs/research/2026-11-16/resonance-audio-routing.md` is written (worker closed). Root
  cause: the system output is a Multi-Output device (no volume control), and the app only renders to the device picked
  in its menu and never follows the default output. The current setup also plays the original and the shifted audio
  together.
- **Plan:** `./docs/plans/2026-11-16-optimization-plan.md`: Core Audio process tap (no driver), render to the current
  default output, 8 steps. Critical path 1 → 5 → Luis's listen check.
- **Lead's assumptions (not asked):** min macOS 14.4; the shift pauses on AirPods calls (HFP); launch at login is
  opt-in; BlackHole stays installed and is used as a silent test sink; signing is decided at step 8.
- **Waiting on Luis:** ask P4N1, plan approval (`./docs/gates/2026-11-16-plan-approval.md`), default hold, deadline
  2026-11-18 15:00Z.
- **On go:** file steps 1–7 as HQ children of HQ-423, branch `hq-423-optimization`, open workers 1–4 in parallel.

## 2026-11-16 — Optimization initiative started (HQ-423)

- **Critical path:** HQ-423, "Resonance: gather context and agree the optimization plan". No code changes until Luis
  approves the plan.
- **In flight:** worker `resonance-research-423` (research) writes
  `./docs/research/2026-11-16/resonance-audio-routing.md`: how routing works today, the root causes of the volume-key and
  AirPods/device-change failures, prior art (eqMac, BackgroundMusic, Core Audio process taps), options, how to test
  in the background, and at most 3 questions for Luis. Brief: `~/.hq/work/resonance-lead/briefs/research-hq-423.md`.
- **Next:** read the dossier, ask Luis the questions (at most 3, with defaults), write the plan in `./docs/`, get his
  approval, then file one build issue per change and open workers (tests first).
- **Waiting on Luis:** nothing yet.
- **Not done:** no plan, no build issues, no code changes. Repo is WhatSnap's (shared): local branch commits only, no
  push without Luis's OK. Installing a driver, HAL plugin, launch agent or anything that needs sudo is asked to Luis first.
