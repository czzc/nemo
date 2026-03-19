#### v1.0.7

- **Quiet Mode** (`/nemo quiet`) - compact, single-bar HUD showing only the zone name and catch count. Toggle between 'normal' view and 'quiet' mode via [-] / [+] buttons in the title bar, or via slash command. _**Note**: quiet mode and silent mode are mutually exclusive so enabling one will disable the other_
- **Item Blacklist** - `Community Coupons` is now filtered from catch tracking. Since it can be randomly awarded during fishing, but is not _technically_ caught.
- Number formatting; all displayed catch counts now use comma separators (e.g. `8,675` instead of `8675`). This applies to row counts, zone totals, session stats, minimap tooltip, bag tooltip, silent mode summary, and `/nemo session`
- Take into account the fact that Angler Anomaly's are a thing that can create an `Oceanic Vortex` in any zone - and count those as well towards the catch totals
- Removed old v1.0 screenshots from the repo
