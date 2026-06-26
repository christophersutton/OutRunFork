# Move: Feet — Fork Audit (OutRun → Move: Feet)

> Inventory of every OutRun-brand surface in the codebase, what must change vs. what must be
> **preserved**, the data-loss/legal hazards, and the prioritized action list. Compiled 2026-06-26
> from four parallel audits (legal · build/assets · code identifiers · localized strings).
> Companion docs: `MIGRATION_HANDOFF.md` (the SwiftUI rewrite — done) and `AXIOM_AUDIT_FINDINGS.md`
> (code quality). **This** doc is the rebrand/fork audit.

## TL;DR

- **Base app:** OutRun by Tim Fraedrich, **GPLv3-or-later**, App Store id `1477511092`, bundle `de.tadris.OutRun`.
- **Already done (commit `81f466f`):** display name → "Move: Feet", app bundle id → `com.wcc.movefeet`
  (+ `.UnitTests`), team `W67CF9C739`, dropped unused clinical HealthKit entitlement, one-command device install.
- **Already done (attribution):** README "Wavelength Port Notice"; in-app Settings rows (fork source, original
  source, GPLv3, "© 2020 Tim Fraedrich" footer); GPL headers preserved across ~128 Swift files.
- **The single most important open question is legal, not technical:** can a *third-party* GPLv3 fork ship on
  the App Store? (GPLv3 ⇄ App Store ToS conflict — the VLC precedent — plus Guideline 4.1/4.3 copycat risk.)
- **The only hard *technical* ship-blocker** for a public release is the **app icon** (still OutRun's real icon).
- **Several brand strings must NOT be renamed** — they bind to existing user data/backups (data-loss hazards).

---

## 1. Legal & licensing (the foundation)

| Fact | Detail |
|---|---|
| License | **GPL-3.0-or-later** — every file header carries "…either version 3 …or (at your option) any later version". `LICENSE` is verbatim GPLv3. |
| Copyright line | `Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>` (in ~166 files). |
| Upstream | repo `github.com/timfraedrich/OutRun`; App Store id `1477511092`; contacts `timfraedrich@icloud.com`, `outrun@tadris.de`. |
| CLA? | **None.** CONTRIBUTING/CODE_OF_CONDUCT impose no copyright assignment — only "keep the GPL header on every file". |

### ⚠️ Legal issue #1 — ROADMAP says "AGPL"; that is wrong
`ROADMAP.md` claims the port "must stay AGPL-licensed." The code is **GPLv3-or-later, not AGPL.** You cannot
unilaterally relicense someone else's GPLv3 work as AGPL — only the copyright holder can. The fork **must remain
GPLv3-or-later.** (GPLv3 §13 is a one-way *interop* clause for *combining* with AGPL code; it does not convert
this code or impose AGPL's network-use disclosure trigger.) **Action: fix the ROADMAP wording.**

### ⚠️ Legal issue #2 — GPLv3 on the App Store (the key decision)
GPLv3's "no additional restrictions" (§10) + anti-DRM/anti-Tivoization (§3/§6) conflict with Apple's App Store
Terms (the documented **2011 VLC removal**). The asymmetry that matters: **Tim Fraedrich can ship his own GPLv3
app** (he's the licensor); **a third-party forker is a licensee and generally cannot** distribute the GPLv3 work
on the App Store without the copyright holder's explicit permission / an App-Store distribution exception (or a
dual-license grant). **Recommended path: contact Tim Fraedrich for written permission** — legally safest *and*
the respectful move.

### ⚠️ Legal issue #3 — App Store copycat/duplicate review (Guideline 4.1 / 4.3)
A near-identical app to one already on the Store (OutRun), submitted from a *different* developer account, is a
classic 4.1 (Copycats) / 4.3 (Spam/Duplicate) rejection trigger. Mitigations: the rebrand + a genuinely new
icon + meaningful differentiation — and, again, the original author's documented blessing.

### GPLv3 obligations checklist for the fork
- [ ] Preserve all GPL headers + the `Tim Fraedrich` copyright in every file (don't strip on rename).
- [ ] Add a **separate** Move: Feet/Wavelength copyright line for our changes (don't replace his).
- [ ] Mark modified files / state significant changes with a date (GPLv3 §5a).
- [ ] License the whole derivative under **GPLv3-or-later**; include `LICENSE` verbatim.
- [ ] Provide complete corresponding source to every binary recipient, under GPLv3 (public repo + written offer).
- [ ] Add **no additional restrictions** (§7/§10) — the crux of the App Store conflict.
- [ ] Fix `ROADMAP.md` (AGPL → GPLv3-or-later).

---

## 2. Already done (don't redo)

- **Build identity** (`81f466f`): `CFBundleDisplayName = Move: Feet`, app bundle `com.wcc.movefeet`,
  tests `com.wcc.movefeet.UnitTests`, team `W67CF9C739`, entitlements cleaned (only `com.apple.developer.healthkit`).
- **Attribution:** README port notice; Settings rows → fork repo (`github.com/christophersutton/OutRunFork`),
  original repo (`github.com/timfraedrich/OutRun`), `License: GPLv3`, footer "© 2020 Tim Fraedrich…".
- **GPL headers preserved** across the tree.

---

## 3. Branding inventory — must / should change

### 3a. App identity / build config
| Item | Current | Status | Action |
|---|---|---|---|
| CFBundleDisplayName | `Move: Feet` | ✅ done | — |
| CFBundleIdentifier | `com.wcc.movefeet` | ✅ done | — |
| CFBundleName / PRODUCT_NAME | resolves to `OutRun` (via `$(TARGET_NAME)`) | ⬜ cosmetic | optional: set explicit name, or rename target (see §6) |
| Backup UTI description | `de.tadris.orbup` / desc **"OutRun Backup"** | ⬜ todo | relabel **description** → "Move: Feet Backup"; **keep id + `.orbup`** (see §4) |
| Usage-description strings | generic "This app…" | ✅ clean | none |
| App Groups / associated domains | none | ✅ clean | none |

### 3b. Visual assets (`OutRun/Support Files/Assets.xcassets`)
| Item | Current | Action |
|---|---|---|
| **AppIcon.appiconset** | OutRun's **real shipped icon** (full size set + 212 KB master) | 🔴 **HARD MUST-REPLACE before any public release** (trademark). Keep filenames to avoid editing `Contents.json`. |
| `runningGlyph.imageset` | OutRun logo glyph (also the launch screen image) | 🟠 replace with Move: Feet artwork (launch screen updates automatically) |
| color sets (orange `accentColor`, etc.) | OutRun palette | ⬜ optional retheme |
| generic glyphs (play/pause/tabbar/etc.) | generic | keep |

### 3c. User-facing localized strings (`OutRun/Support Files/**/*.strings`)
**Live today (shown to users):**
| Key | Value | Notes |
|---|---|---|
| `OutRun` | `OutRun` | the on-screen app name (onboarding header, `OnboardingView.swift:124`). → "Move: Feet" |
| `WorkoutShareAlert.OutRunBackup` | `OutRun Backup` | share-sheet export title |
| `Settings.DataPreferences.Message` | "Backups in OutRun … '.orbup' file …" | settings backup explainer |
| `EditWorkoutController.AlterWorkout.AppleHealth.Error` | "…not added to Apple Health by OutRun…" | live HK error |
| `Settings.OriginalSourceCode` | `Original OutRun Source` | attribution row label (intentional — keep "OutRun" as the *original's* name) |
| `CFBundleDisplayName` (en-GB InfoPlist) | `Out-Run` | UK home-screen/App Store name (legacy trademark workaround) |

**Translation drift (Base/English clean, only the translation says "OutRun") — easy to miss:**
- `Settings.AppleHealthPreferences.Message` — **sv** only.
- `Setup.Permission.Location.Restricted.Message` — **cs** only.

**Dead keys (in bundle, not referenced by the SwiftUI app — low priority):** `Settings.Email.Error`,
`AppleHealth.Remove.Error`, `HKImport.Alert.Message`, `HKImport.ImportAll.Alert.Message`, `Changelog_1.3`.

**Changelog history:** `Changelog_1.2.2` recounts the UK trademark complaint + `outrun@tadris.de` (only shown on
update to that version). Decide whether to keep historical changelog entries verbatim or reset the changelog.

### 3d. Functional URLs / contacts (Swift literals)
| Literal | File | Action |
|---|---|---|
| `https://outrun.tadris.de/policies/` | `PolicyManager.swift:25` | 🟠 **functional** — drives in-app Privacy/Terms loading. **Repoint to a Move:Feet host or those screens break.** |
| `mailto:outrun@tadris.de` + displayed `outrun@tadris.de` | `SettingsView.swift:442,446` | repoint support email |
| GPX creator `"OutRun"` / "created by OutRun" | `ExportManager.swift:195,177` | cosmetic — exported file metadata |
| support email `support@tadris.de` (in a dead LS key) | `Settings.Email.Error` | n/a (dead) |

### 3e. Code symbols (cosmetic — internal, safe to rename)
`OutRunApp` (`@main`), `outRunBackgroundDeliveryQueue` + label `"outrun.background.delivery"`,
`outRunDidResetData` notification (+ raw `"OutRunDidResetData"`), HealthKit queue labels
`"com.tifraedrich.OutRun.*"`, the GB `"OutRun"→"Out-Run"` rewrite in `LS.swift:44`. All in-process only.

---

## 4. 🚫 DO NOT CHANGE — data-loss & legal-preserve

**Renaming these orphans/corrupts existing user data or violates the license:**
| Item | File | Why |
|---|---|---|
| Core Data model ids `OutRunV1`…`OutRunV4`, `OutRunV3to4` (the `identifier` **strings**) | `Models/Data/DataModels/Versions/*.swift` | bind to the migration chain; rename = broken migration of existing stores. (The Swift *enum type names* are safe to rename; the **string constants** are not.) |
| SQLite store filename `"OutRun.sqlite"` | `DataManager.swift:61` | rename = every existing user's DB is orphaned (fresh empty store). |
| `.orbup` extension | `BackupManager.swift:47` | existing user backups carry it; changing breaks import. |
| Backup UTI `de.tadris.orbup` | `SettingsView.swift:41` + Info.plist | system file association + previously exported backups. Relabel description only. |
| GPL headers + `Tim Fraedrich` copyright | ~128/166 files | **legal** — must be preserved (GPLv3 §4/§5). |

---

## 5. Prioritized action checklist

**P0 — legal gate (decide before building anything for distribution)**
- [ ] Decide distribution intent (personal device / public App Store / open-source repo).
- [ ] If App Store: resolve GPLv3⇄App Store — **contact Tim Fraedrich for written permission/exception.**
- [ ] Fix `ROADMAP.md` AGPL → GPLv3-or-later.

**P0 — ship-blockers for ANY public release**
- [ ] Replace the **app icon** (and `runningGlyph`).
- [ ] Repoint `outrun.tadris.de/policies/` (Privacy/Terms) + support email to Move:Feet-controlled endpoints.
- [ ] Add modified-file notices (GPLv3 §5a) + a Move:Feet copyright line; publish GPLv3 source.

**P1 — user-facing brand (live strings)**
- [ ] `OutRun` key → "Move: Feet"; remove the en-GB `Out-Run` + the `LS.swift` GB rewrite.
- [ ] Rebrand backup-feature copy (`WorkoutShareAlert.OutRunBackup`, `Settings.DataPreferences.Message`) — text only.
- [ ] Fix the live HK error string; fix sv/cs translation drift.

**P2 — cosmetic code/metadata**
- [ ] GPX creator string; internal symbols/queue labels/notification name; dead-key cleanup; changelog decision.

**P3 — optional internal hygiene (invasive, defer)**
- [ ] Rename on-disk `OutRun.xcodeproj` / `.xcworkspace` / `OutRun/` dir / target / scheme / entitlements file /
      branded source files. One atomic commit + `pod install` after. **Not required** — identity is already correct.

---

## 6. Open decisions (the grill feeds these)
1. **Distribution intent** — personal device vs. public App Store vs. open-source release? (gates everything).
2. **GPLv3/App Store** — contact author for permission, ship outside the App Store, or stay personal-use?
3. **Author relationship** — proactively reach out (recommended) and how (permission + courtesy heads-up).
4. **Rename scope** — user-facing + icon only (recommended) vs. also internal symbols/project/dirs.
5. **`.orbup` format** — keep id + relabel (recommended, preserves backup compat) vs. full rebrand + migration.
6. **Policy/support hosting** — where Move:Feet hosts Privacy/Terms + support, before public release.
7. **Source publication** — public GPLv3 repo (currently `christophersutton/OutRunFork`) + written offer.

---

## 7. Decisions locked (2026-06-26 grill)

1. **Distribution:** Public **App Store** release.
2. **Legal posture — hybrid.** Email Tim Fraedrich for a **GPLv3 §7 App Store distribution exception**;
   timebox ~3–4 weeks; **differentiate** the app (new icon/name/features kills the 4.1/4.3 copycat risk);
   if no reply, **proceed as a documented, risk-accepted decision** (abandonware → low enforcement risk).
   The §7 exception, if granted, makes the fork fully clean. ROADMAP "AGPL" error → fixed to GPLv3-or-later.
3. **Rebrand scope — full sweep now** (commit zero = lowest churn), with **carve-outs**:
   - Preserve GPL headers + `Tim Fraedrich` copyright (legal).
   - Keep `.orbup` import + the Core Data versioning module + `OutRun.sqlite` filename + `OutRunVx`
     identifier *strings* (invisible plumbing; renaming buys nothing, risks data/migration breakage).
   - **Sequence:** (a) content renames (strings/symbols/URLs/GPX creator) → 1 commit, build+run green;
     (b) structural rename (`.xcodeproj`/`.xcworkspace`/`OutRun/` dir/target/scheme/entitlements file) →
     separate atomic commit → `pod install` → build+run. Never mix the two.
   - **Internal name token: `MoveFeet`** (display "Move: Feet", bundle `com.wcc.movefeet`).
4. **Backup format:** keep `.orbup` **both** import + export (preserves the OutRun→Move: Feet data bridge);
   only relabel the user-facing "OutRun Backup" → "Move: Feet Backup".
5. **Icon / identity:** distinct **placeholder now** (so no build carries OutRun's trademarked mark),
   designed mark before public launch. Accent retheme optional.
6. **Policy / support hosting:** **Wavelength-controlled domain** — repoint `PolicyManager` (Privacy/Terms),
   the support email, and the App Store Connect privacy-policy URL there.

### Also folded into the sweep
- Remove the legacy UK trademark workaround: en-GB `CFBundleDisplayName = "Out-Run"` + the
  `LS.swift` `"OutRun"→"Out-Run"` runtime rewrite.
- Fix the sv/cs translation drift; opportunistically delete the dead LS keys.
- GPLv3 §5a: add a top-level modification notice (`NOTICE`/`CHANGES`) + a Move: Feet/Wavelength copyright
  line; add a "Modified by … (2026)" line to files as they're substantively changed.
- Make the source repo public (GPLv3 §6) and rename to match the brand; the in-app Settings already links it.

### Open / owner actions
- [ ] Send the Tim Fraedrich email (draft ready).
- [ ] Provide the Wavelength policy-host domain (for `PolicyManager` + ASC).
- [ ] Provide / approve the final app icon (placeholder can be generated now).
