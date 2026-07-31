# Changelog
## 0.4.3

- **Fixed: the settings window twitched the first time it was dragged.** It is
  anchored to the centre of the screen, and StartMoving has to convert that relative
  anchor into an absolute position before it can move anything - landing on a
  fractional pixel. That conversion now happens once, rounded, when the window first
  opens, so the first drag has nothing left to convert. It only ever showed up once
  per session, which is why moving the window made it stop.

## 0.4.2

- **Fixed: the Saved... button threw "attempt to call a nil value" and never opened.**
  The picker was placed near the top of the file but calls a scroll helper defined
  hundreds of lines below it, so the call bound to a nil global. Moved below the
  helper it depends on.
- The picker is now **Pick a saved profile...** sitting beside a shortened name box,
  rather than a fourth button crammed next to Save/Load/Delete.
- **Fixed: sliders jumped when clicked.** The value box commits when it loses focus,
  so clicking straight onto a slider re-applied whatever was still in the box over
  the value you had just clicked. It now ignores a commit that matches the live
  value.

## 0.4.1

- A **Saved...** button next to the profile buttons lists what you have saved, so a
  name never has to be typed from memory.
- **Fixed: a pop-up list came up empty the first time and only filled in on the
  second click.** Its width was read from the scroll frame, which is sized by
  anchors and so still measures zero on the frame it was created in - every row was
  built zero-wide. The width now comes from the pop-up's own size, which is known
  immediately.
- Pop-up lists are lifted off the window's near-black background and edged in
  storm-blue, so a floating list reads as sitting on top of the panel rather than
  disappearing into it.

## 0.4.0

- **Profiles.** Save the current settings under a name, then load them on any other
  character. Profiles live in the account-wide saved variables, so one made on your
  main is visible from every alt - no strings to copy, no export and re-import.
- Nothing auto-saves and nothing is bound to a character. A change you make simply
  stays until you Save it into a profile or Load a different one over it.
- **Every slider value can be typed.** The number beside each slider is now a box:
  drag to find a value, type to repeat one you already know. Both drive the same
  setting.
- The boxes commit on Enter or when you click away, put the live value back if you
  type something that is not a number rather than zeroing it, and clamp to the
  slider's own range - so a stray extra digit cannot push a setting somewhere the
  slider could never reach.
- The profile section now says which profile is **loaded**, and marks it
  |cffd8a13f(modified)|r the moment you change anything - because after that you are no
  longer on it, and a label that just echoed the last name you clicked would be wrong
  within seconds. Save writes your changes back; Load throws them away.

## 0.3.7

- CurseForge project id (**1630102**) recorded in the .toc, so addon managers can
  tie an installed copy back to the project and offer updates.
- Dropped the placeholder note that stood in for it.

## 0.3.6

- **Fixed: every pip popped once when you switched specialization.** The rebuild was
  supposed to forget the previous resource count so the new spec's first update draws
  the row rather than animating into it. The line that did the forgetting sat above
  the `local` it was meant to be clearing, so Lua quietly gave it a global of the same
  name and the real value survived the rebuild untouched. The reset now takes effect,
  and the row appears without the flash.

## 0.3.5

- A single line in the options window - "Part of the nugs suite" - shown only when
  nugsSuite is not installed. A note, not a warning, and not a dependency: this
  addon works exactly the same on its own, and the suite is only worth having once
  you run more than one of them.

## 0.3.4

- The minimap button no longer shows a sliver of the world between the icon and the
  tracking border. The border's hole is slightly wider than the icon was, leaving a
  thin see-through ring; there is now a dark disc behind the icon, and the icon
  itself went from 19 to 21 pixels.

## 0.3.3

- `fullColoursRepaired`, the one-shot colour migration flag, is no longer carried
  in nugsSuite profile exports. It is a migration marker rather than a setting, and
  it showed up in every export as a changed value.

## 0.3.2

- **Fixed: the at-maximum glow and recolour were invisible, not absent.** They
  shipped gold — within a few hundredths of Holy Power's own gold — so on a Paladin
  both worked exactly as designed and neither could be seen. The defaults are now
  near-white, and existing settings still carrying the old shipped gold are repaired
  once on load. A colour you chose yourself is never touched.
- Capping is now detected by plain comparison whenever the resource is a normal
  number, and the layers are shown or hidden outright. The 0.001-wide StatusBar
  range is kept only for secret values, where comparing is not permitted — it was
  never the right tool for the common case.
- **New `/ncombo probe`** reports the live state of the pip widgets: shown flags,
  fill widths, vertex colours, the glow texture, and a warning when the resource
  colour and the at-max colour are too close to tell apart.

## 0.3.1

- Registers with **nugsSuite**, the new hub addon: it can now list this addon, open
  this window, fold this minimap button into its own, and carry these settings to
  another character as part of one profile string.
- The registration is a single entry written into a plain global table. nugsSuite
  does not have to be installed for it to be harmless, and does not have to load
  first for it to be found - so nothing here changes if you never install it.
- The defaults handed to the suite are rebuilt with the per-resource block filled
  in, the same way the saved variables are seeded. Without that, every resource
  colour would have read as changed and ridden along in every export.

## 0.3.0 — 2026-07-28

- **The pips now demo themselves while the options window is open.** Every colour
  and glow setting acts on a *filled* pip, and a resource sitting at zero out of
  combat has none — so the window shipped full of controls that visibly did nothing,
  which is indistinguishable from them being broken. The row now runs up and down
  its range while you configure, holding at full for a beat so the cap glow and
  recolour are actually visible. Toggle on the General tab.
- The demo no longer dims under the "when to show it" rules, and holds at the top
  rather than sweeping straight past it.
- Clearer wording on the empty-pip styles, plus a note that a dark empty colour at
  low fill opacity makes "filled, dimmed" and "outline only" look nearly identical —
  which is a settings combination, not a bug.

## 0.2.2 — 2026-07-28

- **Styling no longer fails silently.** `StylePip` was one flat function, so a
  single widget call that threw abandoned everything after it — the pips still drew
  at their old look, but colours, the glow and the layout never applied. That reads
  from the outside as "all the options are there and none of them do anything". It
  is now split into independently guarded phases (geometry, masks, paint, glow,
  range); a failure in one is caught, recorded, and cannot take the others down.
- The border is only drawn if the masks that cut it into a ring actually applied,
  so a mask failure can no longer leave a solid slab covering the pip.
- **`/ncombo diag` now reports the fault** rather than just the resource: how many
  pips were built and shown, whether the display is on screen at all, whether the
  mask pass succeeded, the current shape/border/empty settings, and any trapped
  error with its message.

## 0.2.1 — 2026-07-28

- **Fixed: "outline only" still drew a solid pip.** 0.2.0 added the inverted mask
  that cuts the hole but never gave it anchor points, and a MaskTexture with no
  points has no size and masks nothing — silently, with no error. The border stayed
  the solid shape it had always been.
- The border is now a tinted texture rather than `SetColorTexture`; a 1x1 solid
  colour source is far less predictable to mask than real texels.

## 0.2.0 — 2026-07-28

- **Glow at maximum.** The whole row lights up and haloes when the resource caps,
  in its own configurable colour, with an optional slow pulse. Independent of the
  existing recolour, so you can have either, both or neither. Driven by the widget
  the same way the pips are, so it works on a secret resource value.
- **Fixed: the number was drawn behind the pips.** It sat on the anchor frame, and a
  parent's font string can never come out in front of its child frames. It now lives
  on its own frame stacked above them.
- **Fixed: "dimmed" and "outline only" looked identical.** The border was drawn as a
  solid shape rather than a ring, so both styles rendered a filled blob — one with a
  25% overlay on it. Borders are now a true ring, cut with an inverted mask, at
  whatever thickness the border slider says.

## 0.1.0 — 2026-07-28

First build.

- Class resource drawn as a row of pips on one draggable anchor: combo points,
  holy power, chi, soul shards, arcane charges, runes and essence.
- Also covers the resources 12.0 moved off the power system — Maelstrom Weapon,
  Icicles and Tip of the Spear (buff stacks) and Vengeance's Soul Fragments
  (a cast count).
- Supercharged combo points are recoloured and lit.
- Destruction reads its shards in tenths, so the shard in progress part-fills a pip.
- Spent runes sweep as they recharge.
- Brewmaster's Stagger as a bar under the pips, green through red.
- Five pip shapes (rectangle, rounded, circle, diamond, hexagon), generated as BLP
  masks rather than borrowed from Blizzard's texture set.
- Options window in the suite skin: General, Appearance, Colours, Extras. Every
  control applies live.
- Blizzard's own resource frames hidden by default, per resource, deferred out of
  combat because those frames are protected.
- Minimap button, `/ncombo` commands, `/ncombo diag`.
