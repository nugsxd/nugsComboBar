# nugsComboBar

Your class resource as a row of pips you can put anywhere.

Combo points, holy power, chi, soul shards, arcane charges, runes and essence —
plus the resources 12.0 moved off the power system entirely — drawn as configurable
pips on a single draggable anchor.

Retail only (Interface 120007). Slash command: **`/ncb`**.

## What it draws

| Class | Resource |
|---|---|
| Rogue, Feral Druid (cat form) | Combo Points, including Supercharged points |
| Paladin | Holy Power |
| Windwalker Monk | Chi |
| Warlock | Soul Shards — Destruction shows the shard being built as a part-filled pip |
| Arcane Mage | Arcane Charges |
| Death Knight | Runes, with a recharge sweep on each spent one |
| Evoker | Essence |
| Frost Mage | Icicles |
| Enhancement Shaman | Maelstrom Weapon |
| Survival Hunter | Tip of the Spear |
| Vengeance Demon Hunter | Soul Fragments |
| Devourer Demon Hunter | Souls — Dark Heart stacks, switching to Silence the Whispers during Void Metamorphosis |
| Brewmaster Monk | Stagger, as its own bar under the pips |

## Options

`/ncb` opens the settings window. Four tabs:

- **General** — master switch, position, scale, when to show the pips, minimap button.
- **Appearance** — pip shape, size, spacing, fill order, texture, borders, empty-pip
  styling, motion, what happens at maximum, and the optional number readout.
- **Colours** — a colour per resource (account-wide, so the Chi colour you set on a
  Paladin is waiting on your Monk), plus whether Blizzard's own version of each
  resource is hidden.
- **Extras** — Stagger, rune sweeps, and the combo point cap, filtered to whatever
  the character you are on actually has.

Everything applies live. The pips on screen are the preview.

### At maximum

Capping the resource gets two independent tells, both on the Appearance tab with
their colours on the Colours tab:

- **Glow every pip** — the row lights up and haloes, optionally pulsing.
- **Also recolour the pips** — repaints the filled pips.

Either, both or neither.

## Commands

```
/ncb             open the options window
/ncb unlock      show a grab handle and drag the row into place
/ncb lock        put it back
/ncb test        cycle the pips so you can judge the look
/ncb on | off    master switch
/ncb reset       back to the shipped look and position
/ncb diag        report what the addon can see for your spec
/ncb minimap     show or hide the minimap button
```

## Notes on 12.0

Two things about this patch shape the addon, and `/ncb diag` will tell you which
one you are looking at.

**A class resource is no longer just a power type.** Maelstrom Weapon, Icicles and
Tip of the Spear are buff stacks now, and Vengeance's Soul Fragments are a cast
count. They are drawn here exactly like the rest.

**Some resource counts arrive as secret values** — the game hands them over on the
understanding that you show them without reading them. Pip *i* is a status bar
ranged `(i-1, i)` and every pip is fed the same raw number, so the widget does the
comparison and no Lua code ever touches the value. Everything draws correctly
either way; the only thing a secret value costs is the pop animation, which needs
to notice that the count went up.

## Third-party media

Bar textures and fonts from **LibSharedMedia-3.0** are picked up automatically if
another addon has loaded it. Nothing here depends on it.

## Checks

Every push runs static analysis over the Lua in this repo, and the same checks run
locally before a release. To run them yourself:

```
npm install
npm test
```

Each check exists because of a bug that got as far as a build, and each script says
which one at the top of the file:

| | |
|---|---|
| `check.js` | every file parses |
| `fwdref.js` | a name used above the `local` that declares it - which silently reads a nil global |
| `selfref.js` | `local x = f(function() ... x ... end)`, where the closure captures nil rather than `x` |
| `wowcheck.js` | taint, secret values, and the other WoW-specific ways Lua that looks fine still breaks |
| `globalwrite.js` | assignments that never declared a local - advisory, since SavedVariables have to be globals |

Two more run before release but are not in this repo, because they need a copy of
Ketho's WoW API annotations: a check that no call has been moved or removed in the
current patch, and a full `lua-language-server` pass.

## Licence

Copyright (c) 2026 nugs. All Rights Reserved. See `LICENSE`.
