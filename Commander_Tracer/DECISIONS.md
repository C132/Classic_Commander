# Commander Tracer — decisions

Not to be re-litigated without a reason that is not already here.

**D1. The combat log is the feed, not COMBAT_TEXT_UPDATE.** Blizzard's text
events carry an amount and a type; the log carries the spell, its id (so an
icon), its school, its target, whether it crit, what was absorbed or
resisted, and who did it. Everything the stock text could never show comes
from that choice. The client's feed is read for exactly two things the log
does not carry: a reactive ability lighting up (SPELL_ACTIVE) and honor
(HONOR_GAINED).

**D2. Six lanes with ONE shared settings list.** Every lane offers the same
thirty-odd settings under its own prefix, plus the suite's four chrome
keys. A control that only applies to one motion is greyed rather than
hidden, so the page has one shape whatever a lane is set to. The
alternative -- bespoke pages per lane -- is how lanes drift apart in what
they can do. The ledger and the callouts differ from the number lanes only
by their DEFAULTS (stack / pop, longer duration, merge on, bigger face).

**D3. Kinds route to a lane AND optionally to the ledger.** Twenty-eight
kinds, each with a lane dropdown (any lane or Off) and a ledger flag. The
flag exists because the ledger is a second VIEW of the same event -- a
number scrolls past in the moment, the row lingers for the read-back --
and "both" is the common want. A kind routed to the ledger lane itself
ignores the flag rather than drawing twice.

**D4. Merging is per lane, on the lane's own clock, on a COPY of the
record.** A ledger row that merges six Fireballs must not change the amount
the number lane already drew for the first, so the ledger gets a copy.
Merge keys are kind + spell (not target), because Arcane Explosion on five
targets is one line, not five.

**D5. Self-damage is damage TAKEN; a self-heal is a heal of YOURS.** Hellfire
hurts you before it is your output; a Renew on yourself is a heal you cast.
One kind each, never both, so nothing draws twice.

**D6. The crit treatment is one flag.** Size, mark and punch all hang on
`rec.crit`; the big-hit threshold promotes a non-crit by setting the same
flag (and `rec.big`, so the crit CHIME does not ring for it). One rule, one
place, rather than a parallel "big" path through text, colour and motion.

**D7. Blizzard's text is taken over by CVar, with the old values kept in the
DB.** Not by hiding frames: the world numbers are engine-drawn and have no
frame. The backup lives in the saved variables so a removed addon leaves
its values readable, and Restore Defaults preserves it on purpose.

**D8. Stack rows never scale.** A punch on a row would shove its
neighbours; the merge punch on a stack lane is the accent widening instead.
Number lanes scale their frame and divide the anchor offset by the scale.

**D9. Fonts are the four the client ships.** Same rule as Party Frames'
header: a face that cannot go missing across a patch. Rune (SKURRI) is
offered because it is the face the old damage numbers used.

**D10. Sounds default to silent except the proc chime.** A combat text that
rings on every crit is a combat text people switch off. The proc chime is
the one sound whose whole value is that you were not looking.

**D11. Commander Impact keeps its edges; its words come here.** Impact is a
screen-edge language, this is a text language, so the modules stay apart.
But while Killing Blows are routed here, Impact skips its TARGET ELIMINATED
text (asking `CommanderTracer_Routes("KillingBlow")`), and its other words
(HONORABLE KILL) arrive as a Commander Banner. Superseded 2026-10-05 by D14;
before that the tooltip said to keep one of the two.

**D12. A locked lane never takes the mouse.** The shared HUD chrome keeps a
locked frame mouse-enabled (left-clicks passed through) for its triple
right-click unlock. A combat-text anchor is invisible and sits beside the
character, and a mouse-enabled patch there is a spot where a right-click
camera turn does not start. So `ApplyLane` disables the mouse on a locked
root right after the chrome runs; unlocking is the page's button or
`/ctracer unlock`. The unlocked drag overlay is untouched.

**D13. Stack rows clip their text.** Main and sub lines are anchored to both
edges of the row with wrapping off, so a long sentence is cut at the
backdrop rather than running out past it. Row Width is the control.

**D14. Nothing pops up over the middle of the view (1.1.0, 2026-10-05).**
Devin's ask: the text that fades in over the centre -- Killing Blow, X
ready, the zone name, the suite's banners -- made the view hard to read,
and should all go through this module; the scrolling numbers stay as they
are. So: the four moments default to the ledger (the Callouts lane stays,
routed to nothing, one dropdown away), and six CENTRE-SCREEN kinds were
added -- Zone Changes, Red Errors, Yellow Notices, Raid Warnings, Boss
Emotes, Commander Banners -- all defaulting to the ledger. A one-time
migration (`Migrated.CENTER_TEXT`) moves an existing install's moments off
"Call" only where they were still on that default.

**D15. Blizzard's centre text is taken by hook, read off the frame, and
handed back by routing Off.** `hooksecurefunc` on `FadingFrame_Show` (zone
frames), `RaidNotice_AddMessage` (raid warning, boss emote, and every boss
mod that writes there) and `UIErrorsFrame:AddMessage`, so nothing of
Blizzard's is replaced and no protected path is touched. The text is read
from what the frame was about to draw, not re-derived from events, so the
client's own rules (when a subzone counts, the sanctuary line, the error
throttle) stay the client's. Every hook re-reads the settings, so a kind set
Off (and no ledger row), the Take Over box unticked, or the module disabled
hands the frame straight back with nothing to restore. Sounds stay where
they were. The zone frames are put away on the NEXT tick: ZoneText_OnEvent
asks whether its own frame is shown, and hiding it inside the call makes
the client re-show the zone name as a subzone.

**D16. Commander banners ask, then step aside.** A module calls
`CommanderTracer_Notice{ text, sub, r, g, b, icon }`; true means taken and
the module skips its own banner but keeps its sound, false means draw your
own (Tracer absent, off, or Commander Banners routed Off). No dependency is
declared either way: the call is made at runtime, long after login.
