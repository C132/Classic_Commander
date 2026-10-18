# Commander Guide — assumptions

Things this module believes about the client that have NOT been verified in
the field as of 2026-09-28. Each says what breaks if it is wrong and how to
tell.

**A1. `C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap)` speaks
without the `textToSpeech` CVar.** The signature is the binary's own usage
string and `VoiceChatDocumentation.lua`; the belief is that the call works
with chat text-to-speech switched off in Blizzard's options, as it does on
retail for DBM and WeakAuras. If wrong: nothing is ever heard and `/cguide
test` prints nothing (pcall swallows the failure). Tell by: `/cguide test`
with the chat TTS toggle off, then on.

**A2. `ENCOUNTER_START` / `ENCOUNTER_END` fire on Anniversary raid bosses
with the `DungeonEncounter` ids 652–662.** The ids are the client's own
table; the firing is what Commander_Meters also left unverified. If wrong:
the creature-id fallback names the pull instead, a second or two later,
and the pull closes six seconds after leaving combat rather than on
`ENCOUNTER_END`. Tell by: the pull's `source` in `CommanderGuide_Debug().ctx`
reads `npc` instead of `encounter` on every boss.

**A3. Boss abilities appear in the combat log under the ids in the data.**
Names were matched on Wowhead, but a boss can cast a differently numbered
copy of the same-named spell (Aran's Flame Wreath is two ids, 29946 the
aura and 30004 the cast, and both are listed for that reason).
If wrong for a given line: that callout never fires. Tell by: a boss
mechanic that visibly happens with no line; compare the log's id to the
data's.

**A4. `UNIT_HEALTH` on `target` reaches a raid boss with real numbers.**
Health thresholds (Moroes 30 %, Prince 60/30 %, Attumen mount) read
`UnitHealth/UnitHealthMax` for whichever unit fired, which is only the
boss when someone has it targeted or as boss1. If wrong: threshold lines
are late or absent. Tell by: no "Phase two soon" on Prince with him
targeted at 60 %.

**A5. `VOICE_CHAT_TTS_PLAYBACK_FINISHED` fires when a line ends.** The
event is in the binary; the belief is it fires per utterance. If wrong:
the word-count timer (2.7 words a second at rate 0, plus a second) advances
the queue instead, so routine lines come a beat late. Tell by: two quick
callouts with a gap between them longer than the first line.

**A6. Friendly players carry `COMBATLOG_OBJECT_TYPE_PLAYER` and
`REACTION_FRIENDLY` in destination flags.** Standard since 2.4; the
harness asserts it with literal 0x400 and 0x10. If wrong: every "on a
player" line is silent, "on you" lines still work (GUID compare).

**A7. The Opera and Nightbane YELL fragments match the live text.**
"gentle night" (Julianne, phase three), "from the air" (Nightbane takeoff)
and "crush you" (Nightbane landing) are from memory of the scripts, not a
dump. If wrong: those three lines never fire; nothing else depends on
them. Tell by: the yell in chat without the line.

**A8. Opera acts are told apart by first sighting.** Dorothee 17535, the
Wolf 17521 and Julianne 17534 each open their act's lines when they first
appear in the log. If a different creature id opens an act (a stage hand),
the act's opening line is missing but every spell callout still works.

**A9. The Standard voice option id from `C_TTSSettings.GetVoiceOptionID`
is one of `C_VoiceChat.GetTtsVoices()`.** When it is not, the first voice
in the list is used; when the list is empty at login (voices arrive on
`VOICE_CHAT_TTS_VOICES_UPDATE`), voice 0 is passed. If wrong: the wrong
voice, never silence.

**A10. Questie's raid doors are where the instance portals are.** The
entrance table (`D.ENTRANCES`, DECISIONS D11) is Questie's dungeon
locations for the TBC raids, unverified on this client: Karazhan's two
points in Deadwind Pass, the Caverns of Time door in Tanaris for Hyjal,
the Coilfang Reservoir for Serpentshrine. If wrong: the arrow walks you to
a spot near, not on, the door, and Orders never says "Arrived" there.
Tell by: press Go to Entrance (Waypoint to Entrance before 1.2.0), walk the arrow in, and see where it
says Arrived against where the portal is.

**A11. `CommanderOrders.Entrance(raidMap)` answers with a zone position.**
The guide asks Orders' resolvers for the raid's own uiMap (350 for
Karazhan) before its table. A resolver that answers with the raid's
interior map rather than the zone outside would put the arrow inside the
instance; the guide only rejects answers that are not a 0..1 position on
a map. If wrong: the arrow reads "Other landmass" or "No position" for a
raid that is a short walk away. Tell by: `/dump
CommanderOrders.Entrance(350)` should name map 1430 (Deadwind Pass).
When that answer is one of the table's doors (the Quest Log's resolver
gives Questie's first, 46.7, 70.2), the other doors go along as
alternatives (D11). Tell by: with QuestLog and Questie loaded, stand by the
tower's south side (about 46.9, 76) and press Waypoint to Entrance: the
arrow should point at the 46.9, 74.7 door, not the northern one.

**A12. Orders' door for a raid is where the portal is (1.2.0, D12).** With
Commander Orders 3.1 the door is Orders' shipped table, not D.ENTRANCES:
`CommanderOrders.Entrance({ instance = 532 })` answers Karazhan's two
portals (46.6, 74.1 and the service door), Serpentshrine the Coilfang
Reservoir's mouth, Hyjal the Caverns of Time's. Read from the client's
AreaTrigger rows offline, never walked. If wrong: the arrow says Arrived a
few yards from the portal, or leads to the reservoir's mouth rather than
the pipe. Tell by: from Deadwind Pass south of the tower press Go to
Entrance (or `/cguide entrance`): one "Waypoint set: Karazhan entrance"
line from Commander Orders, the arrow on the nearer door, Arrived at the
portal. Shift-click the button in a group: the party sees "Karazhan
entrance - Deadwind Pass ... (/way #1430 ...)". Restart the client after
updating (no new Guide file, but Orders 3.1 and Commander_Events add
files).
