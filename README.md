# Spelunky 2 Mods

Various Mods for Spelunky 2

## Level Mods

* [Easy Mode](https://spelunky.fyi/mods/m/easy-mode/) - Modifies enemy and trap spawn rates to make the game easier
* [Cinematic Mode](https://spelunky.fyi/mods/m/cinematic-mode/) - Easy Mode too hard? Play for the lore, not the challenge.
* [Doublemint](https://spelunky.fyi/mods/m/doublemint/) - Double the spawn rates. Double the pain

## Script Mods

* [Poison Run](https://spelunky.fyi/mods/m/poison-run/) - You're always poisoned. Can you survive?
* [The Floor is Lava](https://spelunky.fyi/mods/m/the-floor-is-lava/) - Don't stay in one spot for too long, or you might just get burned...
* [Minimoose Frend](https://spelunky.fyi/mods/m/minimoose-frend/) - Adds a minimoose that follows you around

## Development

Every top level folder is an independent mod. `tools/mod.ps1` works on one at a
time, and takes the mod name or, with no name, whichever mod folder you're
standing in.

```powershell
.\tools\mod.ps1 list                # what's here, and what's currently synced
.\tools\mod.ps1 sync Roffto         # copy into the game so it can be played
.\tools\mod.ps1 package Roffto      # zip it for release into dist\
```

`sync` mirrors the mod into `Mods\Packs\<name>` in the Spelunky 2 install,
copying only what changed. It also deletes files the mod no longer ships, so a
renamed sprite doesn't keep running in the install. Modlunky's `mod_info.json`
is left alone.

`package` writes `dist\<Name>-<version>.zip`, taking the version from the `meta`
block in `main.lua`. The zip is flat, with `main.lua` and `Data\` at the root,
which is what Modlunky and spelunky.fyi expect when they extract a pack.

Both commands leave dev artifacts behind: source art (`*.psd`, `*.aseprite`,
...), editor and VCS files, OS junk. The full list is at the top of the script.
Add per mod exclusions in a `.modignore` file next to `main.lua`, one glob per
line. Add `-DryRun` to either command to see what would happen first, and
`-All` to do the whole repo at once.

The game is expected at the usual Steam location. If yours lives elsewhere:

```powershell
$env:SPELUNKY2_DIR = 'D:\SteamLibrary\steamapps\common\Spelunky 2'
```
