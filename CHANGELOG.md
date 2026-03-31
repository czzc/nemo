### v1.2.1

- feat: add "Sort by" option with Most Caught and Most Recent modes
  - New "Sort by" dropdown in settings panel with two modes: - Most Caught (default) - Most Recent: last caught item floats to the top of the list
  - Items caught before this update sort to the bottom in Most Recent mode until caught again.

### v1.2.0

- slight re-design of the main window
- feat: added font selection in the settings window to hopefully aid in supporting more languages

### v1.1.0

- fix: remove UnitName("target") call in LOOT_READY to resolve taint error

#### v1.0.7

- **Quiet Mode** (`/nemo quiet`) - compact, single-bar HUD showing only the zone name and catch count. Toggle between 'normal' view and 'quiet' mode via [-] / [+] buttons in the title bar, or via slash command. _**Note**: quiet mode and silent mode are mutually exclusive so enabling one will disable the other_
- **Item Blacklist** - `Community Coupons` is now filtered from catch tracking. Since it can be randomly awarded during fishing, but is not _technically_ caught.
- Number formatting; all displayed catch counts now use comma separators (e.g. `8,675` instead of `8675`). This applies to row counts, zone totals, session stats, minimap tooltip, bag tooltip, silent mode summary, and `/nemo session`
- Removed old v1.0 screenshots from the repo

#### v1.0.6

- **Silent mode** (`/nemo silent`): Hides the main frame and tracks catches in the background. Minimap icon pulses on new catches. Click the minimap button for a session summary in chat.
- **Minimap button**: Left-click toggles the frame, or prints a session summary while in silent mode. Tooltip shows your last 3 catches. Powered by LibDBIcon/LibDataBroker.
- Dark UI overhaul: pure black body (still configurable by the opacity slider), navy header/footer (non-configurable atm), gold accent default
- Custom Lucide-style TGA icons (hook, close, settings, resize)
- Fixed loot window closing (mailbox, corpses, etc) incorrectly resetting fishing state
- Currency drops (e.g. Shard of Dun'dun) now display their actual icon instead of a question mark
- Removed deprecated preferredIndex from reset confirmation dialog
- Auto-hide delay is now user-configurable (25–120s) via a slider that appears when auto-hide is enabled

#### v1.0.5

- github workflow changes

#### v1.0.4

- Fix NemoDB reassignment during v1 migration that could cause data loss
- Fix undefined behavior: mutating the table during pairs() iteration
- Extract SnapshotFishingTime() helper to deduplicate fishing time logic
- Fix typo in tooltip comment

#### v1.0.3

- Tightened fishing state detection; `isFishing` now resets on loot window close instead of persisting for 45 seconds, to prevent herbs, mining ores, and other non-fishing loot from being captured between casts
- Rewrote Voidstorm vortex loot detection to use `UNIT_SPELLCAST_CHANNEL_START` ("Void Hole Fishing") instead of guessing based on target/no-target, eliminating false positives from herbing and mining in Voidstorm
- Fixed Vortex target name mismatch ("Hyper-Compressed Ocean Target" vs "Hyper-Compressed Ocean")
- Strip Blizzard's crafting quality icons from item names at capture time, fixing `/nemo remove` failing on items like "Mana Lily" and "Tranquility Bloom" (and others)
- One-time migration to clean existing item names with those quality icons
- Deduplicated settings panel open logic into a single `OpenSettings()` function
- Cleaned up deprecated alert settings from saved variables
- Fixed forward declaration bug causing `sessionText` nil error on login

#### v1.0.2

- Changed timer display to only update text instead of rebuilding the full catch list every second
- Added tooltip cache for bag items hovers
- Added lifetime fishing timer
- Added confirmation popup for `/nemo reset` instead of needing to type it twice
- Fixed Voidstorm fishing state not resetting after loot window closes
- Fixed frame content not filling up available width when resizing
- Cleaned up deprecated settings from saved variables
- Fixed forward declaration bug that could cause login errors.
