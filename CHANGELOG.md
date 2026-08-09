# Changelog

## 0.4.9

- **The bar can no longer be placed during combat**, which matches the rule that a pull
  locks it in the first place. Unlocking puts the drag box and a filled sample bar over
  the top of your actual resource, which is the worst possible moment for it. It is now
  refused with a line of chat rather than half-entered.
- **Ready for patch 12.1.** The .toc declares `120007, 120100`, so this is current
  on live and on the 12.1 PTR at once rather than being flagged out of date on one of
  them. Nothing here uses an API that 12.1 removes, and the unit calls that begin
  returning secret values in 12.1 are guarded - a release check now enforces both, so
  it stays true.

## 0.4.8

- **Fixed: "action blocked" errors during combat.** `SetPropagateKeyboardInput` - used
  so that Escape closes a dropdown or the placement bar rather than the window behind
  it - is protected during a fight. Calling it then raises ADDON_ACTION_BLOCKED naming
  this addon, and unlike a Lua error it cannot be caught: it taints the addon for the
  rest of the session. 8 call sites now skip themselves in combat.
- The worst of them was the key handler: it guarded the Escape branch but not the
  branch every *other* key took, so with a list open in combat any keypress would have
  thrown it - movement keys included.

## 0.4.7

- Internal hardening, no visible change. The scroll helper's fallback width guard could
  copy a zero width onto a list's content frame during the first layout pass, and once
  copied nothing would correct it - rows would draw but not be clickable. Every list here
  sets its own content width afterwards, so this was never reachable; the guard now waits
  for the scroll frame to have a real width, so it stays a safe backstop.

## 0.4.6

- **Devourer souls are now tracked.** It is the only resource here that changes
  shape mid-fight, so it needed three things nothing else did:
  - The stacks live on **Dark Heart**, except during **Void Metamorphosis**, when
    they move to **Silence the Whispers**. The aura is chosen before it is read.
  - The cap is not a constant — normally Dark Heart's own maximum stack count, and
    during Void Metamorphosis whatever Collapsing Star currently costs. Either can
    come back secret, so the last good answer is kept rather than collapsing to zero.
  - Because the cap moves, the pip count is re-resolved on value events rather than
    only on a spec change, and a redraw only happens when something actually changed.
- A cap of 10 or fewer draws one pip each; anything larger collapses to a single pip
  that fills like a bar, because thirty pips in a row is not a readable display.
- `/ncombo diag` reports the live cap and which of the two layouts is in use.

## 0.4.5

- **The settings window gets out of the way while you place the resource bar.** Unlocking
  hides it and puts up a small bar instead - Lock bar and Demo - and locking brings the
  window back exactly where it was. Placing things meant dragging boxes the window was
  usually sitting on top of, so it had to be shoved aside and dragged back every time.
- The bar can be dragged if it is in the way, and Escape locks rather than just
  dismissing it - hiding it while things were still unlocked would have left nothing on
  screen to end that state.
- `/ncb unlock` puts the bar up too. If the settings window was not open when you
  unlocked, locking does not conjure one.
- **Fixed: a dropdown could run off the bottom of a smaller screen.** Four of them
  dropped straight down from their button with no check that there was room below and
  no clamping, while the lists beside them already handled it. They now open upwards
  when there is no room, and are clamped as a backstop - clamping alone would slide a
  list up over the button that opened it, hiding the thing being changed.
- **The settings window closes when a fight starts, and the anchor locks.** Not because
  anything here would be blocked - none of these windows touch a secure frame, so
  nothing throws "action blocked" the way an addon driving action bars does. The
  reason is that both states put fake data on screen: with the window open, the pips demo themselves, and sample
  data during a real pull cannot be told apart from the real thing. Nothing reopens
  when combat drops.
- **The slash command is now `/ncb`**, taken over from nugsCastBars, which has moved
  to `/ncast`. `/nugscombobar` still works. `/ncombo` is gone - it was the odd one
  out in a family where everything else is an n and two or three letters.

## 0.4.4

- **The scroll bar can be grabbed and dragged.** It was drawn as a texture, and a
  texture cannot take mouse input at all - so it showed you where you were in a list
  and gave you no way to act on it, leaving the wheel as the only way down a long one.
  It is a real bar now: drag the thumb, or click the track to page toward the click.
  The wheel still works exactly as before.
- **Fixed: the font and bar-texture lists came up empty on the first click** and only
  filled in on the second. Their rows were sized from the scroll frame, which is
  positioned by anchors and so measures zero until a layout pass has run - every row
  was built zero-wide. The scroll helper now repairs a zero-width list itself rather
  than relying on each list to size itself correctly.
- **Lists close when you click away from them.** They stayed open until something was
  selected or the button was pressed again.
- **Fixed: a list could be cut off at the edge of the panel it opened from.** It was
  attached to whichever frame its button sat in, and when that was a scrolling pane the
  list was clipped by it - a scroll frame clips its children. Lists now hang off the
  screen itself, so they overhang the window instead of being cut in half.
- **Fixed: closing the window with Escape left an open list floating on screen.**
  Lists hang off the screen itself now rather than off the window, which is what stops
  a scrolling pane clipping them - and also cut the tie that used to take them down
  with it. A list now watches the control it was opened from and closes when that goes
  away, so it cannot outlive its window however the window was closed. Escape closes
  the list first and the window second, which is the order people expect.

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
