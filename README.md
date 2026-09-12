# DINV — Durel's Inventory Manager for Aardwolf (Mudlet)

DINV ported from MUSHclient to Mudlet, featuring numerous enhancements, SQLite database backing, and full priority equipment set management. (Love you, Durel! We all know it and love it!)

---

## Key Highlights

> [!NOTE]
> **Download anywhere, install from anywhere!**
> You can download `DINV.mpackage` to **any folder on your computer** (such as your `Downloads` folder or Desktop). There is **no need** to move the file into your Mudlet directory before installing.
> - If you download `DINV.mpackage` directly, you do **not** need to extract it; Mudlet handles package installation automatically.
> - If you downloaded the repository archive via GitHub's **`Code` > `Download ZIP`**, **unzip / extract** that ZIP archive first on your computer to reveal `DINV.mpackage` inside. Do **not** import the repository ZIP file itself into Mudlet.

> [!IMPORTANT]
> **Your Mudlet profile does not have to be named `Aardwolf`.**
> DINV uses `getMudletHomeDir()` to load files from whichever Mudlet profile is currently active. Your inventory databases are safely organized per character in `<profile>/dinv-database/<character-name>/`.

---

## Installation

### Step 1: Download the Package

You can obtain the package in either of two ways:

- **Direct Download (Recommended):** Download [`DINV.mpackage`](https://raw.githubusercontent.com/Noobgonewild/Mudlet-DINV/main/DINV.mpackage) directly to anywhere on your computer (such as your `Downloads` folder or Desktop).
- **GitHub ZIP (`Code` > `Download ZIP`):** If you downloaded the repository as a ZIP archive (`Mudlet-DINV-main.zip`), **unzip / extract** the archive first. `DINV.mpackage` is located inside the extracted folder.

> [!IMPORTANT]
> **Do not import the repository ZIP file into Mudlet.** Mudlet only installs `.mpackage` files.
> Once you have `DINV.mpackage`, do **not** unzip or extract the `.mpackage` file itself — Mudlet installs it directly.

---

### Step 2: Install into Mudlet

Open Mudlet and connect to your Aardwolf character/profile (so your main game terminal window is open and active). Then install the package using either method below:

#### Option A: Package Manager (Recommended)

1. In Mudlet, open the **Package Manager**:
   - Press `Alt+O`, or
   - Click **Toolbox** > **Package Manager** from the menu.
2. Click **Install** (or **Install New Package**).
3. Navigate to wherever you downloaded `DINV.mpackage` (e.g., your `Downloads` folder).
4. Select `DINV.mpackage` and click **Open** to install.
5. Save your Mudlet profile.

#### Option B: Drag and Drop (Fresh Installations)

> [!NOTE]
> Drag and drop is best suited for fresh, first-time installations. If you already have an older version of DINV installed, Mudlet will not overwrite it via drag-and-drop — you must first uninstall the old package in **Package Manager** (`Alt+O`) or use **MCheck** to update automatically.

1. Make sure your active Mudlet game window is visible on screen.
2. Open your file browser to where you downloaded `DINV.mpackage`.
3. Drag and drop **`DINV.mpackage`** directly onto the open Mudlet window.

---

### Step 3: Build Your Initial Inventory Database

Once installed and connected to Aardwolf:

1. Type the following command in Mudlet to scan your carried inventory, equipped gear, and containers into DINV's SQLite database:
   ```text
   dinv build
   ```
2. Allow the scan to complete. DINV will index and catalog all items with their stats, flags, and locations.
3. Verify that DINV is ready by typing:
   ```text
   dinv version
   ```

---

## Key Commands & Aliases

DINV provides comprehensive inventory search, equipment sets, stat comparison, and item utilities:

### Core Commands

| Command | Description |
| :--- | :--- |
| `dinv help` | Show general DINV help and topic overview |
| `dinv help <topic>` | View detailed help for a specific command (e.g., `dinv help search`, `dinv help query`) |
| `dinv build` | Scan and rebuild the active character's inventory database |
| `dinv search <query>` | Search your items using DINV's rich query engine |
| `dinv set wear <priority>` | Equip your highest-priority gear set |
| `dinv snapshot save <name>` | Save your currently worn equipment as a named snapshot |
| `dinv snapshot wear <name>` | Re-equip a previously saved snapshot |
| `dinv weapon <priority> <type>` | Swap weapons matching a given priority and damage type |
| `dinv portal <target>` | Locate and enter a portal matching your target destination |
| `dinv unused` | List carried or stored items not used in any priority gear set |
| `dinv compare <item1> <item2>` | Compare stats between two items |
| `dinv config` | View and modify DINV settings |

### Quick Aliases

DINV includes convenient shorthand aliases for high-frequency actions:

| Alias | Full Equivalent | Description |
| :--- | :--- | :--- |
| `dinvs <query>` | `dinv search <query>` | Quick search |
| `dinvp <target>` | `dinv portal <target>` | Quick portal |
| `dinvw <priority> <damtype>` | `dinv weapon <priority> <damtype>` | Quick weapon swap |
| `dinvset <priority> [level]` | `dinv set wear <priority> [level]` | Quick set equip |
| `dinvsnap <name>` | `dinv snapshot wear <name>` | Quick snapshot equip (or `dinvsnap` to list) |
| `dinvnext` | `dinv weapon next` | Cycle to next matching weapon |
| `dinvcovet <priority> <#>` | `dinv covet <priority> <#>` | Evaluate an auction item against your priorities |

---

## Updating the Add-on

Updating is safe because package updates never touch or overwrite your personal inventory database:

### Via MCheck (Recommended — Fully Automated)
If you use [MCheck](https://raw.githubusercontent.com/Noobgonewild/Mudlet-scripts/main/mcheck-index.json), it detects installed add-ons, downloads verified packages, and handles the uninstall and reinstall cycle automatically.

> [!NOTE]
> MCheck scans and updates add-ons that are **already installed** in your active profile. It cannot perform a first-time installation of an uninstalled add-on. Once you have installed the package once via Option A or B above, MCheck manages all future updates seamlessly:

```text
mcheck scan
mcheck update <number>
```

### Via Package Manager (Manual Update)
Because Mudlet will not overwrite an existing package via drag-and-drop or direct re-installation, you must uninstall the old package first:

1. Download the new `DINV.mpackage` anywhere on your computer.
2. Open Mudlet's **Package Manager** (`Alt+O`).
3. Select **`DINV`** and click **Uninstall**.
   *(Note: Uninstalling the package only removes the scripts/triggers; your `dinv-database/` folder, item history, snapshots, and settings remain completely intact).*
4. Click **Install** (or drag and drop the newly downloaded file onto the Mudlet window) to install the updated version.
5. Save your profile or reload if needed.

---

## Database & File Storage

DINV stores SQLite databases separately for each of your characters inside the active Mudlet profile directory:

```text
<Mudlet profile directory>/
└── dinv-database/
    └── <CharacterName>/
        ├── current/
        │   └── dinv.db          Active SQLite database for this character
        └── backup/
            └── ...              Automated rolling database backups
```

To reveal your Mudlet profile folder in your operating system's file browser, type this command in Mudlet:

```text
lua openMudletHomeDir()
```

*(On older Mudlet versions, use `lua getMudletHomeDir()` to print the path).*

---

## Troubleshooting

### Installation warning: "DINV was not loaded"
This indicates that Mudlet could not locate the required Lua modules. Reinstall `DINV.mpackage` through **Package Manager** (`Alt+O`) and save your profile.

### No items appear in searches
Run `dinv build` while connected to Aardwolf. DINV populates its database by querying your worn equipment, inventory, and carried containers.

### Updating via Drag and Drop does nothing or gives an error
Mudlet prevents overwriting existing packages. Open **Package Manager** (`Alt+O`), select `DINV`, click **Uninstall**, and then install the new package. Your database in `dinv-database/` will remain safe.

---

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

Usage analysis helps find items that are-or are not-used by defined priorities and can help store unused items in a container.

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

---

## Useful References

- [Mudlet Package Manager Documentation](https://wiki.mudlet.org/w/Manual%3APackage_Manager)
- [Mudlet File Locations](https://wiki.mudlet.org/w/Mudlet_File_Locations)
- [MMapper and S&D Repository](https://github.com/Noobgonewild/Mapper-and-S-D)
- [Mudlet Scripts Repository](https://github.com/Noobgonewild/Mudlet-scripts)
- [MCheck Addon Index](https://raw.githubusercontent.com/Noobgonewild/Mudlet-scripts/main/mcheck-index.json)

