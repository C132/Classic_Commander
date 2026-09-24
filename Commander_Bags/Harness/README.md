# Commander_Bags harness

One luajit check. Run it before any change to the bag painter.

```bash
/opt/homebrew/bin/luajit bags_harness.lua   # 47 checks
```

It resolves the AddOns root from its own file location, so it works in a git
worktree as well as in the live AddOns directory, and exits non-zero if any
check fails.

## What it covers

The harness loads the real `CommanderSettingsUI.lua` and `CommanderEvents.lua`
alongside all three `Commander_Bags` files under a permissive WoW mock, builds
two container frames of fixtures, fires login, and then reads back what the
buttons would actually be *showing* — every texture records its vertex color,
anchors and shown state.

- **The ring.** Quality color, full alpha, the faint halo beside it, thickness,
  and the four category overrides (quest yellow, gray-junk red, consumable
  cyan, common left plain).
- **Surviving Blizzard.** The reason the ring is drawn instead of borrowed:
  calling `SetItemButtonQuality` on a painted slot — which is what
  `ContainerFrame_Update` does on every bag event — must leave the ring exactly
  as it was, and must put `IconBorder` away again on the way past. This is the
  regression that made the rarity color "fade out" in the first place.
- **Bind badges.** Bind-on-pickup reads closed and steel, an unbound
  bind-on-equip reads open and gold, a BoE that has already bound reads closed,
  and anything that never binds carries no padlock at all. A BoE binding *in
  place* has to flip without the itemID changing.
- **Settings reach the art.** Badge mode, thickness, halo and the master
  coloring toggle each repaint immediately, and turning coloring off hands the
  slot back to Blizzard's own border rather than leaving it blank.
- **Slot lifecycle.** Emptying, refilling, and an item the client has not
  cached yet (which must be left unmemoized so the refresh window comes back
  for it).
- **Cost.** A settled refresh burst may scan a tooltip only for bind-on-equip
  slots, and only once per burst — not once per slot per pass, which is what
  the module's CPU story was about before.

## Mock notes

Lessons already paid for, so the next run does not re-learn them:

- The scanning tooltip's `TextLeftN` font strings are **globals the addon reads
  by name**, so the mock's `SetBagItem` has to publish them into `_G` under the
  tooltip's own name.
- `C_Timer.NewTimer` has to return a cancellable handle: the refresh burst
  reschedules itself ten times and cancels the pending timer each time a new
  window opens.
- `GetContainerItemInfo` deliberately returns **no `isBound` field**. The
  addon prefers it when the client carries it; leaving it out is what keeps the
  tooltip fallback under test.
- `GetID` is auto-generated as a constant by the widget mock, so container
  frames and item buttons `rawset` their own — a bag is not always the frame
  with the matching number.
