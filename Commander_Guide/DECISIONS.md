# Commander Guide — decisions

Not to be re-litigated without a reason that is not already here.

**D1. One page per SEAT, not per boss.** A raid guide that explains every
mechanic to everyone is what the wiki already is. This one is written as
"what do I, the healer, do", and the tank's and the damage seats are
separate pages the same boss will carry later. The healer's seat is the
first one written because it is the one that has to react on a timer:
Garrote, Sacrifice, Holy Fire, Enfeeble all have a person who is dying
right now and a healer who has to know it.

**D2. The guide is data, the reasoning is an engine, the client is a
translator.** `CommanderGuideData.lua` is a pure table (raids, bosses,
seats, callouts) the harness validates on every run; `CommanderGuideEngine.lua`
matches events to callouts and keeps the speech queue with no WoW API in
sight; `CommanderGuide.lua` only turns combat-log rows into the engine's
plain events and the engine's lines into speech, a banner and fontstrings.
Adding Gruul or a tank's seat is editing the data file only.

**D3. The voice is the client's own text-to-speech, not sound files.**
`C_VoiceChat.SpeakText` exists on this client with the CLASSIC signature
`(voiceID, text, rate, volume, overlap)` — no destination argument, unlike
retail; read out of the binary's usage string and
`VoiceChatDocumentation.lua` on `classic_anniversary`. Sound files would
mean recording every line, could not say a player's name, and would need
re-recording for every wording change. Text can be edited in place and
says "Garrote on Thrall".

**D4. Short in combat, long out of it.** A combat callout is at most
fourteen words (the validator enforces it), imperative, and says the
target's first name. The brief (one line plus your job) is spoken when you
TARGET a boss out of combat, once per boss every three minutes, because on
the pull it is too late to hear forty seconds of text. The full brief with
phases is a setting, off by default, for a first kill.

**D5. Urgent lines interrupt, routine lines queue, stale lines die.**
Priority 1 (Flame Wreath, Enfeebled, run, Blind) stops whatever is being
said and empties the routine lines behind it, because a pending "Garrote
on Thrall" is wrong the moment "Run out" is true. Priority 2 waits its
turn. Anything that sat in the queue longer than six seconds is dropped
unsaid: a six-second-old instruction is a lie. The client's
`VOICE_CHAT_TTS_PLAYBACK_FINISHED` advances the queue, with a timer
estimated from the word count as the net under it.

**D6. Two ways to know the boss, ENCOUNTER_START first.** The client's
`DungeonEncounter` table gives Karazhan ids 652–662 and `ENCOUNTER_START`
reports them; Commander_Meters has already written down that its firing
on Anniversary raids is unverified. So the fallback is the creature id
out of any combat-log GUID while in combat: the first row from Moroes
names the pull. The fallback closes six seconds after leaving combat; an
encounter-sourced pull waits for `ENCOUNTER_END` with a thirty-second net.

**D7. Cooldowns are per person for lines about a person.** Garrote on you
and Garrote on Thrall two seconds apart are two facts and two lines; the
same Garrote refreshing on Thrall inside three seconds is noise. Lines
about the boss (Vanish, Evocation) cool down as one. The harness caught
this: the first cut silenced the second Garrote.

**D8. `%t` is the first name, and "you" when it is you.** Every callout
about a person carries `%t`; `sayMe` is an optional second wording for
when the person is you, because "Garrote on you. Heal yourself between
casts." and "Garrote on Thrall. Keep a heal on them." are different
instructions, not the same sentence with a pronoun swapped.

**D9. The window is a plain reader, the banner is the only HUD.** The
window (boss list left, the seat's page right) opens with `/cguide`, a
keybind, or a target when Open-on-target is on (default off: a window
popping on a target is exactly the combat-layout oddity Devin rejects).
The banner is one fontstring under the suite's HUD chrome
(`Banner` prefix, style NONE by default) that writes each spoken line
for four seconds, so the voice can be off and the guide still works.

**D10. Facts came from the client and Wowhead, not memory.** Every spell
id in the data was checked by name against Wowhead's Anniversary tooltip
endpoint on 2026-09-28; creature ids against AtlasLoot's `data-tbc.lua`;
encounter ids against the client's own `DungeonEncounter` DB2 via
wago.tools. Wording of mechanics (Charge 8–25 yards, Intangible Presence
halves spell hit, Holy Wrath +40 % per jump, Sacrifice 1500 a second)
follows those tooltips. What no offline source can settle is in
ASSUMPTIONS.md.

**D11. The guide gets you to the door, through Commander Orders (1.1.0).**
Getting to the raid was the one part of a raid night the guide could not
help with, and Commander Orders is the suite's arrow. "Waypoint to
Entrance" (under the boss list, on the settings page, `/cguide entrance`
and a key binding) hands Orders one waypoint per raid under
(source `Guide`, key `entrance:<RAID>`), so pressing it twice moves one
waypoint rather than stacking two, and it clears itself on arrival like any
consumer mark. Where the door is comes from two places, in this order:
Orders' own entrance resolvers asked for the raid's uiMap
(`CommanderOrders.Entrance(350)`, fed by QuestLog from Questie when that is
loaded, then the client's `C_EncounterJournal` list), then
`D.ENTRANCES`, a nine-row table for every TBC raid keyed by instanceMapID.
A live resolver wins because it reads the same source the table was copied
from, and keeps up with corrections. The table's numbers are Questie's own
(`QuestieDB/support/Zones/dungeons.lua`, each TBC raid's dungeonLocations,
divided by 100; the zone areaIds turned into uiMapIDs with Questie's
`areaIdToUiMapId`), never remembered or estimated, and
`guide_engine_smoke.lua` section I re-checks every one against that data
and against the raid map's parent in the UiMap DB2. Karazhan has two doors
in Questie's row, so both go to Orders as alternatives and the arrow takes
the nearer. That holds through a resolver too: QuestLog's resolver answers
ONE point (Questie's first door, the northern 46.7, 70.2), so when a
resolver's point is one of the table's doors (same map, within 0.002) the
table's other doors ride along as alternatives (2026-10-04 review; before,
the suite's normal QuestLog + Questie setup always sent a raider to the
first door). A resolver point the table does not know is used alone. Orders
is optional and looked up at the press, never captured
at load: absent, the button prints the `/way #1430 46.70 70.20 Karazhan
entrance` line (it never does nothing); switched off, it says so and prints
the same line. Inside the raid the button is greyed out, because the door
is behind you and there is no position for an arrow anyway. Rejected: a
"walk me through the raid" route of boss waypoints (no position inside
instances), and a table of every dungeon (QuestLog's resolver already
answers dungeons from Questie; the guide only needs its raids).
