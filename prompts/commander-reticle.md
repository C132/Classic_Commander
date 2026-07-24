# Prompt — Commander Reticle: the cursor *is* the cast bar

> Feature brief for a new Commander suite module. Written before implementation so the
> intent, the constraints, and the full configuration surface are settled up front.

## The request

Add a new Commander feature that replaces the mouse cursor with a small radial cast bar
the same size as the cursor, carrying as much information as something cursor-sized can
carry. Think deeply about every configuration it should offer and every creative way to
be informative while staying compact.

## The root problem

Mouseover casting means the cursor sits **on the unit frame you are casting at**. The
arrow is ~32 px of opaque art parked exactly on top of the health bar, the incoming
damage, the debuff you were watching — precisely the information the cast is a reaction
to. You are blind to the thing you are aiming at, at the moment it matters most. The
traditional fixes are all compromises: move the cast bar away (now your eyes leave the
target), shrink the unit frames (now they are unreadable), or just accept the occlusion.

## The insight

The cursor is not just an occluder — it is the one thing on screen that is *always*
exactly where you are looking. So do two things at once:

1. **Stop occluding.** Draw a hollow ring (a donut with an empty middle) around the
   cursor hotspot, and optionally replace the arrow itself with a 2 px hotspot dot. A
   ring occludes nothing at its center; a dot occludes nothing at all.
2. **Carry the information the cursor is standing on.** If the ring reports the hovered
   unit's health, class, and range *on the cursor*, then it no longer matters what the
   cursor covers — you are reading the unit from the cursor instead of around it.

The cast bar becomes the cursor, the cursor becomes the unit frame, and your eyes never
leave the target.

## Design principles

- **Hollow by default.** The center is empty unless the player asks for something there.
  Every pixel drawn at the cursor must earn its occlusion.
- **Concentric, not stacked.** Each ring is one channel of information (cast, unit,
  global cooldown). Different radii, different visual languages: the cast arc *sweeps*,
  the unit dial is *segmented*. You should never confuse one for the other at a glance.
- **Peripheral-readable.** Color and arc length carry meaning; text is optional garnish.
  If you have to read a number, the design failed.
- **Zero interference.** Never takes the mouse, never eats a click, never taints a
  secure path. Cheap enough to run on an every-frame follow loop.
- **Everything off-switchable.** Every ring, marker, and flash is a flag. A player who
  only wants "a ring that fills while I cast" can have exactly that.

## Information model

Everything the module can say, and where it says it:

| Channel | Where | Encoding |
| --- | --- | --- |
| Cast progress | inner arc | radial sweep, fills (or drains) over the cast |
| Channel progress | inner arc | drains (or fills) — opposite of casts, so they read differently |
| Spell school / hostility | inner arc color | Frost blue, Fire red…, or friendly green vs hostile red |
| Global cooldown | thin ring | fast sweep on its own radius — "can I act yet" |
| Latency window | tick on the arc | where the next cast can be queued (`GetNetStats` world latency) |
| Pushback | arc | the arc simply retreats — `UNIT_SPELLCAST_DELAYED` moves the end time |
| Hovered unit health | outer dial | segmented pips, green → red, dark pips for missing health |
| Unit identity | dial rim | class color (friendly) or reaction color (hostile) |
| Unit in range | dial | dimmed when the spell cannot reach it |
| Cast target | dial source | mouseover / target / snapshot at cast start / smart |
| Time remaining | center | optional numeral, only if asked for |
| Spell icon | center | optional, dimmable — costs occlusion, so it is off by default |
| Spell name | label | optional single line below the ring |
| Success | whole ring | brief pop and fade |
| Interrupt / failure | whole ring | red flash, optional shake |
| Out of range / line of sight | whole ring | error-colored flash from `UI_ERROR_MESSAGE` |
| Combo points | pips | small dots under the ring |
| The click point itself | hotspot | dot / cross / plus, always exactly under the pointer |

## Configuration surface

Two settings pages, matching the Shield / Shield Extras precedent.

**Reticle** (core, `/creticle`, `/cret`)

- Master enable; Show When (Always / While Casting / Casting or Hovering / While
  Hovering / In Combat); Combat Only; hide while mouselooking.
- Ring size, ring thickness, overall opacity.
- Cast arc: on/off, fill or drain, channel direction, color mode (School / Class /
  Hostility / Fixed), fixed color.
- Center aperture: Empty / Spell Icon / Time Remaining / Target Health %, and its opacity.
- Unit dial: on/off, source (Mouseover / Target / Cast Target / Smart), segment count,
  class-colored rim, dim when out of range.
- Smart Dodge: nudge the ring off the frame it is hovering (Auto / Up / Down / Left /
  Right) and by how far. The hotspot never moves — only the ring steps aside.
- Test button, and the standard Restore Defaults.

**Reticle Extras** (scrollable second page, no slash)

- Global cooldown ring: on/off, thickness, color, inside or outside the cast arc.
- Latency marker, pushback tick.
- Feedback: success pop, failure flash, shake, error flash.
- Cursor replacement: hotspot style (None / Dot / Cross / Plus), size, color, and the
  opt-in **Hide System Cursor** experiment that swaps the OS arrow for a transparent
  texture so the hotspot is the whole pointer.
- Motion: follow smoothing, offset X/Y, frame layer.
- Extras: spell-name label, health percentage text, combo-point pips.

## What shipped against this brief

Built as written, with these deltas:

- **Health percentage text** landed as a center-aperture mode rather than a separate
  option — same information, one fewer switch.
- **Pushback** is reported as a flash plus the arc's own retreat (the sweep jumps back
  when the end time moves), not as a separate tick. The tick had nothing to mark: on a
  radial, the original end is always twelve o'clock.
- **Hide System Cursor does not work** with a transparent PNG on the live 2.5.6 client.
  Since `SetCursor` returns nothing and ignores a cursor it dislikes without complaint,
  all five plausible call forms ship as a selectable **Hiding Method** (TGA, PNG, path
  without suffix, empty path, clear) with a re-apply rate, and `/creticle cursor` walks
  them one press at a time. Treat "none of the five work" as a real possible outcome —
  in which case Smart Dodge is the answer and the arrow stays.
- Added beyond the brief: **demo mode** (`/creticle demo`), which fakes a looping cast
  and a draining target for twenty seconds so every option can be judged from the
  settings page without a target or a fight; and **Dial Style** (segmented vs solid) and
  **Dial Placement** (outside the arc vs inside the hole), which were choices the first
  pass made unilaterally and are better made by looking.

## Technical constraints (TBC Anniversary 2.5.5 / 2.5.6)

- Radial fills come from `Cooldown` frames (`CooldownFrameTemplate`) with a donut swipe
  texture — the client animates them, so a sweep costs nothing per frame. Guard every
  optional method (`SetSwipeTexture`, `SetHideCountdownNumbers`, `SetDrawEdge`) the way
  Commander_Shield does.
- Cursor position: `GetCursorPosition()` divided by `UIParent:GetEffectiveScale()`; the
  ring frame keeps scale 1 and is sized in pixels, because `SetPoint` offsets live in the
  frame's own scaled space.
- Cast data: `UnitCastingInfo` / `UnitChannelInfo` (the `CastingInfo()` globals are gone).
- Hovered frame rect for Smart Dodge: `GetMouseFoci()` on this framework, falling back to
  `GetMouseFocus()`; both `pcall`-guarded, both ignored when they resolve to WorldFrame.
- Spell school is not exposed by any TBC API — derive it from the spell name with a
  memoized keyword table (the same approach Commander_Casting already ships).
- The ring must never enable mouse, and must never be parented to `WorldFrame` (its own
  anchor family — see the Console viewport notes).
- Textures are generated POT RGBA PNGs, stdlib-zlib, the same pipeline as the Console
  strip art and the Afflictions circle mask.

## Non-goals

- No swing timer (a separate concern, and a combat-log tracker of its own).
- No custom cursor *art* — replacing the arrow means removing it, not redrawing it.
- No target-of-target, threat, or aura tracking on the ring: that is a unit frame's job,
  and this is a cursor.

## Acceptance criteria

1. Casting with the cursor parked on a mouseover unit frame, the health bar under the
   cursor is readable — nothing opaque is drawn over it, and the same health reads off
   the ring anyway.
2. The ring follows the cursor with no perceptible lag at default settings, and costs no
   measurable frame time when hidden.
3. Every option toggles live, with no `/reload` and no combat lockdown errors.
4. Turning the master switch off leaves precisely nothing on screen and no OnUpdate
   running.
5. `/creticle test` previews a full cast → success cycle without casting anything.
