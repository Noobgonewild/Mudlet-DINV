# DINV for Aardwolf (Mudlet)

DINV is Durel's Inventory Manager, ported from MUSHclient to Mudlet and expanded with SQLite persistence, inventory tracking, equipment priorities, item analysis, reports, history, portals, consumables, and more.

DINV is an equipment and inventory manager. It works by itself; MMapper integration is optional.

> [!IMPORTANT]
> Your Mudlet profile does **not** have to be named `Aardwolf`.
>
> DINV uses `getMudletHomeDir()`, so it loads from whichever Mudlet profile is currently open. If your profile is named `Bob`, install DINV in the `Bob` profile directory.

> [!WARNING]
> **DO NOT RENAME THE ADDON FOLDER.** It must be named exactly **`DINV`** in uppercase or the loader will not find the Lua files.

## Quick installation

1. Download this repository with **Code > Download ZIP**, then extract the ZIP somewhere temporary.
2. Open the Mudlet profile in which you want to use DINV.
3. Enter this in Mudlet's command line to display that profile's exact directory:

   ```text
   lua getMudletHomeDir()
   ```

4. Close Mudlet.
5. Copy the complete **`DINV`** folder from the extracted repository directly into the profile directory shown in step 3. **Do not rename the folder.**
6. Reopen that Mudlet profile and connect to Aardwolf.
7. Open Mudlet's **Package Manager** (`Alt+O`), choose **Install New Package**, and select:

   ```text
   <Mudlet profile directory>/DINV/DINV.xml
   ```

   Do not install the repository ZIP itself as the Mudlet package.
8. Save the Mudlet profile.
9. Run the commands in [Verify the installation](#verify-the-installation).
10. Build the inventory database for the current character:

    ```text
    dinv build confirm
    ```

    Let the build finish. It scans all worn, carried, contained, and keyring items and identifies eligible items, so a large inventory can take several minutes.

## Required directory layout

The complete addon folder belongs directly inside the active Mudlet profile directory:

```text
<Mudlet profile directory>/
└── DINV/
    ├── DINV.xml
    ├── dinv_dbot.lua
    ├── dinv_database.lua
    ├── dinv_inv_core.lua
    ├── dinv_cli.lua
    ├── ...the rest of the DINV Lua files
    └── priorities/
        ├── navi.txt
        └── thief.txt
```

The folder name is case-sensitive on Linux and macOS and must be exactly `DINV`—not `dinv`, `Dinv`, or `Mudlet-DINV`.

Common incorrect layouts include:

```text
<profile>/Mudlet-DINV-main/DINV/...
<profile>/DINV/DINV/...
<profile>/dinv/...
```

After extracting the GitHub ZIP, copy the `DINV` folder **out of** the outer `Mudlet-DINV-main` folder. Do not place that outer folder in the Mudlet profile, and do not copy only `DINV.xml`; the XML loader needs all the accompanying `.lua` files.

### Typical profile locations

The exact path printed by `lua getMudletHomeDir()` is authoritative. Default locations usually look like:

- Windows: `C:\Users\<you>\.config\mudlet\profiles\<profile-name>`
- Linux: `/home/<you>/.config/mudlet/profiles/<profile-name>`
- macOS: `/Users/<you>/.config/mudlet/profiles/<profile-name>`

## Profile name, character name, and database location

The Mudlet profile name can be anything. DINV reads the active Aardwolf character name and creates a separate database directory for that character:

```text
<Mudlet profile>/dinv-database/<Character>/current/dinv.db
```

For example, character `Gizmo` in a profile named `My Aard Profile` uses:

```text
.../profiles/My Aard Profile/dinv-database/Gizmo/current/dinv.db
```

This separation means multiple characters may use DINV from the same Mudlet profile without sharing inventory data. Backups and editable priority files are stored beside each character's database:

```text
<Mudlet profile>/dinv-database/<Character>/
├── current/
│   └── dinv.db
├── backup/
└── priorities/
```

Do not move `dinv.db` into the `DINV` source folder. Do not rename it or overwrite it while Mudlet is open.

## Moving from MUSHclient or an older DINV

### Moving from MUSHclient

> [!IMPORTANT]
> **New client means a new DINV build.** The Mudlet version does not directly import MUSHclient's `aard_inventory` plugin state.

Install DINV normally, connect the character, and run:

```text
dinv build confirm
```

DINV will create a new per-character SQLite database and rebuild its inventory from Aardwolf. Do not copy MUSHclient plugin files or state files into the `DINV` source folder.

### Updating an older Mudlet DINV installation

Current DINV can perform a one-time import of recognized older Mudlet `.state` files when it creates an empty SQLite database. If the old installation and the new one use the same Mudlet profile, leave the old `dinv-*` character-data directories where they are and start DINV normally. Inventory, configuration, priorities, sets, snapshots, tags, and other recognized state are migrated when available.

The SQLite database becomes authoritative after migration. Check the result with:

```text
dinv help developer
```

If an old state file cannot be parsed, DINV reports the affected file and uses defaults for that module. Include the exact warning when reporting the problem.

## Verify the installation

After installing `DINV.xml` and connecting to Aardwolf, you should see messages similar to:

```text
[DINV] Initializing Durel's Inventory Manager ...
[DINV] Loaded ... modules
[DINV] Initialization complete!
```

Then run:

```text
dinv version
dinv help
dinv help developer
```

Expected results:

- `dinv version` displays the installed DINV version.
- `dinv help` displays the main command list.
- `dinv help developer` displays the current character, the exact `dinv.db` path, item counts, and `SQLite quick_check: ok`.

On a fresh installation, an active item count of zero is normal until the first build completes.

## First build and ongoing tracking

Run this once for every character that does not already have migrated DINV data:

```text
dinv build confirm
```

The build:

1. Scans worn equipment.
2. Scans the main inventory.
3. Scans known containers and the keyring.
4. Identifies eligible non-keyring items, followed by partial keyring items.

Useful build commands:

```text
dinv build status    show whether a build is running
dinv build abort     cancel the current build
dinv refresh         show inventory tracking status and counts
dinv refresh force   reconcile the tracked inventory immediately
```

After the initial build, DINV tracks ordinary inventory changes automatically. A forced refresh is for reconciliation; it is not required after every item change.

## Help and useful commands

Start with:

```text
dinv help
dinv help <command>
dinv query
```

`dinv query` explains searchable fields and tags. Most features also include examples under `dinv help <command>`.

| Command | Purpose |
| --- | --- |
| `dinv search basic <query>` | Search tracked items using DINV query fields |
| `dinv report <query>` | Display or report an item; ambiguous matches produce selectable IDs |
| `dinv history find <query>` | Find recorded item history |
| `dinv priority list` | List equipment-stat priorities |
| `dinv analyze create <priority> [level]` | Calculate an optimal equipment set |
| `dinv set wear <priority> [level]` | Calculate or wear an equipment set |
| `dinv usage <priority> [query]` | Show where items are used across levels |
| `dinv discover <type>` / `dinv discover scan [priority]` | Select a market type, then scan for possible upgrades |
| `dinv portal <query>` | Find and use a tracked portal |
| `dinv backup list` | List DINV database backups |
| `dinv notify` | Show INFO, WARN, and NOTE message settings |
| `dinv reload` | Reload all DINV Lua modules |

Command syntax can evolve. When in doubt, use `dinv help <command>` from the installed version.

## Equipment priorities

DINV's SQLite data is authoritative. Priority text files are editable import/export files stored per character in:

```text
<Mudlet profile>/dinv-database/<Character>/priorities/
```

Use DINV to create or export a priority, edit the resulting file, then import it:

```text
dinv priority create <name>
dinv priority export <name>
dinv priority locate <name>
dinv priority import <name>
```

`dinv priority locate <name>` prints the exact file path. The example files shipped in `DINV/priorities` are copied into the character's priority directory when that character becomes ready, without replacing files already there.

## Backups

Use DINV's backup commands while connected so SQLite creates a consistent snapshot:

```text
dinv backup list
dinv backup create before_changes
dinv backup restore before_changes
dinv backup delete before_changes
```

Named snapshots are stored under:

```text
<Mudlet profile>/dinv-database/<Character>/backup/<backup-name>/dinv.db
```

Do not manually replace the live `current/dinv.db` while Mudlet is open.

## MMapper integration

DINV does not require MMapper. If both current addons are installed in the same profile, MMapper can use DINV's public API for tracked portal and key information. Current mapped hand-held portal exits use commands beginning with:

```text
dinv portal use <object-id>
```

Configure the destination and level in MMapper, then use MMapper's portal help for its current commands. DINV remains responsible for finding and handling the physical item; MMapper remains responsible for route data.

## Troubleshooting

### DINV says required files or modules are missing

Compare the required location printed by the installation warning with `lua getMudletHomeDir()`.

- The complete folder must be `<profile>/DINV`.
- Its name must remain exactly `DINV`.
- Remove any extra `Mudlet-DINV-main` or second `DINV` nesting level.
- Make sure all `.lua` files were copied, not only `DINV.xml`.

After correcting the folder, reopen the profile.

### Mudlet sends `dinv` to Aardwolf or reports an unknown command

The DINV package or aliases did not load. Confirm that `DINV.xml` appears in Mudlet's Package Manager and inspect the main window for a red DINV installation or module error. Fix the reported folder/file problem, then reopen the profile.

### The database is unavailable or the character is `unknown`

DINV opens its database after it receives the connected character's information. Connect fully to Aardwolf and wait for initialization. If it remains unavailable, reconnect or reopen the profile, then run:

```text
dinv help developer
```

### DINV is installed, but there are no items

A fresh Mudlet port has no MUSHclient inventory to import. Run `dinv build confirm` and allow it to finish. Use `dinv build status` to check progress.

### A build is stuck or was interrupted

Check it with `dinv build status`. If it cannot continue, run `dinv build abort`, wait for cancellation, and start a new `dinv build confirm`.

### Priority edits do not appear in DINV

Do not edit only the example under `DINV/priorities`. Run `dinv priority locate <name>`, edit the per-character file it reports, save it, then run `dinv priority import <name>`.

### `dinv reload` says DINV is busy

Reload deliberately waits for builds, refreshes, backups, item operations, reports, and similar workflows to finish. Let the named operation complete or cancel it with its own command, then run `dinv reload` again.

### SQLite reports an error

Stop inventory operations and run `dinv help developer`. Do not repeatedly rename or overwrite database files. Include the database path, `SQLite quick_check` result, and exact error text in a bug report.

## Updating DINV

1. While connected and idle, create a consistent snapshot:

   ```text
   dinv backup create before_update
   ```

2. In Package Manager, remove the existing `DINV` package entry. The profile-level database is separate and is not removed with the package entry.
3. Close Mudlet.
4. Replace the old `DINV` source folder with the complete `DINV` folder from the new release. **Keep the folder name exactly `DINV`.**
5. Do not delete or replace the profile-level `dinv-database` folder.
6. Reopen the profile. In Package Manager, choose **Install New Package** and select the new `DINV/DINV.xml`.
7. Save the profile, reconnect, and run `dinv version` and `dinv help developer`.

For a development update that changes only loose `.lua` files, the verified `dinv reload` command reloads all DINV Lua modules. Reinstall `DINV.xml` whenever that XML file also changed.

## Feature preview

### Search

DINV search supports item fields and query filters:

<img width="1430" height="294" alt="DINV search results" src="https://github.com/user-attachments/assets/3dc5f600-55bd-43c9-a909-2a2e8211bdaf" />

<img width="1435" height="206" alt="DINV filtered search results" src="https://github.com/user-attachments/assets/fbf74f14-9e73-4de7-8e5b-cb3d222c5f96" />

### Equipment discovery

`dinv discover` finds possible upgrades and scores them against defined priorities:

<img width="1571" height="812" alt="DINV equipment discovery" src="https://github.com/user-attachments/assets/2164dbba-18f5-4d37-908f-3e31d27ec41b" />

Level-up checks can test whether newly available equipment improves the current set. The feature can be disabled.

<img width="769" height="45" alt="DINV level-up equipment check" src="https://github.com/user-attachments/assets/caf96525-0126-4b11-a173-927a5f707111" />

### Item reports

If a report query matches several items, DINV displays their IDs so the intended item can be selected and reported through the configured channel. The default channel is local echo.

<img width="1409" height="159" alt="DINV item report" src="https://github.com/user-attachments/assets/f4bbae43-1464-41b6-aedf-79531dc9e2e0" />

### Usage analysis

Usage analysis helps find items that are—or are not—used by defined priorities and can help store unused items in a container.

<img width="770" height="133" alt="DINV usage analysis" src="https://github.com/user-attachments/assets/9adbc653-6b5e-46ce-a7eb-312bf75bc505" />

### Consumables

DINV can manage and purchase configured potions and pills.

<img width="1036" height="522" alt="DINV consumables" src="https://github.com/user-attachments/assets/58ce4d22-5e51-4820-beaf-59205bfbf43c" />

### Progress display

Identification progress can use classic lines, a compact inline display, or be hidden. See `dinv help progress`.

[View the inline progress demo](https://github.com/user-attachments/assets/22d4788e-7308-4326-8d5f-48e00175275b)

### Inventory history

Inventory history tracks item events over time.

<img width="774" height="545" alt="DINV inventory history" src="https://github.com/user-attachments/assets/a30694d5-b1a9-43df-82d9-be1e9d1b60bd" />

Most informational messages can be adjusted with `dinv notify`. As always, use at your own risk, report reproducible bugs, and include the exact warning or error text.

## Useful references

- [Mudlet Package Manager](https://wiki.mudlet.org/w/Manual%3APackage_Manager)
- [Mudlet `getMudletHomeDir()` documentation](https://wiki.mudlet.org/w/Manual%3AMiscellaneous_Functions#getMudletHomeDir)
- [Mudlet profile file locations](https://wiki.mudlet.org/w/Mudlet_File_Locations)
