# Roadmap

Working list of things to fix / build. Newest items at top of each section.

## Bugs (regressions from the SwiftUI rewrite)

_None right now._

## Display / polish

_None right now._

## Design

- **iOS 26 / Liquid Glass pass** — adopt the iOS 26 design language (Liquid Glass materials, updated controls/navigation). Scope TBD — audit the UI for where the new look applies.

## Features

- **Live Activity for active workouts** — add a Live Activity view (Lock Screen / Dynamic Island) showing the in-progress workout.

## UX flow

_None right now._

## Port to Wavelength

- **Finalize legal / contact / attribution** — replace OutRun/Tadris terms, privacy, and contact links with real Wavelength values; finalize license/source-publication wording.
  - **GPLv3-or-later is copyleft (NOT AGPL).** OutRun is licensed GPL-3.0-or-later — every file header says so. The Move: Feet port must stay GPLv3-or-later and ship its complete corresponding source to anyone who receives the binary. It is *distribution of the binary* that triggers source disclosure — **not** network use (that AGPL trigger does not apply here). Not just an attribution line. Full analysis: `docs/MOVEFEET_FORK_AUDIT.md`.
  - **App Store legal gate** — a third-party GPLv3 fork conflicts with Apple's terms (the 2011 VLC precedent). Plan: email Tim Fraedrich for a GPLv3 §7 App Store distribution exception; timebox ~3–4 weeks; differentiate the app; proceed as a documented risk-accepted decision if no reply.

## Done

- **Workout detail charts y-axis** — charts now use a padded data-driven y-axis range instead of always starting at `0`.
- **Rework "stop workout" confirmation** — moved the stop/save/continue/discard confirmation into the main bottom workout controls instead of showing a floating top banner.
- **Workout selector broken** — restored the New Workout bottom-left workout type picker.
- **Apple Health import broken** — wired Settings back to the existing Apple Health import list.
- **Decimal point in main list** — main timeline distances now show one decimal place for miles/km (e.g. `3.1 mi` instead of `3 mi`).
- **Stop workout: two-step discard** — **Discard** now requires confirmation before discarding.
- **Stop workout: save closes card** — **Save** now closes the workout screen and returns to the list after a successful save.
- **Audit legal / contact / attribution** — reviewed legal/contact/source links and added safer in-app source/original attribution rows plus a README port notice.
