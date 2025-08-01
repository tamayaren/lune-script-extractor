# Lune Roblox Script Extractor

A fast, cross-platform CLI tool built with [Lune](https://lune-org.github.io/docs/) and [Rokit](https://github.com/rojo-rbx/rokit) that extracts all exposed scripts (`ModuleScript`, `Script`, and `LocalScript`) from a Roblox `.rbxl` or `.rbxlx` place file into a clean, nested directory structure matching the place's DataModel hierarchy.

---

## Features

- **Blazing Fast**: Extracts hundreds of scripts in milliseconds using Lune's native binary parser (`@lune/roblox`).
- **Hierarchy Mirroring**: Recreates the exact parent-child hierarchy from the top service down to each script (e.g. `ServerScriptService/Core/Handler.luau`).
- **`.luau` File Extensions**: All scripts are saved with `.luau` extensions by default (with optional Rojo-style `.server.luau` / `.client.luau` naming).
- **`.robignore` Support**: Ignores scripts and parent containers matching rules in `.robignore`, following `.gitignore` syntax.
- **Collision Protection**: Automatically resolves naming collisions if duplicate scripts exist under the same parent (e.g. `Main.luau` and `Main (1).luau`), preventing any data loss.
- **Cross-Platform Safe**: Sanitizes folder and file names against invalid filesystem characters (`<>:"/\|?*`) and Windows reserved device names (`CON`, `PRN`, `AUX`, etc.).
- **Windows & Unix Ready**: Includes both a Bash shell script (`extract.sh`) and a Windows Command Prompt batch script (`extract.bat`).

---

## Prerequisites

- **[Rokit](https://github.com/rojo-rbx/rokit)** (Roblox toolchain manager)
- **[Lune](https://lune-org.github.io/)** (Managed automatically via `rokit.toml`)

If you have Rokit installed, run:
```bash
rokit install
```
This automatically installs Lune `0.10.5` as pinned in [rokit.toml](rokit.toml).

---

## Quick Start

### macOS / Linux
```bash
chmod +x extract.sh

# Automatically detects .rbxl file in the directory and extracts to output/<place_name>/
./extract.sh
```

### Windows (Command Prompt)
```cmd
:: Automatically detects .rbxl file in the directory and extracts to output\<place_name>\
extract.bat
```

---

## CLI Usage & Options

```text
Usage:
    ./extract.sh [place_file.rbxl] [output_dir] [options]
    extract.bat  [place_file.rbxl] [output_dir] [options]

Arguments:
    place_file.rbxl         Path to the Roblox place file (defaults to auto-detecting .rbxl in current dir)
    output_dir              Custom output directory (defaults to "output/<place_name>")

Options:
    --direct                Extract directly into "output/" rather than "output/<place_name>/"
    --rojo-ext              Use Rojo conventions (.server.luau, .client.luau, .luau)
    --ignore-file <path>    Specify a custom ignore file (defaults to ".robignore")
    -h, --help              Show usage information
```

### Examples

```bash
# 1. Extract a specific place file
./extract.sh test.rbxl

# 2. Extract into a custom output folder
./extract.sh test.rbxl my_scripts

# 3. Extract directly into output/ without a place subfolder
./extract.sh test.rbxl --direct

# 4. Extract using Rojo-style extensions (.server.luau, .client.luau, .luau)
./extract.sh test.rbxl --rojo-ext

# 5. Use a custom ignore file
./extract.sh test.rbxl --ignore-file custom.ignore
```

---

## `.robignore` File Filtering

The extractor looks for a file called `.robignore` in the working directory (or alongside the `.rbxl` file). It functions like `.gitignore`, allowing you to exclude scripts and parent containers.

### How Rules Work

- **Parent Container Match**: If an entry matches any parent or ancestor folder name (e.g. `Cmdr`, `Chat`, `Admin`), all scripts under that parent are skipped.
- **Path Matching**: Matches hierarchical paths (e.g. `StarterGui/Inventory` or `ServerScriptService/Core`).
- **Filename / Glob Matching**: Matches script names or wildcard patterns (e.g. `*.spec`, `Test*`).
- **Comments & Blank Lines**: Lines beginning with `#` and empty lines are ignored.
- **Negation (`!`)**: Un-ignores a file or folder that was excluded by a previous rule.

### Example `.robignore`

```gitignore
# Ignore all scripts under any parent/folder named "Cmdr"
Cmdr

# Ignore Roblox default chat scripts
Chat

# Ignore all scripts under a specific path
StarterGui/Inventory

# Ignore unit tests and spec scripts
*.spec
*.test

# Un-ignore a specific file that was matched above
!Cmdr/Shared/Util
```

---

## Project Files

- **`extract.luau`**: Core extraction engine using Lune's `@lune/roblox` and `@lune/fs`.
- **`extract.sh`**: Bash entry point for macOS and Linux.
- **`extract.bat`**: Native batch entry point for Windows Command Prompt.
- **`.robignore`**: Configuration file specifying ignore patterns.
- **`rokit.toml`**: Rokit toolchain manifest pinning the Lune version.
- **`test.rbxl`**: Test Roblox place file for experimentation.
