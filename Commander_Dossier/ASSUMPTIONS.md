# Commander_Dossier — assumptions to verify in game

Everything here passes the headless harnesses, which prove the logic and
nothing about the live client. Numbered so a test session can report against
them. A1–A4 carry the whole module; the rest degrade gracefully.

## A1 — `GetPlayerInfoByGUID` exists and returns the documented tuple

**Load bearing.** Class, race, name and realm for a player GUID with no unit
token. Without it the file still fills, but classes only appear for players
you happen to target, mouseover or focus, and spec inference (which needs a
class) mostly stops.

Test: fight one enemy you never target and confirm their record shows a class.
The call is pcall-guarded, so failure is silent — check for the class, not for
an error.

Return order assumed: `localizedClass, englishClass, localizedRace,
englishRace, sex, name, realm`.

## A2 — CLEU aura type is argument 15

`SPELL_AURA_APPLIED` carries `"BUFF"` or `"DEBUFF"` at position 15, after
spellId/spellName/spellSchool. The module ignores BUFF applications entirely,
so if this position is wrong the symptom is either no DR tracking at all or
buffs opening windows.

Test: `/cdossier` and watch a stun land — the board should show a STUN pip.
Then take a buff from an enemy paladin and confirm no pip appears.

## A3 — `SPELL_AURA_BROKEN` fires instead of `SPELL_AURA_REMOVED`

Documented in the suite's API notes as reasoned-but-unverified. If a broken
fear emitted `REMOVED` as well, nothing breaks (the fade is idempotent). If it
emits *neither*, the window would hang "up" until the `MAX_ACTIVE` guard.

Test: fear something and break it with a damage-over-time. The pip should stop
saying "up" and start counting down within a second.

## A4 — The reset window is 15–20 seconds and 20 is the safe read

TBC's reset is dynamic. The module pins 20. If the true window is nearer 15,
the board says "still diminished" for up to five seconds after it has actually
reset — you cast expecting half and get full, which is the harmless direction.

Test: stun something, let it fade, and count. A stun landing full at 16s means
the constant could be tightened.

## A5 — Engineering bombs share the incapacitate category

Included from the sourced list. Arena-relevant in TBC and easy to check.

Test: bomb somebody, then Polymorph them and see whether it lands halved.

## A6 — Disarm and Riposte share a category

Two spell ids are listed for Riposte in the source with a note that only one
is right; both are kept, which is harmless (an unused id never fires).

## A7 — Unstable Affliction's silence diminishes with itself

The only silence in TBC with any DR at all. Worth confirming because it is the
one entry that contradicts the "silences do not diminish" rule the rest of the
module is built on.

## A8 — Combat-log range covers the players whose windows matter

In arena this is certain. In a battleground or the world, an enemy at the far
end of the field may apply crowd control the log never reports, so their
window silently stays at full. Coverage is stated in the options rather than
worked around.

Test: in a battleground, watch whether rows appear for fights you are not
standing in.

## A9 — `PARTY_KILL` names you as the source only for your own killing blows

Used for the kill count. If it also fires for party members, kills would be
over-credited to the player.

Test: let a teammate finish someone and check whether your kill count moved.

## A10 — Talent names match the ability and proc names they grant

The basis of spec inference. Verified structurally against the suite's own
talent data, but not that the *client* emits the same string in the combat
log. Localised clients should be fine (both sides come from the client), but
this has not been checked.

Test: hit a rogue with Shadowstep and confirm their record reads Subtlety.
Known limits by design: talents that grant nothing castable are invisible, so
a deep passive build takes longer to identify than a build with a signature
button.

## A11 — `bit.band` is available to addons on this client

Used for combat-log flags. If absent, every unit classifies as friendly and
non-player, so the board would stay empty and the file would never fill. This
would be loud and immediate.

## A12 — `StaticPopup_Show` and a custom `StaticPopupDialogs` entry work

Only used for the wipe confirmation. Failure means the wipe button does
nothing, which is the safe failure.

## A13 — The immunity klaxon is not annoying in practice

A judgement call, not an API fact. `RAID_WARNING` fires once per category per
target with a three-second floor. If a chaotic battleground makes it constant,
the fix is to gate it on the current target rather than on any tracked unit.
