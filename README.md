# Move: Feet

Move: Feet is an iOS app for recording and viewing your outdoor workouts — running, walking and hiking. It is a fork of [OutRun](https://github.com/timfraedrich/OutRun) by Tim Fraedrich.

This project is fully open-source (GPL-3.0-or-later) and ad-free.

## Fork notice

Move: Feet is a fork of [OutRun](https://github.com/timfraedrich/OutRun) by Tim Fraedrich. The original OutRun code, copyright notices, and per-file license headers are preserved and remain under the GNU General Public License version 3 or later. The combined work — including all Move: Feet modifications — also remains GPL-3.0-or-later. See [`NOTICE.md`](NOTICE.md) for attribution and the statement of modifications (GPLv3 §5a).

## Features

Feet retains OutRun’s focus on customisation and privacy. The list of features includes:

- Keep full control over your data
- Record your outdoor workouts (Running, Walking and Hiking)
- View detailed statistics
- Export your workouts as GPX or OutRun-Backup (.orbup)
- Fully customise the recording process
- Synchronise with Apple Health

## Development

For repeatable physical iPhone builds, use [`scripts/install-movefeet.sh`](scripts/install-movefeet.sh). It builds `MoveFeet.xcworkspace`, installs `com.wcc.movefeet` on the paired phone, launches it, and verifies the running process. See [`docs/DEVICE_INSTALL.md`](docs/DEVICE_INSTALL.md) for the exact device defaults and retry workflow.

## Support and contributions

Report Feet issues in the [fork issue tracker](https://github.com/christophersutton/OutRunFork/issues), or contact support@wavelength.computer. There is no public Feet beta invitation yet. See [CONTRIBUTING.md](CONTRIBUTING.md) for workspace setup.

Translations were inherited from OutRun. Please submit Feet corrections to this repository; the upstream translation project is independent of this fork. Upstream attribution remains in [NOTICE.md](NOTICE.md).

Privacy and use information are available in the app, including offline copies. Before distributing a build, verify the public policy endpoints and publish the matching source revision.

## License

Move: Feet is published under the GNU General Public License, version 3 or later (GPL-3.0-or-later) — the same license as the original OutRun. See [`NOTICE.md`](NOTICE.md) for the statement of modifications.

    Move: Feet — a fork of OutRun
    Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>   (original OutRun)
    Copyright (C) 2026 Chris Sutton / Wavelength                 (Move: Feet modifications)

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
