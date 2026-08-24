# Commander Spoils — backlog

Deliberately not built. Each entry says why now is not the time.

## Worth building next

- **Per-source drop rates.** `Data.drops[creatureID][itemID]` and
  `Data.kills[creatureID]` are already collected off `GetLootSourceInfo`'s
  per-slot GUID and pruned together. What is missing is the view: "Fel Iron
  Ore — 2.4 per node over 61 nodes". This is the honest version of a drop-rate
  metric (D15) and the data cost is already paid.
- **Segment history.** `Data.segments` holds up to 200 closed run/farm
  summaries and nothing reads them. A "last ten runs" list on HAUL would use
  them as-is.
- **`EV.SEGMENT` has no subscriber.** Either wire a notification ("that run was
  worth 84g") or drop the event.
- **Positional GlobalString locales.** `ToPattern` collects each specifier's
  `%n$` index and discards it. Applying it as a permutation in `Match` would
  make deDE/frFR/ruRU correct; `Match` also caps at four captures, which
  `LOOT_ROLL_ROLLED_NEED` already saturates.
- **PARTY does not honour the scope.** `E.Party` is a login-lifetime
  accumulator with no time dimension and no reset on group change. Either key
  it to the run segment or dim its scope button the way BAGS does.

## Deliberately cut

- **Loot council, DKP/EPGP, MS/OS response collection, whispering candidates,
  session export.** A different addon, and most of it is unbuildable without
  the addon-message channel this suite deliberately lacks.
- **Auto-need at any quality.** There is no configuration of that feature which
  is not a griefing tool.
- **Any selling, sorting or merging action.** Commander_Logistics owns
  vendoring and Commander_Bags owns the sort engine; a second loop races their
  item locks. Spoils displays and hands off.
- **Bank and mail census.** Commander_Quartermaster owns the account-wide
  ledger, and bank contents are only readable while the bank is open, so a
  Spoils copy would be stale and look broken.
- **Profession detection.** TBC has no `GetProfessions()`; it is skill-line
  scanning for the payoff of a highlight colour, and the player already knows
  their professions. The settings switches are three clicks and always right.
- **Off-spec / "could they even use it" column in the roll history.** Derivable
  from armor type, and it will start guild drama. The log retains everything
  needed to add it later at zero cost if it is ever actually wanted.
- **A search box.** `ALL / MINE / NOTABLE` covers it. A text field in a HUD
  frame is a keyboard trap in combat.
- **Schema migration code for the ledger.** Version-stamped and wiped on
  mismatch. Migration code for a personal addon's telemetry buys a bug surface
  against data that is not precious enough to justify it.
