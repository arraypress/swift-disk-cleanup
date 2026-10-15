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

- 📋 **Rules are data** — a JSON catalogue compiled into the library (not a resource bundle, which a Homebrew-symlinked binary cannot find): `id`, `category`, `paths`/`globs`, `marker`, `owner`, `regenerable`, `tier`, `removal`, `minAgeDays`, `protect`, `note`. Read strictly — an unknown key is refused — and checked on every load: unique kebab ids, and no rule that removes anything may reach a protected path
- 🏷️ **Three tiers** — safe (goes with its category), review (by id, or when asked), report (shown, never cleaned) — and "held" items with the reason they stay
- 👁️ **Not visible is not zero** — a folder macOS refuses is `notVisible` (or `partial`), never 0 bytes
- 📏 **Honest sizes** — allocated blocks via fts, hard links once, iCloud placeholders never opened; matches `du -sk` to the byte
- 💿 **Installers judged by what they install** — DMGs attached read-only and hidden at a private mount point and always detached, encrypted and licence-agreement images never attached, packages read with `xar`, zips with `unzip -p`; dead only when the same or a newer version is installed
- 🧹 **Leftovers by exact bundle id** — every check must pass: app folders, running apps, launch jobs, LaunchServices and Spotlight (a timeout is not a "no"), 30 days untouched; tool-owned caches are never orphans
- 🔨 **Build folders only beside their marker** — `.build` with `Package.swift`, `target` with `Cargo.toml`; git-tracked, recent and app-bundle folders held; `CACHEDIR.TAG` respected
- 🧠 **ML caches** — Core AI's compiled models split by OS build (another build's folder is dead after an update), Hugging Face per repo, Ollama per model
- 🛡️ **The last door** — just before removal each item's path safety and identity (device, inode, mtime, allocated size) are checked again
- ↩️ **Undo** — user-made things go to the Trash with a journal; `Restorer.undo` puts them back and never overwrites
- 🧪 **Fixture homes** — `CleanupContext.live(home:)` points everything at a stand-in home: its own app folder, its own `.Trash`, and commands only from `<home>/bin`, so tests can never run the real `brew cleanup` or `simctl delete`

## Measured

On a working development Mac a full scan takes 35–40 s for ~890 items; DerivedData, the uv cache and Core AI's cache all match `du -sk` byte for byte. Real installers made with `hdiutil`, `pkgbuild` and `zip` come out dead, pending-update, unknown and encrypted exactly as built (see the `diskmaid` README for the table).

## Credits

Written for this library in its own words. [Mole](https://github.com/tw93/Mole), [kondo](https://github.com/tbillington/kondo), [Pearcleaner](https://github.com/alienator88/Pearcleaner), [npkill](https://github.com/voidcosmos/npkill), [DevCleaner for Xcode](https://github.com/vashpan/xcode-dev-cleaner) and [czkawka](https://github.com/qarmin/czkawka) were read as references for where things live and which mistakes to avoid; no code or rule text was copied.

## Requirements

macOS 14+, Swift 6.2. No dependencies.

## License

MIT — see LICENSE.
