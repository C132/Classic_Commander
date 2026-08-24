# Commander Spoils — assumptions

Things this module believes that are not proven in `FINDINGS.md`. Each one is
written to fail safe, and each says how to check it.

1. **Trade-goods subclass ids** (`CommanderSpoilsEngine.lua`, `TRADE_BUCKET`).
   This client ships no `Enum.ItemTradegoodsSubclass`, so `7/5 = Cloth`,
   `7/6 = Leather`, `7/7 = Metal & Stone`, `7/9 = Herb`, `7/10 = Elemental`,
   `7/12 = Enchanting` are asserted from era knowledge, not from a shipped
   enum. **Check:** `/cspoils size` prints the client's own
   `C_Item.GetItemSubClassInfo(7, i)` names for `i = 0..15`. One login settles it.
   Fails safe: a wrong id lands the bucket in `TRADEGOOD`, never in gear.

2. **`GetLootSourceInfo` returns a GUID string on this client.** Verified
   present in the global API dump, but FrameXML exercises no code path through
   it. The probe is `pcall`ed, only a positive result is memoized, and the
   `UnitName("target")` heuristic remains as the fallback.

3. **`SetGradient(orientation, colorObject, colorObject)`** for the screen-edge
   glow. This signature is 10.0-era and is not in FINDINGS. It is `pcall`ed and
   `CreateColor` is probed; a flat edge is an acceptable degradation, an aborted
   login handler is not.

4. **Motes and Primals cannot be separated** by subclass (both `7/10`). No
   heuristic is attempted; the bucket reads "Elemental" and item rows carry the
   names. If a Primal counter is ever wanted specifically it is 16 hardcoded
   item ids and nothing else.

5. **`ChatFrameUtil.*` exists.** The deprecated `ChatFrame_*` globals are kept
   as a fallback, but if both are absent the chat filters silently do not
   install — which leaves Blizzard's chat lines showing, i.e. it fails toward
   the safe side.

6. **Positional `%1$s` GlobalStrings are not handled.** `ToPattern` recognises
   them so they do not corrupt the pattern, but the capture order is textual,
   so a locale that reorders `LOOT_ITEM` would map "who" and "item" the wrong
   way round. enUS is unaffected. See BACKLOG.

7. **Container APIs are populated by `PLAYER_LOGIN`.** Not relied on: the first
   bag scan is only accepted as a baseline when it actually read slots, so a
   late-populating client costs one extra settle rather than recording the
   whole inventory as loot.

8. **`UIParent:IsShown()` distinguishes a real close from an ambient hide.**
   The frame's `OnHide` ends the loot session, and the guard against Alt-Z,
   cinematics and `MovieFrame` is that they hide `UIParent` rather than us.
   Reasoned from client behaviour; the headless mock does not propagate
   ancestor hides, so it is untested. Worst case is a loot session closing when
   the UI is hidden — annoying, not destructive.

9. **`Data.drops` / `Data.kills` are worth persisting** before anything renders
   them. They are capped and pruned, and the per-source drop-rate view that
   consumes them is in BACKLOG. If that view is cut, delete the tables.
