# DINV - Durel's Inventory Manager (Mudlet Port)

Ported from the MUSHclient plugin `aard_inventory.xml` by Durel.

## Installation

1. **Copy the DINV folder** to your Mudlet profile directory:
   - Windows: `%APPDATA%\Mudlet\profiles\YourProfile\`
   - macOS: `~/Library/Application Support/Mudlet/profiles/YourProfile/`
   - Linux: `~/.config/mudlet/profiles/YourProfile/`

2. **Load the loader script** in Mudlet:
   - Open Mudlet and connect to Aardwolf
   - Go to `Scripts` editor
   - Create a new script group called "DINV"
   - Add a new script and paste the contents of `dinv_loader.lua`
   - Or use: `lua dofile(getMudletHomeDir() .. "/DINV/dinv_loader.lua")`

3. **Initialize DINV**:
   ```
   lua DINV.startup()
   ```

4. **Build your inventory** (required first time):
   ```
   dinv build confirm
   ```

## Module Structure

```
DINV/
├── dinv_loader.lua      -- Main entry point
├── dinv_dbot.lua        -- Core utilities (dbot namespace)
├── dinv_inv_core.lua    -- Inventory core (inv namespace)
├── dinv_inv_config.lua  -- Configuration
├── dinv_inv_items.lua   -- Item table management
├── dinv_inv_cache.lua   -- Item cache
├── dinv_inv_priority.lua -- Stat priorities
├── dinv_inv_score.lua   -- Item scoring
├── dinv_inv_set.lua     -- Equipment sets
├── dinv_inv_weapon.lua  -- Weapon sets by damage type
├── dinv_inv_snapshot.lua -- Equipment snapshots
├── dinv_inv_analyze.lua -- Optimal set analysis
├── dinv_inv_usage.lua   -- Item usage tracking
├── dinv_inv_compare.lua -- Item comparison
├── dinv_inv_statbonus.lua -- Stat bonus tracking
├── dinv_inv_consume.lua -- Consumables
├── dinv_inv_portal.lua  -- Portal usage
├── dinv_inv_pass.lua    -- Area passes
├── dinv_inv_regen.lua   -- Auto regen ring
├── dinv_inv_organize.lua -- Container organization
├── dinv_inv_keyword.lua -- Custom keywords
├── dinv_inv_tags.lua    -- Command completion tags
├── dinv_inv_unused.lua  -- Find unused equipment
├── dinv_cli.lua         -- Command-line interface
├── dinv_triggers.lua    -- Trigger definitions
└── dinv_aliases.lua     -- Alias definitions
```

## Commands

### Inventory Management
- `dinv build confirm` - Initial inventory scan
- `dinv refresh [on <min>|off|force]` - Refresh inventory
- `dinv search <query>` - Search inventory

### Equipment Sets
- `dinv set [wear|display] <priority> [level]` - Equipment sets (display rebuilds by default)
- `dinv priority [create|delete|list] <name>` - Manage priorities
- `dinv snapshot [create|wear|list] <name>` - Equipment snapshots
- `dinv weapon <priority> <damtypes>` - Weapon by damage type
- `dinv weapon next` - Next weapon type

### Analysis
- `dinv analyze [create|display|list] <priority>` - Optimal analysis
- `dinv compare <priority> <item>` - Compare items
- `dinv covet <priority> <auction#>` - Analyze auction item
- `dinv unused` - Find unused equipment
- `dinv unused store <container>` - Store unused items

### Item Actions
- `dinv get <query>` - Get items from containers
- `dinv put <container> <query>` - Put items in container
- `dinv store <query>` - Store in home containers
- `dinv portal <query>` - Use a portal
- `dinv consume [add|use] <type>` - Consumables

### Advanced
- `dinv backup [create|restore|list]` - Backup management
- `dinv progress <classic|inline|compact>` - Progress reporting style
- `dinv notify [none|light|standard|all]` - Notification level
- `dinv regen [on|off]` - Auto regen ring
- `dinv help [topic]` - Help system

## Quick Aliases
- `dinvs <query>` - Quick search
- `dinvp <portal>` - Quick portal
- `dinvw <priority> <damtype>` - Quick weapon swap
- `dinvset <priority>` - Quick set wear
- `dinvsnap <name>` - Quick snapshot wear
- `dinvnext` - Next weapon type

## Porting Notes

### Key Differences from MUSHclient Version:

1. **GMCP**: Uses native Mudlet `gmcp.*` tables instead of gmcphelper plugin
2. **Triggers**: Uses `tempRegexTrigger()` and event handlers
3. **Timers**: Uses `tempTimer()` with optional repeating
4. **Storage**: Uses Lua file I/O to Mudlet home directory
5. **Colors**: Converts @X codes to Mudlet cecho format
6. **Coroutines**: Native Lua coroutines (no wait.make dependency)

### Namespaces Preserved:
- `dbot.*` - Utility functions
- `inv.*` - Inventory functions
- All original function names maintained for compatibility

## License

Original plugin by Durel. Mudlet port maintains original functionality.
