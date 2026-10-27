# Swift Disk Cleanup

What can go from a Mac, and why — as data, with the evidence for every item and the safety checks that keep a cleaner from being the thing that deletes something it should not have.

```swift
import DiskCleanup

let catalogue = try Catalogue.builtIn()
let context = CleanupContext.live()
let report = Scanner.scan(catalogue: catalogue, context: context,
                          options: ScanScope(categories: [.xcode, .buildFolders]))
for total in report.categories {
    print(total.category, total.visibility, total.safeBytes)
}

let targets = try Planner.targets(["xcode"])
let plan = try Planner.select(targets, from: report, includeReview: false, olderThanDays: nil)
let outcomes = Remover.remove(plan.take, catalogue: catalogue, context: context)
```

The `diskmaid` CLI is the front end; this is everything it knows.

## Features

- 📋 **Rules are data** — a JSON catalogue compiled into the library (not a resource bundle, which a Homebrew-symlinked binary cannot find): `id`, `category`, `paths`/`globs`, `marker`, `owner`, `regenerable`, `tier`, `removal` (`trash`, `delete`, `sudo` — printed, never run — or the owner's command), `minAgeDays`, `protect`, `keepNewest`, `apps`, `note`. Read strictly — an unknown key is refused — and checked on every load: unique kebab ids, and no rule that removes anything may reach a protected path
- 🏷️ **Three tiers** — safe (goes with its category), review (by id, or when asked), report (shown, never cleaned) — and "held" items with the reason they stay
- 👁️ **Not visible is not zero** — a folder macOS refuses is `notVisible` (or `partial`), never 0 bytes
- 📏 **Honest sizes** — allocated blocks via fts, hard links once, blocks APFS clones share once (files of 64 KB and up), iCloud placeholders never opened; matches `du -sk` to the byte where there are no clones, and reads 52 MB where `du` reads 5.3 GB for 101 clones of one file
- 💿 **Installers judged by what they install** — DMGs attached read-only and hidden at a private mount point and always detached, encrypted and licence-agreement images never attached, packages read with `xar`, zips with `unzip -p`; dead only when the same or a newer version is installed. An `Install macOS ….app` is judged by the macOS version its own data names (`InstallInfo.plist`, or the software-update XML inside `SharedSupport.dmg`), so a release no name table knows still reads
- 🩶 **System Data, explained** — `SystemReader.read` gathers the volume's total, free and available-for-important-use space (so purgeable), local snapshots with dates, swap, the sleep image, the startup container's volumes by role, and — given a scan — the gap between apparent and clone-aware size (`Measurement.apparentBytes`, `Item.apparentBytes`); `SystemReader.lines` says what each figure means. Fixture homes read only tools in `<home>/bin`
- 🎛️ **Plugins** — `Plugins.inventory` lists audio, Quick Look, preference-pane, Internet and Safari plugins with vendor, version and architectures (`MachOText` reads fat and thin headers), and makes an item only of one that provably cannot load: AAX without Pro Tools, no arm64 slice on Apple silicon without Rosetta, an Internet plug-in, a .safariextz
- 🚀 **Startup items** — `Startup.list` describes launch agents and daemons, apps' SMAppService helpers and (asked) System Events' login items: program, owner app, team, loaded and disabled per launchctl, Apple's or not; `Startup.plan`/`remove` take one the uninstall way (`Restorer.undo(_:journal:context:)` bootstraps a restored agent), and `Startup.setEnabled` is launchctl disable/enable
- 🐘 **Big files** — `BigFiles.insidePackage` (public, also used by `diskmaid dupes`) says whether a file is part of a package; `Remover.refusal` asks the last door's question ahead of time, for a plan to show. `BigFiles.find` asks Spotlight through `mdfind`/`mdls` (fixture homes: only `<home>/bin`), reads `mdls -raw` batches (attributes come back in sorted name order; a batch that does not line up is read file by file), leaves out ~/Library, what a rule owns and anything inside a package, and lists protected places report-only; `BigFiles.select` picks by id or all
- 📈 **What changed** — `HistoryStore` saves each scan's sizes (capped, oldest dropped, only date-named files counted), finds the newest at or before a date, and `HistoryStore.changes` compares two scans over the categories both covered: `grewBytes`, `shrankBytes`, `netBytes`, and per item and category `deltaBytes` and `status`
- 🌳 **Where the space went** — `TreeSizer.tree` sizes a folder and everything `depth` levels down in one walk per top-level child, in parallel, each folder through its own clone tally (`CloneTally.add(_:allocated:)` shares one `getattrlist` per file); refused folders are `notVisible`, their parents `partial`. `Where.tree` adds labels from a scan that only looks (`ScanScope.measure = false`), folds small folders and sorts biggest first
- 🗑️ **Uninstall by evidence** — `Uninstaller.plan` resolves a .app, name, bundle id, package id, vendor or team id; matches installer receipts (only the deepest paths a package owns whole), ~/Library places named by bundle id, launch jobs, helpers, group containers and audio plug-ins; and sorts them exact / likely / review, demoting what another installed app shares. `Uninstaller.remove` refuses a running app unless asked to quit it, unloads its agents, trashes with the undo journal, and `Uninstaller.byHand` writes the one sudo line for root's part. Receipts, signatures, launchd and quitting go through `InstallRecords`, so fixtures never touch this Mac's
- 🧷 **The Dock icon, through cfprefsd** — an uninstall plan gets one exact item (`Removal.dock`) for the app's tiles in `persistent-apps` and `recent-apps`, matched by `bundle-identifier` or the app's file URL (`DockTiles`). Removing journals the exact arrays first (`JournalEntry.backup`, `.after`), writes the edited ones with CFPreferences, restarts the Dock and reads them back — a Dock that kept the icon is a failure (`RemovalOutcome.Result.edited` on success). `Restorer.undo` writes the originals back exactly unless the Dock changed since. The Dock is a `DockPreferences` (`SystemDockPreferences`; a fixture home gets `FileDockPreferences`, a plain plist and a stand-in `killall`); the catalogue can never name `dock`
- 🙈 **An ignore list** — `IgnoreList` entries name a path (it holds what is in it and what holds it), a rule or an item id; `CleanupContext.ignore` marks `Item.ignored` in scans, uninstall plans, big files and plugins, `CategoryTotal.ignoredBytes` counts them apart, `Selection` holds them, and the remover refuses them at the last door. `IgnoreStore.load` throws `.ignoreList` for a file it cannot read, never returns empty
- 🛠️ **Maintenance that does something** — `Maintenance.tasks` declares DNS flush, Spotlight re-index, Launch Services rebuild (`lsregister -r -f -all local,system,user`, then `-gc`; macOS 27 removed `-kill`), old logs (the `user-logs` rule, to the Trash with undo) and the Quick Look cache, each with what it fixes; `Maintenance.run` runs this user's through a `MaintenanceRunner` (fixtures: only `<home>/bin`), stops at the first failure, and gives root's back as `Maintenance.byHand`'s one line. No placebo tasks
- 🧬 **What apps are built with** — `AppStacks.scan` reads each app in /Applications (and its subfolders) and ~/Applications for the runtime it carries — Electron, Chromium Embedded, NW.js, Flutter, React Native, Qt, Unity, a bundled Java runtime, .NET's MonoBundle, an iPhone app's `Wrapper/`, Catalyst's `UIDeviceFamily` — with the file that decided (`StackRules`: the runtime decides, never an updater like Sparkle or Squirrel), the bundle's size, the runtime's own size, the Electron version (vendor suffixes dropped: `37.10.3-dropbox-…` is 37.10.3), the binary's architecture (`AppArchitecture`: apple-silicon, universal, intel — Rosetta's) and Spotlight's last-opened date, one `mdls` for all. A link like /Applications/Safari.app (into the system's sealed volume) is followed and measured where it points, each app counted once; invisible direction marks some apps put in their names are dropped. No match is not proof of native — a renamed runtime or a WebKit wrapper like Tauri reads as native
- 🔄 **Which apps are out of date** — `AppUpdates.check` asks each non-Apple app of the source that knows it best: the App Store's public lookup for an app with a `_MASReceipt`, the app's own Sparkle feed (`SUFeedURL`; `AppcastParsing` reads versions from items or enclosures and compares builds the way Sparkle does), else Homebrew's public cask catalogue (`UpdateCatalogues`: by the `.app` a cask installs, or the bundle id its uninstall step quits — package casks name no app), cached a day, a stale copy beating none. The installed version is always the app's own: Homebrew's record said one app was 10.1.1 after it had updated itself to 10.2.0. Anything that cannot be ordered, or a source that does not answer, is `unknown`, never current. The network goes through `UpdateFetching`, so tests never reach it
- 🩺 **Drive health** — `SystemReader.read` passes on the startup drive's own report from `diskutil info`: the SMART verdict and, for NVMe, life used, spare capacity against its threshold, media errors, bytes written (data units of 1,000 × 512 bytes), hours on, temperature (kelvin converted) and unsafe shutdowns, with a warning when one calls for a backup (`DiskHealthText`). Maintenance adds `verify-disk` (`diskutil verifyVolume`, read-only, ~8 s on a live volume, no root) and `icon-cache` (root's icon caches, a printed sudo line)
- 🧹 **Leftovers by exact bundle id** — every check must pass: app folders, running apps, launch jobs, LaunchServices and Spotlight (a timeout is not a "no"), 30 days untouched; tool-owned caches are never orphans
- 🔨 **Build folders only beside their marker** — `.build` with `Package.swift`, `target` with `Cargo.toml`; git-tracked, recent and app-bundle folders held; `CACHEDIR.TAG` respected
- 🎹 **App libraries outside the home** — Logic/GarageBand/MainStage and Reason sound libraries in `/Library`, found only when none of their apps is installed; root's, so only a `sudo` line is handed back (`HandBack.line`): the removal, then `pkgutil --forget` for receipts that list only files there — found by `--file-info`, never by name, and never ones macOS keeps under SIP in /Library/Apple/System/Library/Receipts, which are only counted in a note. Receipts whose files are gone are an item of their own. Fixtures read `<home>/root/Library`, never this Mac's
- 💬 **Chat stores that lost track** — WhatsApp's database read-only against its `Message/Media`: what no row lists is counted as evidence and a scan note
- 📱 **Device support by build** — the newest version, then build (a beta below any release of its train), per device model
- 🧠 **ML caches** — Core AI's compiled models split by OS build (another build's folder is dead after an update), Hugging Face per repo, Ollama per model
- 🛡️ **The last door** — just before removal each item's path safety and identity (device, inode, mtime, allocated size) are checked again
- ↩️ **Undo** — user-made things go to the Trash with a journal; `Restorer.undo` puts them back and never overwrites
- 🧪 **Fixture homes** — `CleanupContext.live(home:)` points everything at a stand-in home: its own app folder, its own `.Trash`, its own Dock plist, and commands only from `<home>/bin`, so tests can never run the real `brew cleanup` or `simctl delete`, or edit this Mac's Dock

## Measured

On a working development Mac a full scan takes 35–40 s for ~890 items; DerivedData, the uv cache and Core AI's cache all match `du -sk` byte for byte. Real installers made with `hdiutil`, `pkgbuild` and `zip` come out dead, pending-update, unknown and encrypted exactly as built (see the `diskmaid` README for the table).

## Credits

Written for this library in its own words. [Mole](https://github.com/tw93/Mole), [kondo](https://github.com/tbillington/kondo), [Pearcleaner](https://github.com/alienator88/Pearcleaner), [npkill](https://github.com/voidcosmos/npkill), [DevCleaner for Xcode](https://github.com/vashpan/xcode-dev-cleaner) and [czkawka](https://github.com/qarmin/czkawka) were read as references for where things live and which mistakes to avoid; no code or rule text was copied.

## Requirements

macOS 14+, Swift 6.2. No dependencies.

## License

MIT — see LICENSE.
