# Commander_Quartermaster harness

Offline smoke checks that load the REAL shared framework
(`Commander_Events/CommanderSettingsUI.lua` + `CommanderEvents.lua`), the three
Quartermaster files, and Commander_Inventory (for the crate-button integration)
under a permissive WoW mock. Run both modes before shipping any change:

```
/opt/homebrew/bin/luajit quartermaster_harness.lua        # full run (~120 checks)
/opt/homebrew/bin/luajit quartermaster_harness.lua noqm   # Inventory without Quartermaster
```

The full run also loads `CommanderQuartermasterFringe.lua` and enforces its house
rule: fringe-spec picks (Shockadin, Smite, Subtlety, Demo Tank, Dreamstate) may only
reference item IDs the generated database already verified. The Lvl column is
covered in both faces — client item level in item lists, character level in the
Roster — including the sort-order correction when item info arrives late.

Coverage: login + ledger filing, the v1 close-race flushes (bank withdrawal
inside the coalesce window, the mail inbox-seen gate), tooltip count scoping
(realm scope, Track* gates, transit layer, alt breakdown), outbound-mail
transit (case-insensitive recipient match, merge, MAIL_FAILED discard,
unknown recipients, supersede-by-own-scan, 31-day login prune), deep token
search, era/source filters, column sorting, the watchlist (targets, badges,
stars, popup plumbing, reset survival), loadout readiness grades + both
GetTalentTabInfo shapes + played-class verdict isolation, the shopping list,
the raid supply check (dedupe window, sound, master toggle), the roster view
(hide/forget, gold, column relabel), slash dispatch, and the Inventory crate
button in both installed and absent worlds.

Mock lessons baked in (do not regress): auto-generated widget methods are
prefix-matched only so template-child property probes (`browser.TitleText`)
read nil unless the template mock provides them; `HookScript` CHAINS handlers
(the search box hooks a placeholder onto its own OnTextChanged); and
`C_Timer.After` feeds an executable queue because every scan and browser
refresh coalesces through it.
