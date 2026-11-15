# TASK_LOG — resonance

Newest first. The lead's notebook (resonance-lead).

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
