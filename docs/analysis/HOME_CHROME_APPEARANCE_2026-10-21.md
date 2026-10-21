# Home navigation appearance handoff

Base: `7b3373f`, including installed-source `42c68ab`. Implementation is on
`agent/feet-theme-1021`; no branch switch, publishing, or installation performed.
Two `gpt-6.1-sol` agents independently audited colors/assets and navigation chrome.

## Findings and changes

- Home's top navigation bar belongs to `WorkoutTimelineView`. Its sort button
  inherited the root orange tint. The light accent `(1, 0.573, 0)` has **2.24:1**
  contrast against white; this establishes a palette contrast problem, not the
  exact rendered contrast of native glass. The button now locally uses
  `Color.orPrimary` (dynamic black/white). The rest of the app keeps its accent.
- The iOS 26+ `MainTabView` loads Timeline and Settings images by asset name,
  bypassing the legacy UIImage helpers that explicitly request template rendering.
  Those two assets now declare template intent. Apple's [asset format reference](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/ImageSetType.html)
  documents original rendering as the metadata default for these names. This
  removes dependence on a native tab implementation overriding that default;
  it does **not** prove the old icons caused the reported phone symptom.
- No home-path forced color scheme, global navigation/tab appearance override,
  or frozen `resolvedColor`/`cgColor` was found. Static named UIColors remain
  dynamic; the SwiftUI bridge preserves them. No theme preference was added.
- Native iOS 26 tab structure/search-role action and system navigation surfaces
  remain in place. Legacy tab styling, recording, Health, storage, and existing
  tests are unchanged. No speculative toolbar background/color-scheme override.

## Verification here

- `git diff --check` and `plutil -lint MoveFeet.xcodeproj/project.pbxproj`: passed.
- Python metadata inspection: both native tab assets declare template intent,
  their referenced images exist, and all six shared color catalogs parse.
- Compared all 28 existing test/support files byte-for-byte with base: unchanged;
  all **138 existing test methods retained**.
- Added three `HomeChromeAppearanceTests` methods to the native UnitTests target:
  direct asset loading produces template images; the same UIColor instances
  maintain readable light/dark/light contrast; the SwiftUI primary bridge follows
  its environment. These test resources, not the rendered toolbar hierarchy.
- Independent diff review found no blocking issues. **No native build, compiler,
  test execution, simulator/device access, SSH, private app data, Nidra, or external
  worker was used.** Native tests are pending, not reported as passing.

## Main-session runtime checks

1. Build from the main session's workspace after checking XcodeBuildMCP defaults;
   run `HomeChromeAppearanceTests` and the existing native suites as appropriate.
2. On iOS 26.2 simulator and the reported iOS 27 phone, compare cold light and dark
   launches with populated and empty/filtered-empty home content. Check the sort
   label at scroll top and after scrolling beneath the bar.
3. While running, switch system appearance light → dark → light. Switch Timeline,
   Stats, and Settings; open/dismiss sort and a workout detail; recheck toolbar and
   selected/unselected tab icon contrast. Confirm sort still opens and applies.
4. Confirm the native plus action starts recording without changing tab selection.
   The recording flow was not changed by this patch.

The phone symptom and any iOS 27-specific glass/backdrop difference remain
unreproduced here. Existing integer-string neutral color components were left
unchanged because their compiled interpretation was not established; the native
UIColor contrast test will check the actual compiled home palette. If runtime
shows a wrong toolbar surface, capture top/scrolled and live-transition evidence
before introducing a scoped surface fix.
