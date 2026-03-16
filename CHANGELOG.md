# Nemo Changelog

## v1.0.6

### Features

- **Silent mode** (`/nemo silent`): Hides the main frame and tracks catches in the background. Minimap icon pulses on new catches. Click the minimap button for a session summary in chat.
- **Minimap button**: Left-click toggles the frame, or prints a session summary while in silent mode. Tooltip shows your last 3 catches. Powered by LibDBIcon/LibDataBroker.

### General Updates:

- Dark UI overhaul: pure black body (still configurable by the opacity slider), navy header/footer (non-configurable atm), gold accent default
- Custom Lucide-style TGA icons (hook, close, settings, resize)

### Bug Fixes

- Fixed loot window closing (mailbox, corpses, etc) incorrectly resetting fishing state
- Currency drops (e.g. Shard of Dun'dun) now display their actual icon instead of a question mark
- Removed deprecated preferredIndex from reset confirmation dialog

### Settings

- Auto-hide delay is now user-configurable (25–120s) via a slider that appears when auto-hide is enabled
