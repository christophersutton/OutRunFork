# Roadmap

Working list of things to fix / build. Newest items at top of each section.

## Bugs (regressions from the SwiftUI rewrite)

_None right now._

## Display / polish

- **Workout detail charts y-axis** — charts need to zoom to real y values instead of always starting at `0`.

## Design

- **iOS 26 / Liquid Glass pass** — adopt the iOS 26 design language (Liquid Glass materials, updated controls/navigation). Scope TBD — audit the UI for where the new look applies.

## Features

- **Live Activity for active workouts** — add a Live Activity view (Lock Screen / Dynamic Island) showing the in-progress workout.

## UX flow

- **Rework "stop workout" confirmation**
  - Move the confirmation dialog into the main bottom area instead of a new floating element at the top.

## Port to Wavelength

- **Finalize legal / contact / attribution** — replace OutRun/Tadris terms, privacy, and contact links with real Wavelength values; finalize license/source-publication wording.
  - **AGPL is copyleft** — the Wavelength port must itself stay AGPL-licensed and source-available (network use triggers the source-disclosure obligation). Not just an attribution line.

## Done

- **Workout selector broken** — restored the New Workout bottom-left workout type picker.
- **Apple Health import broken** — wired Settings back to the existing Apple Health import list.
- **Decimal point in main list** — main timeline distances now show one decimal place for miles/km (e.g. `3.1 mi` instead of `3 mi`).
- **Stop workout: two-step discard** — **Discard** now requires confirmation before discarding.
- **Stop workout: save closes card** — **Save** now closes the workout screen and returns to the list after a successful save.
- **Audit legal / contact / attribution** — reviewed legal/contact/source links and added safer in-app source/original attribution rows plus a README port notice.
