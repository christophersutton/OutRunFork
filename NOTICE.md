# NOTICE — Move: Feet

**Move: Feet** is a fork of **OutRun**, an open-source iOS workout tracker.

## Original work

- **OutRun** — Copyright (C) 2020 Tim Fraedrich &lt;timfraedrich@icloud.com&gt;
- Source: https://github.com/timfraedrich/OutRun
- License: GNU General Public License, version 3 or later (GPL-3.0-or-later)

All original OutRun copyright notices and per-file license headers are preserved
in this repository.

## This fork

- **Move: Feet** — Copyright (C) 2026 Chris Sutton / Wavelength
- Source: https://github.com/christophersutton/OutRunFork (repository rename pending)
- License: **GPL-3.0-or-later** — the entire combined work, including all
  modifications, continues to be licensed under the GNU General Public License,
  version 3 or later. See [`LICENSE`](LICENSE) for the full text.

## Statement of modifications (GPLv3 §5a)

In accordance with section 5(a) of the GPLv3, this is notice that the OutRun
source has been modified, with the relevant dates. Significant modifications by
the Move: Feet authors:

- **2026** — Incremental UIKit → SwiftUI migration: every screen and the app
  shell are now SwiftUI; live recording, maps, banners, and the CoreStore data
  layer are retained as UIKit and bridged from SwiftUI. See
  [`docs/MIGRATION_HANDOFF.md`](docs/MIGRATION_HANDOFF.md).
- **2026-06** — Rebrand to "Move: Feet": application name, display name, bundle
  identifier (`com.wcc.movefeet`), a new app icon, and repointed privacy/terms
  and support endpoints (`move.wavelength.computer`). Structural rename of the
  Xcode project, target, scheme, and source directory from `OutRun` to
  `MoveFeet`. See [`docs/MOVEFEET_FORK_AUDIT.md`](docs/MOVEFEET_FORK_AUDIT.md).

For the precise, commit-by-commit history, see the git log.

## Preserved for data compatibility / attribution

To avoid breaking existing user data and to honour the original work, the
following retain their original `OutRun` / `de.tadris` naming and are **not**
rebranded:

- The Core Data schema model identifiers (`OutRunV1`…`OutRunV4`, `OutRunV3to4`)
  and the on-disk store filename (`OutRun.sqlite`).
- The backup format: the `.orbup` extension and its `de.tadris.orbup` uniform
  type identifier — so backups exported from OutRun can still be imported into
  Move: Feet.
- Every original GPLv3 file header and the `Copyright (C) 2020 Tim Fraedrich`
  notice.

## Trademark / name

The GPL covers the source code; it does **not** grant rights to the "OutRun"
name, logo, or app icon. "Move: Feet" uses its own name and icon and does not
represent itself as OutRun.
