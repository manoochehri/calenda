# Landscape only (issue #78)

Calenda is a landscape game. Portrait is out of scope (owner decision, 2026-10-24).

- **Lock:** `default.project.json` sets `StarterGui.ScreenOrientation = LandscapeSensor` (both landscape
  directions); `Hud.new` also sets `PlayerGui.ScreenOrientation` at runtime.
- **Supported ratios** (`src/shared/ScreenLayout.luau`, tested in `tests/screenlayout.test.luau`):
  16:9, 4:3, 19.5:9, 21:9, at a 390 px tall reference phone.
- **Safe area:** every HUD `ScreenGui` uses `ScreenInsets = CoreUISafeInsets`, `IgnoreGuiInset = false`
  (`src/client/GuiLayout.luau`), so its 0..1 space is the safe area. Per the ScreenGui docs, `IgnoreGuiInset = false` keeps `CoreUISafeInsets` (clear of top bar and cutouts); `true` would switch it to `DeviceSafeInsets`; `None` applies no insets. Only decorative full-screen layers
  (hit flash, results dim, title backdrop) use `ScreenInsets = None` (with `IgnoreGuiInset = true`). Inset values (notch 47 px per
  side, home bar 21 px, top bar 44 px, 12 px corner margin) are estimates until checked on devices.
- **Rules the tests enforce:** HUD elements stay in the safe area and never overlap while shown together;
  text floor 14 px and the box is at least that tall and wide enough for its longest string; touch
  targets >= 44 px; primary buttons (`PRIMARY_BUTTON`: "¡Otra calenda!", "Jugar") sit in the lower
  right corner under the thumb.
- **Add a HUD element:** add it to `ScreenLayout.ELEMENTS`; the tests then cover it at every ratio.
- **Stacking:** `ScreenLayout.DISPLAY_ORDER` gives every GUI a unique `DisplayOrder` (tested); the hit flash and results dim are under the HUD text.

Issue #160 removes active-gameplay screen text entirely, including the counter, detail,
steering hint, section meter and section toast. `ScreenLayout` now reserves text only for
ending banners, results and title controls; safe-area, readability, touch and world-lane
checks remain. Actual phone-size Studio visuals are UNVERIFIED until engine validation.
